{{ config(materialized='view') }}
-- 1:1 flatten of raw VARIABLE_INCOMES detail payloads into typed columns, in spec order.
SELECT
    snapshot_id,
    investment_id,
    CAST(snapshot_created_at AS TIMESTAMP) AS snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    {{ payload_field('issuerInstitutionCnpjNumber', 'VARCHAR') }} AS issuer_cnpj,
    {{ payload_field('isinCode',                    'VARCHAR') }} AS isin_code,
    {{ payload_field('ticker',                      'VARCHAR') }} AS ticker
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'VARIABLE_INCOMES' AND payload_kind = 'detail'
