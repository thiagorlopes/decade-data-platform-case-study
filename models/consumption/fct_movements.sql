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
    holding_key,
    investment_id,
    movement_type,
    transaction_type,
    transaction_type_additional_info,
    CAST({{ cols.quantity }} AS DECIMAL(38, 10)) AS quantity,
    CAST({{ cols.gross }} AS DECIMAL(38, 10)) AS gross_amount,
    CAST({{ cols.net }} AS DECIMAL(38, 10)) AS net_amount,
    currency,
    list_filter([
        CASE WHEN {{ cols.date }} IS NULL THEN 'missing:transaction_date' END,
        CASE WHEN had_cross_id_twin THEN 'duplicate:cross_id' END
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM {{ cross_id_movements(ref('int_' ~ family ~ '_transactions'),
                           ref('int_' ~ family ~ '_positions'),
                           date_col=cols.date,
                           qty_col=cols.quantity,
                           gross_col=cols.gross) }} AS mov
{{ 'UNION ALL' if not loop.last }}
{% endfor %}
