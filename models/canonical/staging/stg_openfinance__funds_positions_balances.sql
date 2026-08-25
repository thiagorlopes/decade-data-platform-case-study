-- 1:1 flatten of raw FUNDS balances payloads into typed columns, in spec order.
SELECT
    snapshot_id,
    investment_id,
    CAST(snapshot_created_at AS TIMESTAMP) AS snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    {{ payload_field('referenceDate',                           'DATE', required=true) }}           AS reference_date,
    {{ payload_field('grossAmount.amount',                      'DECIMAL(25,10)', required=true) }} AS gross_amount,
    {{ payload_field('netAmount.amount',                        'DECIMAL(25,10)', required=true) }} AS net_amount,
    {{ payload_field('incomeTaxProvision.amount',               'DECIMAL(25,10)', required=true) }} AS income_tax,
    {{ payload_field('financialTransactionTaxProvision.amount', 'DECIMAL(25,10)', required=true) }} AS transaction_tax,
    {{ payload_field('blockedAmount.amount',                    'DECIMAL(25,10)', required=true) }} AS blocked_amount,
    {{ payload_field('quotaQuantity',                           'DECIMAL(25,10)', required=true) }} AS quota_quantity,
    {{ payload_field('quotaGrossPriceValue.amount',             'DECIMAL(25,10)', required=true) }} AS quota_price,
    {{ payload_field('grossAmount.currency',                    'VARCHAR') }}                       AS currency
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'FUNDS' AND payload_kind = 'balances'
