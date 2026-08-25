-- Rows the classifier could not safely resolve (conflict groups without exactly
-- one live row). Expected empty; the yml monitor warns if it ever grows.
{% set families = [
    ('int_variable_incomes_positions', 'VARIABLE_INCOMES', 'quantity'),
    ('int_funds_positions', 'FUNDS', 'quota_quantity'),
    ('int_bank_fixed_incomes_positions', 'BANK_FIXED_INCOMES', 'quantity'),
    ('int_credit_fixed_incomes_positions', 'CREDIT_FIXED_INCOMES', 'quantity'),
    ('int_treasure_titles_positions', 'TREASURE_TITLES', 'quantity'),
] %}

{% for model, family, qty_col in families %}
SELECT
    '{{ family }}' AS investment_type,
    snapshot_created_at,
    snapshot_id,
    account_id,
    institution_name,
    natural_key,
    investment_id,
    {{ qty_col }} AS quantity,
    gross_amount,
    gross_amount_currency AS currency
FROM {{ ref(model) }}
WHERE admission = 'quarantine'
{% if not loop.last %}
UNION ALL
{% endif %}
{% endfor %}
