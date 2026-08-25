-- Physical holdings: lots regrouped by the natural key.
SELECT
    snapshot_created_at, snapshot_id, account_id, institution_name,
    isin_code, debtor_cnpj, due_date,
    any_value(debtor_name)   AS debtor_name,
    sum(quantity)            AS quantity,
    sum(gross_amount)        AS gross_amount,
    sum(net_amount)          AS net_amount,
    sum(blocked_amount)      AS blocked_amount,
    any_value(currency)      AS currency,
    count(*)                 AS n_lots,
    array_agg(investment_id) AS investment_ids
FROM {{ ref('int_credit_fixed_incomes_positions') }}
GROUP BY ALL
