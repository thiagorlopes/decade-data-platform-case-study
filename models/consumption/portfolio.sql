-- All families in one uniform schema: one row per holding per sync.
-- Tables are aliased and columns qualified because DuckDB lateral alias
-- binding would otherwise resolve source columns to same-named SELECT aliases.
SELECT
    h.snapshot_created_at,
    h.snapshot_id,
    h.account_id,
    h.institution_name,
    'VARIABLE_INCOMES' AS investment_type,
    h.ticker           AS instrument,
    h.holding_key,
    h.quantity,
    h.gross_amount,
    h.currency,
    h.n_lots,
    h.dq_flags
FROM {{ ref('holdings_variable_incomes') }} h

UNION ALL

SELECT
    h.snapshot_created_at,
    h.snapshot_id,
    h.account_id,
    h.institution_name,
    'FUNDS'     AS investment_type,
    h.fund_name AS instrument,
    h.holding_key,
    h.quantity,
    h.gross_amount,
    h.currency,
    h.n_lots,
    h.dq_flags
FROM {{ ref('holdings_funds') }} h

UNION ALL

SELECT
    h.snapshot_created_at,
    h.snapshot_id,
    h.account_id,
    h.institution_name,
    'BANK_FIXED_INCOMES' AS investment_type,
    coalesce(h.isin_code, h.investment_type) AS instrument,
    h.holding_key,
    h.quantity,
    h.gross_amount,
    h.currency,
    h.n_lots,
    h.dq_flags
FROM {{ ref('holdings_bank_fixed_incomes') }} h

UNION ALL

SELECT
    h.snapshot_created_at,
    h.snapshot_id,
    h.account_id,
    h.institution_name,
    'CREDIT_FIXED_INCOMES' AS investment_type,
    coalesce(h.isin_code, h.investment_type) AS instrument,
    h.holding_key,
    h.quantity,
    h.gross_amount,
    h.currency,
    h.n_lots,
    h.dq_flags
FROM {{ ref('holdings_credit_fixed_incomes') }} h

UNION ALL

SELECT
    h.snapshot_created_at,
    h.snapshot_id,
    h.account_id,
    h.institution_name,
    'TREASURE_TITLES' AS investment_type,
    h.product_name    AS instrument,
    h.holding_key,
    h.quantity,
    h.gross_amount,
    h.currency,
    h.n_lots,
    h.dq_flags
FROM {{ ref('holdings_treasure_titles') }} h
