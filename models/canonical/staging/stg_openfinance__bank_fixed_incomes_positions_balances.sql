-- 1:1 flatten of raw BANK_FIXED_INCOMES balances payloads into typed columns.
-- API: GET /investments/{investmentId}/balances — bank-fixed-incomes v1.1.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/bank-fixed-incomes/1.1.0.yml#L129
-- Payload schema #/components/schemas/ResponseBankFixedIncomesBalances.data: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/bank-fixed-incomes/1.1.0.yml#L406
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
    {{ payload_field('referenceDateTime',                'TIMESTAMP', required=true) }}      AS reference_datetime,
    {{ payload_field('quantity',                         'DECIMAL(25,10)', required=true) }} AS quantity,
    {{ payload_field('preFixedRate',                     'DECIMAL(12,6)') }}                 AS pre_fixed_rate,
    {{ payload_field('postFixedIndexerPercentage',       'DECIMAL(12,6)') }}                 AS post_fixed_indexer_percentage,
    {{ payload_field('updatedUnitPrice.amount',          'DECIMAL(25,10)', required=true) }} AS updated_unit_price,
    {{ payload_field('updatedUnitPrice.currency',        'VARCHAR') }}                       AS updated_unit_price_currency,
    {{ payload_field('grossAmount.amount',               'DECIMAL(25,10)', required=true) }} AS gross_amount,
    {{ payload_field('grossAmount.currency',             'VARCHAR') }}                       AS gross_amount_currency,
    {{ payload_field('netAmount.amount',                 'DECIMAL(25,10)', required=true) }} AS net_amount,
    {{ payload_field('netAmount.currency',               'VARCHAR') }}                       AS net_amount_currency,
    {{ payload_field('incomeTax.amount',                 'DECIMAL(25,10)', required=true) }} AS income_tax_amount,
    {{ payload_field('incomeTax.currency',               'VARCHAR') }}                       AS income_tax_amount_currency,
    {{ payload_field('financialTransactionTax.amount',   'DECIMAL(25,10)', required=true) }} AS financial_transaction_tax_amount,
    {{ payload_field('financialTransactionTax.currency', 'VARCHAR') }}                       AS financial_transaction_tax_amount_currency,
    {{ payload_field('blockedBalance.amount',            'DECIMAL(25,10)', required=true) }} AS blocked_amount,
    {{ payload_field('blockedBalance.currency',          'VARCHAR') }}                       AS blocked_amount_currency,
    {{ payload_field('purchaseUnitPrice.amount',         'DECIMAL(25,10)', required=true) }} AS purchase_unit_price,
    {{ payload_field('purchaseUnitPrice.currency',       'VARCHAR') }}                       AS purchase_unit_price_currency
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'BANK_FIXED_INCOMES' AND payload_kind = 'balances'
