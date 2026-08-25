-- Physical holdings: lots regrouped by the natural key. Additive fields sum;
-- identity fields are constant within a group (validated in notebook 02).
SELECT
    snapshot_created_at, snapshot_id, account_id, institution_name,
    isin_code, ticker,
    sum(quantity)            AS quantity,
    sum(gross_amount)        AS gross_amount,
    sum(blocked_amount)      AS blocked_amount,
    any_value(currency)      AS currency,
    count(*)                 AS n_lots,
    array_agg(investment_id) AS investment_ids
FROM {{ ref('int_variable_incomes_positions') }}
GROUP BY ALL
