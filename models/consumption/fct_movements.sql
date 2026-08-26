{%- set families = {
    'bank_fixed_incomes': {
        'date':  'transaction_date',
        'gross': 'transaction_gross_amount',
        'net':   'transaction_net_amount',
    },
    'credit_fixed_incomes': {
        'date':  'transaction_date',
        'gross': 'transaction_gross_amount',
        'net':   'transaction_net_amount',
    },
    'funds': {
        'date':  'transaction_conversion_date',
        'gross': 'transaction_gross_amount',
        'net':   'transaction_net_amount',
    },
    'treasure_titles': {
        'date':  'transaction_date',
        'gross': 'transaction_gross_amount',
        'net':   'transaction_net_amount',
    },
    'variable_incomes': {
        'date':  'transaction_date',
        'gross': 'transaction_amount',
        'net':   'CAST(NULL AS DECIMAL(25, 10))',
    },
} -%}

{% for family, cols in families.items() %}
SELECT
    party_id,
    account_id,
    institution_name,
    '{{ family }}' AS product_family,
    transaction_id,
    investment_id,
    {{ cols.date }} AS transaction_date,
    movement_type,
    transaction_type,
    transaction_type_additional_info,
    {{ cols.gross }} AS gross_amount,
    {{ cols.net }} AS net_amount,
    currency,
    ingested_at,
    list_filter([
        CASE WHEN {{ cols.date }} IS NULL THEN 'missing:transaction_date' END
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM {{ ref('int_' ~ family ~ '_transactions') }}
{{ 'UNION ALL' if not loop.last }}
{% endfor %}
