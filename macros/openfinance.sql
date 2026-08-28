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

{# A provider may re-deliver the same (snapshot_id, investment_id) with a
   changed value. The latest arrival wins. Superseded copies stay visible
   in staging and in the lot_redelivery warn ledger. Ties cannot happen
   here: the staging grain test errors on
   (snapshot_id, investment_id, ingested_at), so the sort always has one
   winner. #}
{% macro latest_delivery(staging_ref) -%}
(
    SELECT * FROM {{ staging_ref }}
    QUALIFY row_number() OVER (
        PARTITION BY snapshot_id, investment_id
        ORDER BY ingested_at DESC
    ) = 1
)
{%- endmacro %}

{# --- Classify duplicate investment_ids per natural key and stamp each row
   with an admission verdict (notebook 03). Shared by every int_*_positions
   model so the five families agree on what counts as a duplicate and how
   to resolve one.

   Caller contract:
     - Provides a CTE named `with_natural_key` with columns `snapshot_id`, `account_id`,
       `natural_key`, `investment_id`, `gross_amount`, and the quantity column
       named by `qty_col` (default `quantity`; funds pass `quota_quantity`).
     - Gets back the final SELECT of the model, with every input column plus
       `admission` (admit / reject_duplicate / reject_zero_duplicate / quarantine) and
       `data_quality_flags` (array of defect labels).

   `extra_flags` lets a family append its own (condition, label) pairs to
   data_quality_flags — used for missing-field signals like ('indexer IS NULL',
   'missing:indexer'). --- #}
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
        CASE WHEN natural_key IS NULL           THEN 'missing:natural_key'  -- no key, cannot check for duplicates
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
        CASE WHEN natural_key IS NULL THEN 'missing:natural_key' END,
        CASE WHEN is_resolvable_conflict AND gross_amount > 0
             THEN 'zero:duplicate_dropped' END{% for cond, label in extra_flags %},
        CASE WHEN {{ cond }} THEN '{{ label }}' END{% endfor %}
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM classified
{%- endmacro %}

{# --- receipts replay (shared by every int_*_holdings model).
   Derives each lot's quantity from transaction movements: ENTRADA adds,
   SAIDA subtracts, receipts with no quantity count zero. The positions
   feed cannot be trusted for this: it freezes quantity at the first buy,
   so for 1,578 of 1,611 variable-income lots the balance equals the first
   trade, not the latest state (evidence in notebook 05).
   Receipts whose date the provider lost (staging nulls the 1970-01-01
   placeholder) get the most favorable ordering: lost-date buys sort first,
   lost-date sells last. If the running total still drops below zero,
   receipts are missing and the flags macro below marks the lot
   `movements:incomplete`.
   Emits three CTEs; models join on `replay`. Funds pass their own
   column names. --- #}
{% macro replay_quantity(transactions_ref, qty_col='transaction_quantity', date_col='transaction_date') -%}
day_net AS (
    SELECT
        investment_id,
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
    FROM {{ transactions_ref }}
    GROUP BY investment_id, eff_date
),

running AS (
    SELECT
        *,
        sum(day_net) OVER (
            PARTITION BY investment_id ORDER BY eff_date
        ) AS running_total
    FROM day_net
),

replay AS (
    SELECT
        investment_id,
        sum(day_net)        AS replay_quantity,
        min(running_total)  AS min_running_total,
        sum(n_qty_receipts) AS n_qty_receipts
    FROM running
    GROUP BY investment_id
)
{%- endmacro %}

{# --- holdings cross-sync flags (shared by every int_*_holdings model).
   `holding_timeline()` emits the `timeline` CTE (SELECT * plus lag/lead
   over the holding-grain window). `holding_data_quality_flags()` emits the final
   data_quality_flags expression: per-lot flags unioned with the cross-sync
   signals (investment_id:multiple, zero:lot_kept, zero:transient, investment_id:replaced) and the
   replay verdicts (movements:incomplete, stale:quantity); a holding with
   neither replay flag has a quantity the movements confirm. --- #}
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
    CASE WHEN n_investment_ids > 1 AND has_zero_lot THEN 'zero:lot_kept' END,
    CASE WHEN gross_amount = 0 AND prev_gross > 0 AND next_gross > 0
              AND quantity = prev_qty AND quantity = next_qty
         THEN 'zero:transient' END,
    -- The provider reissued investment_ids for the same holding.
    CASE WHEN has_arrived_ids AND has_departed_ids THEN 'investment_id:replaced' END,
    CASE WHEN has_incomplete_replay THEN 'movements:incomplete' END,
    CASE WHEN NOT has_incomplete_replay AND has_stale_lot THEN 'stale:quantity' END
], f -> f IS NOT NULL))
{%- endmacro %}
