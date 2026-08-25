-- One row per lot (snapshot_id, investment_id): the lot's detail and balances
-- payloads joined and flattened into typed columns.
SELECT
    snapshot_id,
    investment_id,
    TRY_CAST(coalesce(det.snapshot_created_at, bal.snapshot_created_at) AS TIMESTAMP) AS snapshot_created_at,
    coalesce(det.institution_id,   bal.institution_id)   AS institution_id,
    coalesce(det.institution_name, bal.institution_name) AS institution_name,
    coalesce(det.party_id,         bal.party_id)         AS party_id,
    coalesce(det.account_id,       bal.account_id)       AS account_id,
    coalesce(det.connection_id,    bal.connection_id)    AS connection_id,
    {{ payload_field('det', 'issuerInstitutionCnpjNumber', 'VARCHAR') }}       AS issuer_cnpj,
    {{ payload_field('det', 'isinCode',                    'VARCHAR') }}       AS isin_code,
    {{ payload_field('det', 'ticker',                      'VARCHAR') }}       AS ticker,
    {{ payload_field('bal', 'referenceDate',               'DATE') }}          AS reference_date,
    {{ payload_field('bal', 'priceFactor',                 'DECIMAL(12,6)') }} AS price_factor,
    {{ payload_field('bal', 'grossAmount.amount',          'DECIMAL(18,4)') }} AS gross_amount,
    {{ payload_field('bal', 'blockedBalance.amount',       'DECIMAL(18,4)') }} AS blocked_amount,
    {{ payload_field('bal', 'quantity',                    'DECIMAL(24,8)') }} AS quantity,
    {{ payload_field('bal', 'closingPrice.amount',         'DECIMAL(18,4)') }} AS closing_price,
    {{ payload_field('bal', 'grossAmount.currency',        'VARCHAR') }}       AS currency
{{ from_positions('VARIABLE_INCOMES') }}
