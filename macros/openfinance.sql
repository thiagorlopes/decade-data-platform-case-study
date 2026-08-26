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

{# Used on the columns that feed natural keys (cnpj, isin, ticker,
   product_name): a blank string passes IS NOT NULL and would silently
   fragment those keys. #}
{% macro blank_to_null_field(path, required=false) -%}
    nullif(trim({{ payload_field(path, 'VARCHAR', required) }}), '')
{%- endmacro %}

{# --- within-record repairs (notebook 02), applied in the intermediate layer
   so the staging warn tests keep counting the raw defects. --- #}

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

{# 0001-01-01 is .NET DateTime.MinValue: a missing date in a date costume. #}
{% macro clean_missing_date(column) -%}
    nullif({{ column }}, DATE '0001-01-01')
{%- endmacro %}

{# --- Classify duplicate investment_ids per natural key and stamp each row
   with an admission verdict (notebook 03). Shared by every int_*_positions
   model so the five families agree on what counts as a duplicate and how
   to resolve one.

   Caller contract:
     - Provides a CTE named `keyed` with columns `snapshot_id`, `account_id`,
       `natural_key`, `investment_id`, `gross_amount`, and the quantity column
       named by `qty_col` (default `quantity`; funds pass `quota_quantity`).
     - Gets back the final SELECT of the model, with every input column plus
       `admission` (admit / reject_duplicate / reject_fossil / quarantine) and
       `data_quality_flags` (array of defect labels).

   `extra_flags` lets a family append its own (condition, label) pairs to
   data_quality_flags — used for missing-field signals like ('indexer IS NULL',
   'missing:indexer'). --- #}
{% macro resolve_duplicate_investments(qty_col='quantity', extra_flags=[]) -%}
-- A duplicate group is two or more investment_ids under one natural key in
-- one sync. Rows with a NULL natural_key are excluded here (can't be grouped
-- by an identifier that isn't there) and are handled by the classifier below.
duplicate_groups AS (
    SELECT
        snapshot_id,
        account_id,
        natural_key,
        count(DISTINCT {{ qty_col }})            AS n_distinct_quantities,
        count(DISTINCT gross_amount)             AS n_distinct_gross_amounts,
        count(*) FILTER (WHERE gross_amount > 0) AS n_positive_gross_amounts
    FROM keyed
    WHERE natural_key IS NOT NULL
    GROUP BY ALL
    HAVING count(DISTINCT investment_id) > 1
),

-- Notebook 03 §2 ladder, read top to bottom:
--   no natural key           -> we cannot check for duplicates ('missing_identity')
--   key not in a group       -> unique in the sync             ('no_duplicate')
--   quantities differ        -> genuinely separate investments ('partition')
--   quantities agree + gross agrees -> redundant copies        ('hard_dup')
--   quantities agree + gross differs -> same position, two valuations ('conflict')
classified AS (
    SELECT
        keyed.*,
        CASE WHEN keyed.natural_key IS NULL          THEN 'missing_identity'
             WHEN dup.natural_key IS NULL            THEN 'no_duplicate'
             WHEN dup.n_distinct_quantities > 1      THEN 'partition'
             WHEN dup.n_distinct_gross_amounts <= 1  THEN 'hard_dup'
             ELSE 'conflict' END AS dup_class,
        dup_class = 'conflict' AND dup.n_positive_gross_amounts = 1 AS is_resolvable_conflict,
        -- Rank 1 is the copy a hard_dup keeps: prefer a priced one, then
        -- lowest investment_id for determinism.
        row_number() OVER (
            PARTITION BY keyed.snapshot_id, keyed.account_id, keyed.natural_key
            ORDER BY (keyed.gross_amount IS NULL), keyed.investment_id
        ) AS dedup_rank
    FROM keyed
    LEFT JOIN duplicate_groups AS dup
        ON  keyed.snapshot_id = dup.snapshot_id
        AND keyed.account_id  = dup.account_id
        AND keyed.natural_key = dup.natural_key
)

SELECT
    * EXCLUDE (dup_class, is_resolvable_conflict, dedup_rank),
    CASE
        WHEN dup_class = 'hard_dup' AND dedup_rank > 1 THEN 'reject_duplicate'
        WHEN is_resolvable_conflict
             AND coalesce(gross_amount, 0) = 0         THEN 'reject_fossil'
        WHEN dup_class = 'conflict'
             AND NOT is_resolvable_conflict            THEN 'quarantine'
        ELSE 'admit'
    END AS admission,
    list_filter([
        CASE WHEN natural_key IS NULL THEN 'missing_identity' END,
        CASE WHEN is_resolvable_conflict AND gross_amount > 0
             THEN 'zero_conflict_resolved' END{% for cond, label in extra_flags %},
        CASE WHEN {{ cond }} THEN '{{ label }}' END{% endfor %}
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM classified
{%- endmacro %}

{# --- holdings cross-sync flags (shared by every holdings_*_family model).
   `holding_timeline()` emits the `timeline` CTE (SELECT * plus lag/lead
   over the holding-grain window). `holding_data_quality_flags()` emits the final
   data_quality_flags expression: per-investment flags unioned with the cross-sync
   signals (merged_lots, zero_gross_lot, zero_flap, id_handoff). --- #}
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
    CASE WHEN n_lots > 1 THEN 'merged_lots' END,
    CASE WHEN n_lots > 1 AND has_zero_lot THEN 'zero_gross_lot' END,
    CASE WHEN gross_amount = 0 AND prev_gross > 0 AND next_gross > 0
              AND quantity = prev_qty AND quantity = next_qty
         THEN 'zero_flap' END,
    -- The provider reissued investment_ids for the same holding.
    CASE WHEN has_arrived_ids AND has_departed_ids THEN 'id_handoff' END
], f -> f IS NOT NULL))
{%- endmacro %}
