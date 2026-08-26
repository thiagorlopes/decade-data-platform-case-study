-- 1:1 flatten of raw FUNDS detail payloads into typed columns, in spec order.
-- API: GET /investments/{investmentId} — funds v1.1.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/funds/1.1.0.yml#L98
-- Payload schema #/components/schemas/ResponseFundsProductIdentificationData: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/funds/1.1.0.yml#L457
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
    {{ payload_field('name',           'VARCHAR', required=true) }} AS fund_name,
    {{ blank_to_null_field('cnpjNumber',    required=true) }}            AS fund_cnpj,
    {{ blank_to_null_field('isinCode') }}                                AS isin_code,
    {{ payload_field('anbimaCategory', 'VARCHAR') }}                AS anbima_category,
    {{ payload_field('anbimaClass',    'VARCHAR') }}                AS anbima_class,
    {{ payload_field('anbimaSubclass', 'VARCHAR') }}                AS anbima_subclass
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'FUNDS' AND payload_kind = 'detail'
