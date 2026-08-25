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
    {{ payload_field('det', 'cnpjNumber',                               'VARCHAR') }}       AS cnpj_number,
    {{ payload_field('det', 'name',                                     'VARCHAR') }}       AS fund_name,
    {{ payload_field('det', 'anbimaCategory',                           'VARCHAR') }}       AS anbima_category,
    {{ payload_field('bal', 'quotaQuantity',                            'DECIMAL(24,8)') }} AS quota_quantity,
    {{ payload_field('bal', 'quotaGrossPriceValue.amount',              'DECIMAL(18,4)') }} AS quota_price,
    {{ payload_field('bal', 'grossAmount.amount',                       'DECIMAL(18,4)') }} AS gross_amount,
    {{ payload_field('bal', 'netAmount.amount',                         'DECIMAL(18,4)') }} AS net_amount,
    {{ payload_field('bal', 'blockedAmount.amount',                     'DECIMAL(18,4)') }} AS blocked_amount,
    {{ payload_field('bal', 'incomeTaxProvision.amount',                'DECIMAL(18,4)') }} AS income_tax,
    {{ payload_field('bal', 'financialTransactionTaxProvision.amount',  'DECIMAL(18,4)') }} AS transaction_tax,
    {{ payload_field('bal', 'grossAmount.currency',                     'VARCHAR') }}       AS currency,
    {{ payload_field('bal', 'referenceDate',                            'DATE') }}          AS reference_date
{{ lot_join('FUNDS') }}
