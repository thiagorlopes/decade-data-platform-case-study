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

{# Identity columns (cnpj, isin, ticker, product_name) feed the natural keys
   derived in the intermediate layer. A blank string passes IS NOT NULL and
   would silently fragment those keys, so staging normalizes '' to NULL: the
   warn-severity not_null tests then count blanks as the D1 defects they are. #}
{% macro identity_field(path, required=false) -%}
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

{# --- lot classification (notebook 03), shared by every int_*_positions model.
   Consumes a `keyed` CTE with a `natural_key` column; emits `groups` and
   `classified` CTEs plus the final SELECT that stamps `admission` and
   `dq_flags`. `qty_col` names the quantity for partition detection (funds use
   `quota_quantity`). `extra_flags` is a list of (condition, label) pairs
   appended to dq_flags for family-specific missing-field signals. --- #}
{% macro classify_and_admit(qty_col='quantity', extra_flags=[]) -%}
-- Duplicate groups: two or more investment_ids under one key in one sync.
groups AS (
    SELECT
        snapshot_id,
        account_id,
        natural_key,
        count(DISTINCT {{ qty_col }})            AS n_qty,
        count(DISTINCT gross_amount)             AS n_gross,
        count(*) FILTER (WHERE gross_amount > 0) AS n_live
    FROM keyed
    WHERE natural_key IS NOT NULL
    GROUP BY ALL
    HAVING count(DISTINCT investment_id) > 1
),

-- The notebook 03 §2 ladder: quantities differ = partition (real lots),
-- everything agrees = hard_dup (redundant copies), same quantity but gross
-- disagrees = conflict (one side is usually a frozen-zero fossil).
classified AS (
    SELECT
        keyed.*,
        CASE WHEN groups.n_qty IS NULL   THEN 'sole'
             WHEN groups.n_qty > 1       THEN 'partition'
             WHEN groups.n_gross <= 1    THEN 'hard_dup'
             ELSE 'conflict' END AS dup_class,
        groups.n_live,
        row_number() OVER (
            PARTITION BY keyed.snapshot_id, keyed.account_id, keyed.natural_key
            ORDER BY (keyed.gross_amount IS NULL), keyed.investment_id
        ) AS dedup_rank
    FROM keyed
    LEFT JOIN groups
        ON  keyed.snapshot_id = groups.snapshot_id
        AND keyed.account_id  = groups.account_id
        AND keyed.natural_key = groups.natural_key
)

SELECT
    * EXCLUDE (dup_class, n_live, dedup_rank),
    CASE
        WHEN dup_class = 'hard_dup' AND dedup_rank > 1 THEN 'reject_duplicate'
        WHEN dup_class = 'conflict' AND n_live = 1
             AND coalesce(gross_amount, 0) = 0         THEN 'reject_fossil'
        WHEN dup_class = 'conflict' AND n_live <> 1    THEN 'quarantine'
        ELSE 'admit'
    END AS admission,
    list_filter([
        CASE WHEN natural_key IS NULL THEN 'missing_identity' END,
        CASE WHEN dup_class = 'conflict' AND n_live = 1 AND gross_amount > 0
             THEN 'zero_conflict_resolved' END{% for cond, label in extra_flags %},
        CASE WHEN {{ cond }} THEN '{{ label }}' END{% endfor %}
    ], f -> f IS NOT NULL) AS dq_flags
FROM classified
{%- endmacro %}

{# --- holdings cross-sync flags (shared by every holdings_*_family model).
   `holding_timeline()` emits the `timeline` CTE (SELECT * plus lag/lead
   over the holding-grain window). `holding_dq_flags()` emits the final
   dq_flags expression: prior lot flags unioned with the cross-sync
   signals (merged_lots, zero_gross_lot, zero_flap, id_handoff). --- #}
{% macro holding_timeline() -%}
timeline AS (
    SELECT
        *,
        lag(gross_amount)   OVER win AS prev_gross,
        lead(gross_amount)  OVER win AS next_gross,
        lag(quantity)       OVER win AS prev_qty,
        lead(quantity)      OVER win AS next_qty,
        lag(investment_ids) OVER win AS prev_ids
    FROM holding
    WINDOW win AS (
        PARTITION BY account_id, holding_key
        ORDER BY snapshot_created_at, snapshot_id
    )
)
{%- endmacro %}

{% macro holding_dq_flags() -%}
list_distinct(lot_flags || list_filter([
    CASE WHEN n_lots > 1 THEN 'merged_lots' END,
    CASE WHEN n_lots > 1 AND has_zero_lot THEN 'zero_gross_lot' END,
    CASE WHEN gross_amount = 0 AND prev_gross > 0 AND next_gross > 0
              AND quantity = prev_qty AND quantity = next_qty
         THEN 'zero_flap' END,
    CASE WHEN len(list_filter(investment_ids, id -> NOT list_contains(prev_ids, id))) > 0
          AND len(list_filter(prev_ids, id -> NOT list_contains(investment_ids, id))) > 0
         THEN 'id_handoff' END
], f -> f IS NOT NULL))
{%- endmacro %}
