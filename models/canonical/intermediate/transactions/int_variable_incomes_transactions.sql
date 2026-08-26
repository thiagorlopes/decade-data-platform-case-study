-- One row per transaction_id: re-delivered copies collapse to the latest delivery.
{{ config(unique_key='transaction_id') }}

-- transaction_unit_price_currency dropped; transaction_amount_currency
-- stands in as the row-currency stamp (no gross column in this family).
SELECT
    * EXCLUDE (transaction_unit_price_currency),
    list_filter([
        CASE WHEN movement_type IS NULL      THEN 'missing:movement_type' END,
        CASE WHEN transaction_type IS NULL   THEN 'missing:transaction_type' END,
        CASE WHEN transaction_date IS NULL   THEN 'missing:transaction_date' END,
        CASE WHEN transaction_amount IS NULL THEN 'missing:transaction_amount' END
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM {{ ref('stg_openfinance__variable_incomes_transactions') }}
{% if is_incremental() %}
-- watermark rationale: README § Materializations
WHERE ingested_at > (SELECT max(ingested_at) FROM {{ this }})
{% endif %}
QUALIFY row_number() OVER (
    PARTITION BY transaction_id
    ORDER BY ingested_at DESC, snapshot_id DESC
) = 1
