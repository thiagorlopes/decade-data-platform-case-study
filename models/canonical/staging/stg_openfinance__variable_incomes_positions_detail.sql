-- 1:1 flatten of raw VARIABLE_INCOMES detail payloads into typed columns.
-- API: GET /investments/{investmentId} — variable-incomes v1.3.0
-- Endpoint in spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/variable-incomes/1.3.0.yml#L122
-- Payload schema #/components/schemas/ResponseVariableIncomesProductIdentificationData: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/variable-incomes/1.3.0.yml#L504
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
    {{ identity_field('issuerInstitutionCnpjNumber') }}                          AS issuer_cnpj,
    {{ identity_field('isinCode',                   required=true) }}            AS isin_code,
    {{ identity_field('ticker',                     required=true) }}            AS ticker
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'VARIABLE_INCOMES' AND payload_kind = 'detail'
