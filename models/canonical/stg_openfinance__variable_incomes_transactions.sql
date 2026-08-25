{{ config(materialized='view') }}
-- 1:1 flatten of raw VARIABLE_INCOMES transaction payloads into typed columns, in spec order.
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
    {{ txn_field('transactionId',                 'VARCHAR') }}                       AS transaction_id,
    {{ txn_field('type',                          'VARCHAR') }}                       AS movement_type,
    {{ txn_field('transactionType',               'VARCHAR') }}                       AS transaction_type,
    {{ txn_field('transactionTypeAdditionalInfo', 'VARCHAR') }}                       AS transaction_type_info,
    {{ txn_field('transactionDate',               'DATE', required=true) }}           AS transaction_date,
    {{ txn_field('priceFactor',                   'DECIMAL(25,10)') }}                AS price_factor,
    {{ txn_field('transactionUnitPrice.amount',   'DECIMAL(25,10)') }}                AS transaction_unit_price,
    {{ txn_field('transactionQuantity',           'DECIMAL(25,10)') }}                AS transaction_quantity,
    {{ txn_field('transactionValue.amount',       'DECIMAL(25,10)', required=true) }} AS transaction_value,
    {{ txn_field('brokerNoteId',                  'VARCHAR') }}                       AS broker_note_id,
    {{ txn_field('transactionValue.currency',     'VARCHAR') }}                       AS currency
FROM {{ source('raw_openfinance', 'transactions') }}
WHERE investment_type = 'VARIABLE_INCOMES'
