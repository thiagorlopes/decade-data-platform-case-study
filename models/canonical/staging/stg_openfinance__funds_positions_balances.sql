-- 1:1 flatten of raw FUNDS balances payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId}/balances — funds v1.1.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/funds/1.1.0.yml#L146
-- Payload schema #/components/schemas/ResponseFundsBalanceData: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/funds/1.1.0.yml#L521
SELECT
    snapshot_id,
    investment_id,
    CAST(snapshot_created_at AS TIMESTAMP) AS snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    CAST(ingested_at AS TIMESTAMP) AS ingested_at,
    {{ payload_field('referenceDate',                              'DATE', required=true) }}           AS reference_date,
    {{ payload_field('grossAmount.amount',                         'DECIMAL(25,10)', required=true) }} AS gross_amount,
    {{ payload_field('grossAmount.currency',                       'VARCHAR', required=true) }}        AS gross_amount_currency,
    {{ payload_field('netAmount.amount',                           'DECIMAL(25,10)', required=true) }} AS net_amount,
    {{ payload_field('netAmount.currency',                         'VARCHAR', required=true) }}        AS net_amount_currency,
    {{ payload_field('incomeTaxProvision.amount',                  'DECIMAL(25,10)', required=true) }} AS income_tax_amount,
    {{ payload_field('incomeTaxProvision.currency',                'VARCHAR', required=true) }}        AS income_tax_amount_currency,
    {{ payload_field('financialTransactionTaxProvision.amount',    'DECIMAL(25,10)', required=true) }} AS financial_transaction_tax_amount,
    {{ payload_field('financialTransactionTaxProvision.currency',  'VARCHAR', required=true) }}        AS financial_transaction_tax_amount_currency,
    {{ payload_field('blockedAmount.amount',                       'DECIMAL(25,10)', required=true) }} AS blocked_amount,
    {{ payload_field('blockedAmount.currency',                     'VARCHAR', required=true) }}        AS blocked_amount_currency,
    {{ payload_field('quotaQuantity',                              'DECIMAL(25,10)', required=true) }} AS quota_quantity,
    {{ payload_field('quotaGrossPriceValue.amount',                'DECIMAL(25,10)', required=true) }} AS quota_gross_price,
    {{ payload_field('quotaGrossPriceValue.currency',              'VARCHAR', required=true) }}        AS quota_gross_price_currency
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'FUNDS' AND payload_kind = 'balances'
