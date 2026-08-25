{{ config(materialized='view') }}
-- 1:1 flatten of raw TREASURE_TITLES detail payloads into typed columns, in spec order.
SELECT
    snapshot_id,
    investment_id,
    CAST(snapshot_created_at AS TIMESTAMP) AS snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    {{ payload_field('isinCode',                                'VARCHAR') }}             AS isin_code,
    {{ payload_field('productName',                             'VARCHAR') }}             AS product_name,
    {{ payload_field('remuneration.indexer',                    'VARCHAR') }}             AS indexer,
    {{ payload_field('remuneration.preFixedRate',               'DECIMAL(12,6)') }}       AS pre_fixed_rate,
    {{ payload_field('remuneration.postFixedIndexerPercentage', 'DECIMAL(12,6)') }}       AS post_fixed_indexer_pct,
    {{ payload_field('dueDate',                                 'DATE', required=true) }} AS due_date,
    {{ payload_field('purchaseDate',                            'DATE', required=true) }} AS purchase_date
FROM {{ source('raw_openfinance', 'positions') }}
WHERE investment_type = 'TREASURE_TITLES' AND payload_kind = 'detail'
