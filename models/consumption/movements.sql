-- All families in one uniform schema: one row per transaction, the movements
-- behind the portfolio holdings. gross and net are equal where the spec
-- provides a single transactionValue.
SELECT
    m.account_id,
    m.institution_name,
    'FUNDS' AS investment_type,
    m.investment_id,
    m.transaction_id,
    m.movement_type,
    m.transaction_type,
    m.transaction_conversion_date AS transaction_date,
    m.transaction_quota_quantity  AS quantity,
    m.transaction_quota_price     AS unit_price,
    m.transaction_gross_amount    AS gross_amount,
    m.transaction_net_amount      AS net_amount,
    m.transaction_amount_currency AS currency,
    m.data_quality_flags
FROM {{ ref('int_funds_transactions') }} m

UNION ALL

SELECT
    m.account_id,
    m.institution_name,
    'VARIABLE_INCOMES' AS investment_type,
    m.investment_id,
    m.transaction_id,
    m.movement_type,
    m.transaction_type,
    m.transaction_date,
    m.transaction_quantity        AS quantity,
    m.transaction_unit_price      AS unit_price,
    m.transaction_amount          AS gross_amount,
    m.transaction_amount          AS net_amount,
    m.transaction_amount_currency AS currency,
    m.data_quality_flags
FROM {{ ref('int_variable_incomes_transactions') }} m

UNION ALL

SELECT
    m.account_id,
    m.institution_name,
    'BANK_FIXED_INCOMES' AS investment_type,
    m.investment_id,
    m.transaction_id,
    m.movement_type,
    m.transaction_type,
    m.transaction_date,
    m.transaction_quantity              AS quantity,
    m.transaction_unit_price            AS unit_price,
    m.transaction_gross_amount          AS gross_amount,
    m.transaction_net_amount            AS net_amount,
    m.transaction_gross_amount_currency AS currency,
    m.data_quality_flags
FROM {{ ref('int_bank_fixed_incomes_transactions') }} m

UNION ALL

SELECT
    m.account_id,
    m.institution_name,
    'CREDIT_FIXED_INCOMES' AS investment_type,
    m.investment_id,
    m.transaction_id,
    m.movement_type,
    m.transaction_type,
    m.transaction_date,
    m.transaction_quantity              AS quantity,
    m.transaction_unit_price            AS unit_price,
    m.transaction_gross_amount          AS gross_amount,
    m.transaction_net_amount            AS net_amount,
    m.transaction_gross_amount_currency AS currency,
    m.data_quality_flags
FROM {{ ref('int_credit_fixed_incomes_transactions') }} m

UNION ALL

SELECT
    m.account_id,
    m.institution_name,
    'TREASURE_TITLES' AS investment_type,
    m.investment_id,
    m.transaction_id,
    m.movement_type,
    m.transaction_type,
    m.transaction_date,
    m.transaction_quantity              AS quantity,
    m.transaction_unit_price            AS unit_price,
    m.transaction_gross_amount          AS gross_amount,
    m.transaction_net_amount            AS net_amount,
    m.transaction_gross_amount_currency AS currency,
    m.data_quality_flags
FROM {{ ref('int_treasure_titles_transactions') }} m
