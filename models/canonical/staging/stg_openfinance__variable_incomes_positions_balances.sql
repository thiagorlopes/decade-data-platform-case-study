-- 1:1 flatten of raw VARIABLE_INCOMES balances payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId}/balances — variable-incomes v1.3.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/variable-incomes/1.3.0.yml#L170
-- Payload schema #/components/schemas/ResponseVariableIncomesBalanceData: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/variable-incomes/1.3.0.yml#L530
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
    {{ payload_field('referenceDate',            'DATE', required=true) }}           AS reference_date,
    {{ payload_field('priceFactor',              'DECIMAL(25,10)', required=true) }} AS price_factor,
    {{ payload_field('grossAmount.amount',       'DECIMAL(25,10)', required=true) }} AS gross_amount,
    {{ payload_field('grossAmount.currency',     'VARCHAR', required=true) }}        AS gross_amount_currency,
    {{ payload_field('blockedBalance.amount',    'DECIMAL(25,10)', required=true) }} AS blocked_amount,
    {{ payload_field('blockedBalance.currency',  'VARCHAR', required=true) }}        AS blocked_amount_currency,
    {{ payload_field('quantity',                 'DECIMAL(25,10)', required=true) }} AS quantity,
    {{ payload_field('closingPrice.amount',      'DECIMAL(25,10)', required=true) }} AS closing_price,
    {{ payload_field('closingPrice.currency',    'VARCHAR', required=true) }}        AS closing_price_currency
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'VARIABLE_INCOMES' AND payload_kind = 'balances'
