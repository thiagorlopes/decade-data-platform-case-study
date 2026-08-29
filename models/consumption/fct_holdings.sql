{%- set families = [
    'bank_fixed_incomes',
    'credit_fixed_incomes',
    'funds',
    'treasure_titles',
    'variable_incomes',
] -%}

{% for family in families %}
SELECT
    reference_date,
    snapshot_created_at,
    snapshot_id,
    party_id,
    account_id,
    institution_id,
    institution_name,
    '{{ family }}' AS product_family,
    holding_key,
    CAST(quantity AS DECIMAL(38, 10)) AS quantity,
    CAST(quantity_derived AS DECIMAL(38, 10)) AS quantity_derived,
    -- the stale-quantity defect resolved once, for every consumer:
    -- the replay unless it is untrustworthy, then the provider's number
    CAST(CASE WHEN list_contains(data_quality_flags, 'movements:incomplete')
              THEN quantity
              ELSE coalesce(quantity_derived, quantity)
         END AS DECIMAL(38, 10)) AS quantity_best,
    CAST(gross_amount AS DECIMAL(38, 10)) AS gross_amount,
    CAST(net_amount AS DECIMAL(38, 10)) AS net_amount,
    CAST(unit_price AS DECIMAL(38, 10)) AS unit_price,
    currency,
    n_investment_ids,
    investment_ids,
    data_quality_flags
FROM {{ ref('int_' ~ family ~ '_holdings') }}
{{ 'UNION ALL' if not loop.last }}
{% endfor %}
