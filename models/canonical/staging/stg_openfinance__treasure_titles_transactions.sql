-- 1:1 flatten of raw TREASURE_TITLES transaction payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId}/transactions (and /transactions-current) — treasure-titles v1.1.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/treasure-titles/1.1.0.yml#L191
-- Payload schema #/components/schemas/TreasureTitlesProductTransaction: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/treasure-titles/1.1.0.yml#L476
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
    {{ txn_field('type',                             'VARCHAR', required=true) }}        AS movement_type,
    {{ txn_field('transactionType',                  'VARCHAR', required=true) }}        AS transaction_type,
    {{ txn_field('transactionTypeAdditionalInfo',    'VARCHAR') }}                       AS transaction_type_additional_info,
    {{ txn_field('transactionDate',                  'DATE', required=true) }}           AS transaction_date,
    {{ txn_field('transactionUnitPrice.amount',      'DECIMAL(25,10)', required=true) }} AS transaction_unit_price,
    {{ txn_field('transactionUnitPrice.currency',    'VARCHAR', required=true) }}        AS transaction_unit_price_currency,
    {{ txn_field('transactionQuantity',              'DECIMAL(25,10)', required=true) }} AS transaction_quantity,
    {{ txn_field('transactionGrossValue.amount',     'DECIMAL(25,10)', required=true) }} AS transaction_gross_amount,
    {{ txn_field('transactionGrossValue.currency',   'VARCHAR', required=true) }}        AS transaction_gross_amount_currency,
    {{ txn_field('incomeTax.amount',                 'DECIMAL(25,10)', required=true) }} AS income_tax_amount,
    {{ txn_field('incomeTax.currency',               'VARCHAR', required=true) }}        AS income_tax_amount_currency,
    {{ txn_field('financialTransactionTax.amount',   'DECIMAL(25,10)', required=true) }} AS financial_transaction_tax_amount,
    {{ txn_field('financialTransactionTax.currency', 'VARCHAR', required=true) }}        AS financial_transaction_tax_amount_currency,
    {{ txn_field('transactionNetValue.amount',       'DECIMAL(25,10)', required=true) }} AS transaction_net_amount,
    {{ txn_field('transactionNetValue.currency',     'VARCHAR', required=true) }}        AS transaction_net_amount_currency,
    {{ txn_field('remunerationTransactionRate',      'DECIMAL(12,6)') }}                 AS remuneration_rate,
    {{ txn_field('transactionId',                    'VARCHAR', required=true) }}        AS transaction_id
FROM {{ source('raw_openfinance', 'transactions') }}
WHERE investment_type = 'TREASURE_TITLES'
