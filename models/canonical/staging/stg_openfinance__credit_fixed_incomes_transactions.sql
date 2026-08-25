-- 1:1 flatten of raw CREDIT_FIXED_INCOMES transaction payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId}/transactions (and /transactions-current) — credit-fixed-incomes v1.1.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/credit-fixed-incomes/1.1.0.yml#L185
-- Payload schema #/components/schemas/CreditFixedIncomesTransactions: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/credit-fixed-incomes/1.1.0.yml#L1120
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
    {{ txn_field('transactionDate',                'DATE', required=true) }}           AS transaction_date,
    {{ txn_field('transactionUnitPrice.amount',    'DECIMAL(25,10)') }}                AS transaction_unit_price,
    {{ txn_field('transactionQuantity',            'DECIMAL(25,10)') }}                AS transaction_quantity,
    {{ txn_field('transactionGrossValue.amount',   'DECIMAL(25,10)', required=true) }} AS transaction_gross_amount,
    {{ txn_field('incomeTax.amount',               'DECIMAL(25,10)') }}                AS income_tax_amount,
    {{ txn_field('financialTransactionTax.amount', 'DECIMAL(25,10)') }}                AS financial_transaction_tax_amount,
    {{ txn_field('transactionNetValue.amount',     'DECIMAL(25,10)', required=true) }} AS transaction_net_amount,
    {{ txn_field('remunerationTransactionRate',    'DECIMAL(12,6)') }}                 AS remuneration_rate,
    {{ txn_field('indexerPercentage',              'DECIMAL(12,6)') }}                 AS indexer_percentage,
    {{ txn_field('transactionGrossValue.currency', 'VARCHAR') }}                       AS currency
FROM {{ source('raw_openfinance', 'transactions') }}
WHERE investment_type = 'CREDIT_FIXED_INCOMES'
