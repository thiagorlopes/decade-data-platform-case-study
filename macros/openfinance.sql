{# Typed extraction of one JSON field, used by the staging models.

   Casting policy: json_extract_string already returns VARCHAR, so VARCHAR
   targets get no cast; everything else uses TRY_CAST so malformed provider
   values surface as NULL and are caught by the warn-severity not_null tests
   in _staging_quality.yml instead of crashing the view. `required` only
   documents what the OFB spec mandates. #}
{% macro json_field(column, prefix, path, type, required) -%}
    {%- set expr = "json_extract_string(" ~ column ~ ", '" ~ prefix ~ path ~ "')" -%}
    {%- if type == 'VARCHAR' -%}
        {{ expr }}
    {%- else -%}
        TRY_CAST({{ expr }} AS {{ type }})
    {%- endif -%}
{%- endmacro %}

{# positions payload_json carries the API response envelope, hence $.data. #}
{% macro payload_field(path, type, required=false) -%}
    {{ json_field('payload_json', '$.data.', path, type, required) }}
{%- endmacro %}

{# transaction_json is flat (no $.data wrapper). #}
{% macro txn_field(path, type, required=false) -%}
    {{ json_field('transaction_json', '$.', path, type, required) }}
{%- endmacro %}

{# --- within-record repairs (notebook 02), applied in the intermediate layer
   so the staging warn tests keep counting the raw defects. --- #}

{# Used on the columns that feed natural keys (isin, ticker, product_name):
   a blank string passes IS NOT NULL and would silently fragment those keys. #}
{% macro blank_to_null(column) -%}
    nullif(trim({{ column }}), '')
{%- endmacro %}

{# Providers serialize CNPJs through a numeric type and pick up a decimal
   tail ('92894922000108.00'). Strip the tail, then demand exactly 14 digits;
   anything else degrades to NULL (regexp_extract returns '' on no match). #}
{% macro clean_cnpj(column) -%}
    nullif(regexp_extract(regexp_replace({{ column }}, '\.[0-9]+$', ''), '^[0-9]{14}$'), '')
{%- endmacro %}

{# 'IPC-A' is the market's spelling of the OFB enum value 'IPCA'. #}
{% macro clean_indexer(column) -%}
    CASE {{ column }} WHEN 'IPC-A' THEN 'IPCA' ELSE {{ column }} END
{%- endmacro %}

{# 0001-01-01 is .NET DateTime.MinValue and 1970-01-01 is Unix epoch zero:
   missing dates in a date costume. #}
{% macro clean_missing_date(column) -%}
    CASE WHEN {{ column }} IN (DATE '0001-01-01', DATE '1970-01-01') THEN NULL ELSE {{ column }} END
{%- endmacro %}

{# Incremental filter for the int_*_positions models: admit whole snapshots,
   not single rows. resolve_duplicate_investments compares rows within one
   sync, so a late or re-delivered row must be re-judged together with the
   siblings that already landed; a row-level watermark would classify it
   alone and admit both copies. The (snapshot_id, investment_id) unique_key
   turns the re-touched rows into an upsert, keeping reruns idempotent. #}
{% macro snapshot_watermark(staging_refs) -%}
snapshot_id IN (
    {%- for staging_ref in staging_refs %}
    SELECT snapshot_id FROM {{ staging_ref }}
    -- Use >= not >. One arrival batch shares one ingested_at stamp, so a
    -- run that reads it while it is still landing must read that stamp
    -- again next run, or the rest of the batch never reaches downstream.
    -- Reruns re-touch the boundary snapshots; the upsert keeps that idempotent.
    WHERE ingested_at >= (SELECT max(ingested_at) FROM {{ this }})
    {{ 'UNION' if not loop.last }}
    {%- endfor %}
)
{%- endmacro %}

{# The provider can deliver the same lot twice with different values.
   This macro keeps the newest copy of each (snapshot_id,
   investment_id), by ingested_at. The older copies are not lost: they
   stay in staging, and the lot_redelivery warn ledger counts them.
   "Newest" always picks exactly one row, because the staging grain
   test fails the build when two copies share the same ingested_at. #}
{% macro latest_lot_delivery(staging_ref) -%}
(
    SELECT * FROM {{ staging_ref }}
    QUALIFY row_number() OVER (
        PARTITION BY snapshot_id, investment_id
        ORDER BY ingested_at DESC
    ) = 1
)
{%- endmacro %}

{# --- Classifies duplicate investment_ids per natural key and stamps
   each row with an admission verdict (notebook 03). Shared by every
   int_*_positions model, so the five families agree on what counts as
   a duplicate and how to resolve one.

   The caller provides a CTE named `with_natural_key` with the columns
   `snapshot_id`, `account_id`, `natural_key`, `investment_id`,
   `gross_amount`, and the quantity column named by `qty_col` (default
   `quantity`; funds pass `quota_quantity`).

   The caller gets back the final SELECT of the model: every input
   column plus `admission` (admit / reject_duplicate /
   reject_zero_duplicate / quarantine) and `data_quality_flags` (an
   array of defect labels).

   With `extra_flags`, a family appends its own (condition, label)
   pairs to data_quality_flags. This carries the missing-field
   signals, like ('indexer IS NULL', 'indexer:missing'). --- #}
{% macro resolve_duplicate_investments(qty_col='quantity', extra_flags=[]) -%}
-- Step 1: find the duplicate groups. A duplicate group is one natural key
-- held by two or more investment_ids within the same sync.
duplicate_groups AS (
    SELECT
        snapshot_id,
        account_id,
        natural_key,
        count(*)                          =  2   AS is_pair,
        count(DISTINCT {{ qty_col }})    <= 1    AS quantities_agree,
        count(DISTINCT gross_amount)     <= 1    AS gross_amounts_agree,
        count(*) FILTER (WHERE gross_amount > 0) AS n_positive_gross_amounts
    FROM with_natural_key
    WHERE natural_key IS NOT NULL
    GROUP BY ALL
    HAVING count(DISTINCT investment_id) > 1
),

-- Step 2: hand each investment the stats of its duplicate group.
-- Investments in no group (unique key, or no key at all) get NULL stats.
with_group_stats AS (
    SELECT
        with_natural_key.*,
        dup.natural_key IS NOT NULL AS is_in_duplicate_group,
        dup.is_pair,
        dup.quantities_agree,
        dup.gross_amounts_agree,
        dup.n_positive_gross_amounts
    FROM with_natural_key
    LEFT JOIN duplicate_groups AS dup
        ON  with_natural_key.snapshot_id = dup.snapshot_id
        AND with_natural_key.account_id  = dup.account_id
        AND with_natural_key.natural_key = dup.natural_key
),

-- Step 3: classify each investment (notebook 03 §2).
classified AS (
    SELECT
        *,
        CASE WHEN natural_key IS NULL           THEN 'natural_key:missing'  -- no key, cannot check for duplicates
             WHEN NOT is_in_duplicate_group     THEN 'sole_lot'
             WHEN NOT quantities_agree          THEN 'separate_lots'
             WHEN gross_amounts_agree           THEN 'redundant_copies'
             ELSE 'conflict'                                        -- same quantity, gross disagrees
        END AS dup_class,
        -- The exact shape notebook 03 §3 asserts before resolving: a pair,
        -- one positive side, shared positive quantity. Anything else quarantines.
        dup_class = 'conflict'
            AND is_pair
            AND n_positive_gross_amounts = 1
            AND coalesce({{ qty_col }}, 0) > 0 AS is_resolvable_conflict,
        -- Rank 1 is the copy redundant_copies keeps: prefer a priced one,
        -- then lowest investment_id for determinism.
        row_number() OVER (
            PARTITION BY snapshot_id, account_id, natural_key
            ORDER BY (gross_amount IS NULL), investment_id
        ) AS dedup_rank
    FROM with_group_stats
)

-- Step 4: the admission verdict, plus the defect flags.
SELECT
    * EXCLUDE (is_in_duplicate_group, is_pair, quantities_agree,
               gross_amounts_agree, n_positive_gross_amounts, dup_class,
               is_resolvable_conflict, dedup_rank),
    CASE
        WHEN dup_class = 'redundant_copies' AND dedup_rank > 1 THEN 'reject_duplicate'
        WHEN is_resolvable_conflict
             AND coalesce(gross_amount, 0) = 0         THEN 'reject_zero_duplicate'
        WHEN dup_class = 'conflict'
             AND NOT is_resolvable_conflict            THEN 'quarantine'
        ELSE 'admit'
    END AS admission,
    list_filter([
        CASE WHEN natural_key IS NULL THEN 'natural_key:missing' END,
        CASE WHEN is_resolvable_conflict AND gross_amount > 0
             THEN 'lot:zero_copy_dropped' END{% for cond, label in extra_flags %},
        CASE WHEN {{ cond }} THEN '{{ label }}' END{% endfor %}
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM classified
{%- endmacro %}

{# Collapses duplicate movements that hide under different
   investment_ids of the same holding.

   The provider sometimes delivers a movement again under another of
   the holding's investment_ids, and gives the copy a new
   transaction_id. int_*_transactions dedups within each id, so both
   copies pass through to this macro.

   The macro compares content, not ids:
   - Two movements are the same event if they agree on every business
     field: holding, date, type, quantity, amount, currency.
   - If the same event appears twice under one id, keep one copy.
   - If the same event appears under two ids that were ever admitted
     together in one sync with different gross amounts, keep both.
     Such ids are real lots (flagged investment_id:multiple), and the
     same movement on two real lots is two real events. The
     different-gross requirement stops placeholder-quantity copies
     from passing as real lots.
   - A movement with no identical twin is always kept. After an id
     replacement, the retired id may hold the only record of old
     history.

   Of the copies, the first-delivered one survives; on a tie, the
   lowest investment_id does. So a copy that arrives later can never
   take over from a transaction_id that earlier builds already
   published to consumers.

   Emits a subquery: the deduped movement stream, with holding_key and
   a had_cross_id_twin flag on each surviving copy. #}
{% macro cross_id_movements(transactions_ref, positions_ref, date_col='transaction_date', qty_col='transaction_quantity', gross_col='transaction_gross_amount') -%}
(
    WITH
    -- which holding does each investment_id belong to. max, not any_value:
    -- order-independent if a provider ever re-keys an id.
    holding_of AS (
        SELECT investment_id, max(natural_key) AS natural_key
        FROM {{ positions_ref }}
        GROUP BY investment_id
    ),

    -- Pairs of ids that were both admitted in one sync: the provider
    -- valued both as live money at once, so they are two real lots of
    -- the holding, not a record and its copy. The differing-gross
    -- condition filters out fakes: lots share one price per sync, so
    -- two real lots with different quantities cannot show the same
    -- gross. A pair with identical gross is a duplicated record whose
    -- quantity is a placeholder (README, placeholder quantity defect).
    ids_live_together AS (
        SELECT DISTINCT lot_a.investment_id AS id_a, lot_b.investment_id AS id_b
        FROM {{ positions_ref }} AS lot_a
        JOIN {{ positions_ref }} AS lot_b
            ON  lot_a.snapshot_id   = lot_b.snapshot_id
            AND lot_a.account_id    = lot_b.account_id
            AND lot_a.natural_key   = lot_b.natural_key
            AND lot_a.investment_id < lot_b.investment_id
        WHERE lot_a.admission = 'admit' AND lot_b.admission = 'admit'
          AND lot_a.gross_amount IS DISTINCT FROM lot_b.gross_amount
    ),

    movements AS (
        SELECT mov.*, coalesce(holding_of.natural_key, mov.investment_id) AS holding_key
        FROM {{ transactions_ref }} AS mov
        LEFT JOIN holding_of USING (investment_id)
    ),

    -- everything that identifies "the same event": the holding plus every
    -- business field. Two movements sharing an event_key are either one
    -- event delivered twice or a real repeat.
    keyed AS (
        SELECT *, struct_pack(
            account  := account_id,
            holding  := holding_key,
            happened := {{ date_col }},
            movement := movement_type,
            kind     := transaction_type,
            detail   := transaction_type_additional_info,
            quantity := {{ qty_col }},
            amount   := {{ gross_col }},
            currency := currency
        ) AS event_key
        FROM movements
    ),

    -- one row per distinct event: how many ids delivered it, and which
    -- id's copy survives if it turns out to be a duplicate
    same_event AS (
        SELECT
            event_key,
            count(DISTINCT investment_id) AS n_ids,
            list(DISTINCT investment_id)  AS ids,
            arg_min(investment_id, struct_pack(
                arrived  := ingested_at,
                tiebreak := investment_id
            )) AS keep_id
        FROM keyed
        GROUP BY event_key
    ),

    -- delivered twice = several ids, and no two of them were real lots
    decided AS (
        SELECT
            same_event.*,
            n_ids > 1 AND NOT EXISTS (
                SELECT 1 FROM ids_live_together
                WHERE list_contains(ids, id_a) AND list_contains(ids, id_b)
            ) AS delivered_twice
        FROM same_event
    )

    SELECT
        keyed.* EXCLUDE (event_key),
        decided.delivered_twice AS had_cross_id_twin
    FROM keyed
    JOIN decided ON keyed.event_key IS NOT DISTINCT FROM decided.event_key
    WHERE NOT decided.delivered_twice
       OR keyed.investment_id = decided.keep_id
)
{%- endmacro %}

{# Derives each holding's quantity from its movements.
   Shared by every int_*_holdings model.

   Why not the positions feed: the provider freezes balance quantity at
   the first buy. For 1,578 of 1,611 variable-income lots the balance
   still equals the opening trade (notebook 05). Movements are the
   reliable record.

   Rule:
     - ENTRADA adds, SAIDA subtracts. Movements with no quantity count zero.
     - Runs at holding grain over the deduplicated stream from
       cross_id_movements, so history follows an id replacement and
       re-issued twins count once.
     - Movements whose date the provider lost (staging nulls the
       1970-01-01 placeholder) get the most favorable ordering: lost-date
       buys sort first, lost-date sells last.
     - If the running total still dips below zero, movements are missing.
       The flags macro then marks the holding `movements:incomplete` and
       the derived quantity should not be trusted.

   Emits three CTEs; models join `replay` on (account_id, holding_key).
   Funds pass their own column names. #}
{% macro replay_quantity(movements_rel, qty_col='transaction_quantity', date_col='transaction_date') -%}
day_net AS (
    SELECT
        account_id,
        holding_key,
        CASE
            WHEN {{ date_col }} IS NULL AND movement_type = 'SAIDA'
                THEN DATE '9999-12-31'
            WHEN {{ date_col }} IS NULL
                THEN DATE '1970-01-01'
            ELSE {{ date_col }}
        END AS eff_date,
        sum(CASE
            WHEN {{ qty_col }} IS NULL THEN 0
            WHEN movement_type = 'ENTRADA' THEN {{ qty_col }}
            ELSE -{{ qty_col }}
        END) AS day_net,
        count(*) FILTER ({{ qty_col }} IS NOT NULL) AS n_qty_receipts
    FROM {{ movements_rel }}
    GROUP BY account_id, holding_key, eff_date
),

running AS (
    SELECT
        *,
        sum(day_net) OVER (
            PARTITION BY account_id, holding_key ORDER BY eff_date
        ) AS running_total
    FROM day_net
),

replay AS (
    SELECT
        account_id,
        holding_key,
        sum(day_net)        AS replay_quantity,
        min(running_total)  AS min_running_total,
        sum(n_qty_receipts) AS n_qty_receipts
    FROM running
    GROUP BY account_id, holding_key
)
{%- endmacro %}

{# Joins the replay verdicts onto the lots: rationale in the
   replay_quantity macro header. #}
{% macro holding_replay() -%}
holding AS (
    SELECT
        lots.*,
        replay.replay_quantity AS quantity_derived,
        (replay.min_running_total < -0.001
            OR coalesce(replay.n_qty_receipts, 0) = 0)       AS has_incomplete_replay,
        abs(lots.quantity - replay.replay_quantity) >= 0.001 AS has_stale_lot
    FROM lots
    LEFT JOIN replay USING (account_id, holding_key)
)
{%- endmacro %}

{# --- Holdings cross-sync flags, shared by every int_*_holdings model.

   `holding_timeline()` emits the `timeline` CTE: SELECT * plus lag and
   lead columns over the holding-grain window.

   `holding_data_quality_flags()` emits the final data_quality_flags
   expression. It unions the per-lot flags with the cross-sync signals
   (investment_id:multiple, lot:zero_kept, gross:zero_transient,
   investment_id:replaced) and the replay verdicts
   (movements:incomplete, quantity_reported:stale). A holding that carries
   neither replay verdict has a quantity the movements confirm. It also
   raises the informational holding:matured disclosure. --- #}
{% macro holding_timeline() -%}
timeline AS (
    SELECT
        *,
        lag(gross_amount)   OVER win AS prev_gross,
        lead(gross_amount)  OVER win AS next_gross,
        lag(quantity)       OVER win AS prev_qty,
        lead(quantity)      OVER win AS next_qty,
        lag(investment_ids) OVER win AS prev_ids,
        len(list_filter(investment_ids, id -> NOT list_contains(prev_ids, id))) > 0 AS has_arrived_ids,
        len(list_filter(prev_ids, id -> NOT list_contains(investment_ids, id))) > 0 AS has_departed_ids
    FROM holding
    WINDOW win AS (
        PARTITION BY account_id, holding_key
        ORDER BY snapshot_created_at, snapshot_id
    )
)
{%- endmacro %}

{% macro holding_data_quality_flags() -%}
list_distinct(lot_flags || list_filter([
    CASE WHEN n_investment_ids > 1 THEN 'investment_id:multiple' END,
    CASE WHEN n_investment_ids > 1 AND has_zero_lot THEN 'lot:zero_kept' END,
    CASE WHEN gross_amount = 0 AND prev_gross > 0 AND next_gross > 0
              AND quantity = prev_qty AND quantity = next_qty
         THEN 'gross:zero_transient' END,
    -- The provider reissued investment_ids for the same holding.
    CASE WHEN has_arrived_ids AND has_departed_ids THEN 'investment_id:replaced' END,
    CASE WHEN has_incomplete_replay THEN 'movements:incomplete' END,
    CASE WHEN NOT has_incomplete_replay AND has_stale_lot THEN 'quantity_reported:stale' END,
    CASE WHEN due_date IS NOT NULL AND due_date < reference_date
              AND coalesce(gross_amount, 0) > 0
         THEN 'holding:matured' END
], f -> f IS NOT NULL))
{%- endmacro %}
