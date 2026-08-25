-- One row per lot (snapshot_id, investment_id): the lot's detail and balances
-- staging rows joined into a single record.
-- FULL JOIN because some lots arrive with balances only (no detail payload);
-- has_detail / has_balances mark which payloads actually arrived.
SELECT
    snapshot_id,
    investment_id,
    det.snapshot_id IS NOT NULL AS has_detail,
    bal.snapshot_id IS NOT NULL AS has_balances,
    coalesce(det.snapshot_created_at, bal.snapshot_created_at) AS snapshot_created_at,
    coalesce(det.institution_id,   bal.institution_id)   AS institution_id,
    coalesce(det.institution_name, bal.institution_name) AS institution_name,
    coalesce(det.party_id,         bal.party_id)         AS party_id,
    coalesce(det.account_id,       bal.account_id)       AS account_id,
    coalesce(det.connection_id,    bal.connection_id)    AS connection_id,
    det.issuer_cnpj,
    det.isin_code,
    det.ticker,
    bal.reference_date,
    bal.price_factor,
    bal.gross_amount,
    bal.blocked_amount,
    bal.quantity,
    bal.closing_price,
    bal.currency
FROM {{ ref('stg_openfinance__variable_incomes_positions_detail') }} AS det
FULL JOIN {{ ref('stg_openfinance__variable_incomes_positions_balances') }} AS bal
    USING (snapshot_id, investment_id)
