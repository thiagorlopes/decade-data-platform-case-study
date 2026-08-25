-- 1:1 flatten of raw CREDIT_FIXED_INCOMES detail payloads into typed columns, in spec order.
-- Spec: https://github.com/OpenBanking-Brasil/draft-openapi/blob/main/swagger-apis/credit-fixed-incomes/1.1.0.yml
SELECT
    snapshot_id,
    investment_id,
    CAST(snapshot_created_at AS TIMESTAMP) AS snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    {{ payload_field('issuerInstitutionCnpjNumber',             'VARCHAR') }}                       AS issuer_cnpj,
    {{ payload_field('isinCode',                                'VARCHAR') }}                       AS isin_code,
    {{ payload_field('investmentType',                          'VARCHAR') }}                       AS product_type,
    {{ payload_field('debtorCnpjNumber',                        'VARCHAR') }}                       AS debtor_cnpj,
    {{ payload_field('debtorName',                              'VARCHAR') }}                       AS debtor_name,
    {{ payload_field('taxExemptProduct',                        'VARCHAR') }}                       AS tax_exempt,
    {{ payload_field('remuneration.indexer',                    'VARCHAR') }}                       AS indexer,
    {{ payload_field('remuneration.preFixedRate',               'DECIMAL(12,6)') }}                 AS pre_fixed_rate,
    {{ payload_field('remuneration.postFixedIndexerPercentage', 'DECIMAL(12,6)') }}                 AS post_fixed_indexer_pct,
    {{ payload_field('issueUnitPrice.amount',                   'DECIMAL(25,10)', required=true) }} AS issue_unit_price,
    {{ payload_field('issueDate',                               'DATE', required=true) }}           AS issue_date,
    {{ payload_field('dueDate',                                 'DATE', required=true) }}           AS due_date,
    {{ payload_field('clearingCode',                            'VARCHAR') }}                       AS clearing_code,
    {{ payload_field('purchaseDate',                            'DATE', required=true) }}           AS purchase_date
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'CREDIT_FIXED_INCOMES' AND payload_kind = 'detail'
