-- Conservation invariant of the cross-id dedup: a movement may be missing
-- from fct_movements only when an identical copy survives there, under
-- another investment_id of the same holding, flagged duplicate:cross_id,
-- agreeing on every business field including net_amount, and delivered no
-- later than the dropped copy (first-delivered wins). Any row returned
-- here is a movement the dedup deleted without holding its twin.
{% set families = {
    'bank_fixed_incomes':   {'date': 'transaction_date',            'qty': 'transaction_quantity',       'gross': 'transaction_gross_amount', 'net': 'dropped.transaction_net_amount'},
    'credit_fixed_incomes': {'date': 'transaction_date',            'qty': 'transaction_quantity',       'gross': 'transaction_gross_amount', 'net': 'dropped.transaction_net_amount'},
    'funds':                {'date': 'transaction_conversion_date', 'qty': 'transaction_quota_quantity', 'gross': 'transaction_gross_amount', 'net': 'dropped.transaction_net_amount'},
    'treasure_titles':      {'date': 'transaction_date',            'qty': 'transaction_quantity',       'gross': 'transaction_gross_amount', 'net': 'dropped.transaction_net_amount'},
    'variable_incomes':     {'date': 'transaction_date',            'qty': 'transaction_quantity',       'gross': 'transaction_amount',       'net': 'CAST(NULL AS DECIMAL(38, 10))'},
} %}
{% for family, cols in families.items() %}
SELECT
    '{{ family }}' AS product_family,
    dropped.transaction_id,
    dropped.investment_id
FROM {{ ref('int_' ~ family ~ '_transactions') }} AS dropped
LEFT JOIN (
    SELECT investment_id, max(natural_key) AS natural_key
    FROM {{ ref('int_' ~ family ~ '_positions') }}
    GROUP BY investment_id
) AS holding_of USING (investment_id)
WHERE NOT EXISTS (
    SELECT 1 FROM {{ ref('fct_movements') }} AS fct
    WHERE fct.transaction_id = dropped.transaction_id
)
AND NOT EXISTS (
    SELECT 1 FROM {{ ref('fct_movements') }} AS kept
    WHERE kept.product_family = '{{ family }}'
      AND kept.account_id = dropped.account_id
      AND kept.holding_key = coalesce(holding_of.natural_key, dropped.investment_id)
      AND kept.investment_id <> dropped.investment_id
      AND list_contains(kept.data_quality_flags, 'duplicate:cross_id')
      AND kept.transaction_date IS NOT DISTINCT FROM dropped.{{ cols.date }}
      AND kept.movement_type IS NOT DISTINCT FROM dropped.movement_type
      AND kept.transaction_type IS NOT DISTINCT FROM dropped.transaction_type
      AND kept.transaction_type_additional_info IS NOT DISTINCT FROM dropped.transaction_type_additional_info
      AND kept.quantity IS NOT DISTINCT FROM CAST(dropped.{{ cols.qty }} AS DECIMAL(38, 10))
      AND kept.gross_amount IS NOT DISTINCT FROM CAST(dropped.{{ cols.gross }} AS DECIMAL(38, 10))
      AND kept.net_amount IS NOT DISTINCT FROM CAST({{ cols.net }} AS DECIMAL(38, 10))
      AND kept.currency IS NOT DISTINCT FROM dropped.currency
      AND (kept.ingested_at < dropped.ingested_at
           OR (kept.ingested_at = dropped.ingested_at AND kept.investment_id < dropped.investment_id))
)
{{ 'UNION ALL' if not loop.last }}
{% endfor %}
