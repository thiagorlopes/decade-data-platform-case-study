{%- set families = {
    'bank_fixed_incomes': {
        'date':     'transaction_date',
        'gross':    'transaction_gross_amount',
        'net':      'transaction_net_amount',
        'quantity': 'transaction_quantity',
    },
    'credit_fixed_incomes': {
        'date':     'transaction_date',
        'gross':    'transaction_gross_amount',
        'net':      'transaction_net_amount',
        'quantity': 'transaction_quantity',
    },
    'funds': {
        'date':     'transaction_conversion_date',
        'gross':    'transaction_gross_amount',
        'net':      'transaction_net_amount',
        'quantity': 'transaction_quota_quantity',
    },
    'treasure_titles': {
        'date':     'transaction_date',
        'gross':    'transaction_gross_amount',
        'net':      'transaction_net_amount',
        'quantity': 'transaction_quantity',
    },
    'variable_incomes': {
        'date':     'transaction_date',
        'gross':    'transaction_amount',
        'net':      'CAST(NULL AS DECIMAL(38, 10))',
        'quantity': 'transaction_quantity',
    },
} -%}

{% for family, cols in families.items() %}
SELECT
    {{ cols.date }} AS transaction_date,
    ingested_at,
    party_id,
    account_id,
    institution_id,
    institution_name,
    '{{ family }}' AS product_family,
    transaction_id,
    coalesce(k.natural_key, investment_id) AS holding_key,
    investment_id,
    movement_type,
    transaction_type,
    transaction_type_additional_info,
    CAST({{ cols.quantity }} AS DECIMAL(38, 10)) AS quantity,
    CAST({{ cols.gross }} AS DECIMAL(38, 10)) AS gross_amount,
    CAST({{ cols.net }} AS DECIMAL(38, 10)) AS net_amount,
    currency,
    list_filter([
        CASE WHEN {{ cols.date }} IS NULL THEN 'missing:transaction_date' END
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM {{ ref('int_' ~ family ~ '_transactions') }}
LEFT JOIN (
    -- natural_key is a property of the security, so any snapshot resolves it.
    SELECT investment_id, any_value(natural_key) AS natural_key
    FROM {{ ref('int_' ~ family ~ '_positions') }}
    GROUP BY investment_id
) AS k USING (investment_id)
{{ 'UNION ALL' if not loop.last }}
{% endfor %}
