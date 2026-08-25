-- 1:1 flatten of raw FUNDS transaction payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId}/transactions (and /transactions-current) — funds v1.1.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/funds/1.1.0.yml#L201
-- Payload schema #/components/schemas/ResponseFundsTransactionsData: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/funds/1.1.0.yml#L560
SELECT
    snapshot_id,
    payload_source,
    CAST(snapshot_created_at AS TIMESTAMP) AS snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    investment_id,
    {{ txn_field('transactionId',                  'VARCHAR') }}                       AS transaction_id,
    {{ txn_field('type',                           'VARCHAR') }}                       AS movement_type,
    {{ txn_field('transactionType',                'VARCHAR') }}                       AS transaction_type,
    {{ txn_field('transactionTypeAdditionalInfo',  'VARCHAR') }}                       AS transaction_type_additional_info,
    {{ txn_field('transactionConversionDate',      'DATE', required=true) }}           AS transaction_conversion_date,
    {{ txn_field('transactionQuotaPrice.amount',   'DECIMAL(25,10)', required=true) }} AS transaction_quota_price,
    {{ txn_field('transactionQuotaQuantity',       'DECIMAL(25,10)', required=true) }} AS transaction_quota_quantity,
    {{ txn_field('transactionValue.amount',        'DECIMAL(25,10)', required=true) }} AS transaction_amount,
    {{ txn_field('transactionGrossValue.amount',   'DECIMAL(25,10)', required=true) }} AS transaction_gross_amount,
    {{ txn_field('incomeTax.amount',               'DECIMAL(25,10)') }}                AS income_tax_amount,
    {{ txn_field('financialTransactionTax.amount', 'DECIMAL(25,10)') }}                AS financial_transaction_tax_amount,
    {{ txn_field('transactionExitFee.amount',      'DECIMAL(25,10)') }}                AS transaction_exit_fee,
    {{ txn_field('transactionNetValue.amount',     'DECIMAL(25,10)') }}                AS transaction_net_amount,
    {{ txn_field('transactionGrossValue.currency', 'VARCHAR') }}                       AS currency
FROM {{ source('raw_openfinance', 'transactions') }}
WHERE investment_type = 'FUNDS'
