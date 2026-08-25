{{ config(materialized='view') }}
-- 1:1 flatten of raw BANK_FIXED_INCOMES balances payloads into typed columns, in spec order.
SELECT
    snapshot_id,
    investment_id,
    CAST(snapshot_created_at AS TIMESTAMP) AS snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    {{ payload_field('referenceDateTime',              'TIMESTAMP', required=true) }}      AS reference_datetime,
    {{ payload_field('quantity',                       'DECIMAL(25,10)', required=true) }} AS quantity,
    {{ payload_field('updatedUnitPrice.amount',        'DECIMAL(25,10)', required=true) }} AS updated_unit_price,
    {{ payload_field('grossAmount.amount',             'DECIMAL(25,10)', required=true) }} AS gross_amount,
    {{ payload_field('netAmount.amount',               'DECIMAL(25,10)', required=true) }} AS net_amount,
    {{ payload_field('incomeTax.amount',               'DECIMAL(25,10)', required=true) }} AS income_tax,
    {{ payload_field('financialTransactionTax.amount', 'DECIMAL(25,10)', required=true) }} AS transaction_tax,
    {{ payload_field('blockedBalance.amount',          'DECIMAL(25,10)', required=true) }} AS blocked_amount,
    {{ payload_field('purchaseUnitPrice.amount',       'DECIMAL(25,10)', required=true) }} AS purchase_unit_price,
    {{ payload_field('grossAmount.currency',           'VARCHAR') }}                       AS currency
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'BANK_FIXED_INCOMES' AND payload_kind = 'balances'
