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
    CAST(unit_price AS DECIMAL(38, 10)) AS unit_price,
    CAST(quantity_resolved AS DECIMAL(38, 10)) AS quantity,
    CAST(quantity_resolved::DOUBLE * unit_price::DOUBLE AS DECIMAL(38, 10)) AS gross_amount,
    CAST(quantity_derived AS DECIMAL(38, 10)) AS quantity_derived,
    CAST(quantity AS DECIMAL(38, 10)) AS quantity_reported,
    CAST(gross_amount AS DECIMAL(38, 10)) AS gross_amount_reported,
    CAST(net_amount AS DECIMAL(38, 10)) AS net_amount_reported,
    currency,
    n_investment_ids,
    investment_ids,
    data_quality_flags
FROM (
    -- a plain name is a promise: quantity is resolved once here (the replay
    -- unless it is untrustworthy, then the provider's number), and the plain
    -- columns agree with each other: gross_amount = quantity * unit_price.
    -- The provider's original claims keep the _reported suffix.
    SELECT *, CASE WHEN array_contains(data_quality_flags, 'movements:incomplete')
                   THEN quantity
                   ELSE coalesce(quantity_derived, quantity)
              END AS quantity_resolved
    FROM {{ ref('int_' ~ family ~ '_holdings') }}
)
{{ 'UNION ALL' if not loop.last }}
{% endfor %}
