-- 1:1 flatten of raw FUNDS transaction payloads into typed columns, in spec order.
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
    {{ txn_field('transactionTypeAdditionalInfo',  'VARCHAR') }}                       AS transaction_type_info,
    {{ txn_field('transactionConversionDate',      'DATE', required=true) }}           AS transaction_conversion_date,
    {{ txn_field('transactionQuotaPrice.amount',   'DECIMAL(25,10)', required=true) }} AS transaction_quota_price,
    {{ txn_field('transactionQuotaQuantity',       'DECIMAL(25,10)', required=true) }} AS transaction_quota_quantity,
    {{ txn_field('transactionValue.amount',        'DECIMAL(25,10)', required=true) }} AS transaction_value,
    {{ txn_field('transactionGrossValue.amount',   'DECIMAL(25,10)', required=true) }} AS transaction_gross_value,
    {{ txn_field('incomeTax.amount',               'DECIMAL(25,10)') }}                AS income_tax,
    {{ txn_field('financialTransactionTax.amount', 'DECIMAL(25,10)') }}                AS transaction_tax,
    {{ txn_field('transactionExitFee.amount',      'DECIMAL(25,10)') }}                AS transaction_exit_fee,
    {{ txn_field('transactionNetValue.amount',     'DECIMAL(25,10)') }}                AS transaction_net_value,
    {{ txn_field('transactionGrossValue.currency', 'VARCHAR') }}                       AS currency
FROM {{ source('raw_openfinance', 'transactions') }}
WHERE investment_type = 'FUNDS'
