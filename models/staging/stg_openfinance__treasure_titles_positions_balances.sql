-- 1:1 flatten of raw TREASURE_TITLES balances payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId}/balances (treasure-titles v1.1.0)
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/treasure-titles/1.1.0.yml#L129
-- Payload schema #/components/schemas/TreasureTitlesBalances: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/treasure-titles/1.1.0.yml#L596
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
    {{ payload_field('updatedUnitPrice.amount',          'DECIMAL(25,10)', required=true) }} AS updated_unit_price,
    {{ payload_field('updatedUnitPrice.currency',        'VARCHAR', required=true) }}        AS updated_unit_price_currency,
    {{ payload_field('grossAmount.amount',               'DECIMAL(25,10)', required=true) }} AS gross_amount,
    {{ payload_field('grossAmount.currency',             'VARCHAR', required=true) }}        AS gross_amount_currency,
    {{ payload_field('netAmount.amount',                 'DECIMAL(25,10)', required=true) }} AS net_amount,
    {{ payload_field('netAmount.currency',               'VARCHAR', required=true) }}        AS net_amount_currency,
    {{ payload_field('incomeTax.amount',                 'DECIMAL(25,10)', required=true) }} AS income_tax_amount,
    {{ payload_field('incomeTax.currency',               'VARCHAR', required=true) }}        AS income_tax_amount_currency,
    {{ payload_field('financialTransactionTax.amount',   'DECIMAL(25,10)', required=true) }} AS financial_transaction_tax_amount,
    {{ payload_field('financialTransactionTax.currency', 'VARCHAR', required=true) }}        AS financial_transaction_tax_amount_currency,
    {{ payload_field('blockedBalance.amount',            'DECIMAL(25,10)', required=true) }} AS blocked_amount,
    {{ payload_field('blockedBalance.currency',          'VARCHAR', required=true) }}        AS blocked_amount_currency,
    {{ payload_field('purchaseUnitPrice.amount',         'DECIMAL(25,10)', required=true) }} AS purchase_unit_price,
    {{ payload_field('purchaseUnitPrice.currency',       'VARCHAR', required=true) }}        AS purchase_unit_price_currency,
    {{ payload_field('quantity',                         'DECIMAL(25,10)', required=true) }} AS quantity
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'TREASURE_TITLES' AND payload_kind = 'balances'
