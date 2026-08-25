-- 1:1 flatten of raw BANK_FIXED_INCOMES detail payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId} — bank-fixed-incomes v1.1.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/bank-fixed-incomes/1.1.0.yml#L81
-- Payload schema #/components/schemas/IdentifyProduct: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/bank-fixed-incomes/1.1.0.yml#L581
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
    {{ payload_field('issuerInstitutionCnpjNumber',             'VARCHAR', required=true) }}        AS issuer_cnpj,
    {{ payload_field('isinCode',                                'VARCHAR') }}                       AS isin_code,
    {{ payload_field('investmentType',                          'VARCHAR', required=true) }}        AS product_type,
    {{ payload_field('remuneration.preFixedRate',               'DECIMAL(12,6)') }}                 AS pre_fixed_rate,
    {{ payload_field('remuneration.postFixedIndexerPercentage', 'DECIMAL(12,6)') }}                 AS post_fixed_indexer_percentage,
    {{ payload_field('remuneration.rateType',                   'VARCHAR') }}                       AS rate_type,
    {{ payload_field('remuneration.ratePeriodicity',            'VARCHAR') }}                       AS rate_periodicity,
    {{ payload_field('remuneration.calculation',                'VARCHAR') }}                       AS calculation,
    {{ payload_field('remuneration.indexer',                    'VARCHAR', required=true) }}        AS indexer,
    {{ payload_field('remuneration.indexerAdditionalInfo',      'VARCHAR') }}                       AS indexer_additional_info,
    {{ payload_field('issueUnitPrice.amount',                   'DECIMAL(25,10)', required=true) }} AS issue_unit_price,
    {{ payload_field('issueUnitPrice.currency',                 'VARCHAR', required=true) }}        AS issue_unit_price_currency,
    {{ payload_field('dueDate',                                 'DATE', required=true) }}           AS due_date,
    {{ payload_field('issueDate',                               'DATE', required=true) }}           AS issue_date,
    {{ payload_field('clearingCode',                            'VARCHAR') }}                       AS clearing_code,
    {{ payload_field('purchaseDate',                            'DATE', required=true) }}           AS purchase_date,
    {{ payload_field('gracePeriodDate',                         'DATE', required=true) }}           AS grace_period_date
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'BANK_FIXED_INCOMES' AND payload_kind = 'detail'
