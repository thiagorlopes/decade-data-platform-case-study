-- One schema over the five families for cross-family questions.
SELECT snapshot_created_at, snapshot_id, account_id, institution_name,
       'VARIABLE_INCOMES' AS investment_type, ticker AS instrument,
       quantity, gross_amount, currency, n_lots
FROM {{ ref('holdings_variable_incomes') }}
UNION ALL
SELECT snapshot_created_at, snapshot_id, account_id, institution_name,
       'FUNDS', fund_name, quota_quantity, gross_amount, currency, n_lots
FROM {{ ref('holdings_funds') }}
UNION ALL
SELECT snapshot_created_at, snapshot_id, account_id, institution_name,
       'BANK_FIXED_INCOMES', isin_code, quantity, gross_amount, currency, n_lots
FROM {{ ref('holdings_bank_fixed_incomes') }}
UNION ALL
SELECT snapshot_created_at, snapshot_id, account_id, institution_name,
       'CREDIT_FIXED_INCOMES', isin_code, quantity, gross_amount, currency, n_lots
FROM {{ ref('holdings_credit_fixed_incomes') }}
UNION ALL
SELECT snapshot_created_at, snapshot_id, account_id, institution_name,
       'TREASURE_TITLES', product_name, quantity, gross_amount, currency, n_lots
FROM {{ ref('holdings_treasure_titles') }}
