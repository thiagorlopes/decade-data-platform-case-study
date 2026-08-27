{%- set families = {
    'bank_fixed_incomes':   'investment_type',
    'credit_fixed_incomes': 'coalesce(debtor_name, investment_type)',
    'funds':                'fund_name',
    'treasure_titles':      'product_name',
    'variable_incomes':     'ticker',
} -%}

{% for family, holding_name in families.items() %}
SELECT
    party_id,
    account_id,
    institution_id,
    institution_name,
    '{{ family }}' AS product_family,
    holding_key,
    {{ holding_name }} AS holding_name,
    isin_code,
    snapshot_id,
    snapshot_created_at,
    reference_date,
    CAST(quantity AS DECIMAL(38, 10)) AS quantity,
    CAST(gross_amount AS DECIMAL(38, 10)) AS gross_amount,
    CAST(net_amount AS DECIMAL(38, 10)) AS net_amount,
    currency,
    n_lots,
    investment_ids,
    data_quality_flags
FROM {{ ref('int_' ~ family ~ '_holdings') }}
{{ 'UNION ALL' if not loop.last }}
{% endfor %}
