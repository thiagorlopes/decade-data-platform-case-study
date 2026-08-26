-- One row per transaction_id: re-delivered copies collapse to the latest delivery.
{{ config(unique_key='transaction_id') }}

-- Per-amount currency siblings dropped; transaction_gross_amount_currency
-- stands in as the row-currency stamp.
SELECT
    * EXCLUDE (
        transaction_unit_price_currency,
        income_tax_amount_currency,
        financial_transaction_tax_amount_currency,
        transaction_net_amount_currency
    ),
    list_filter([
        CASE WHEN movement_type IS NULL            THEN 'missing:movement_type' END,
        CASE WHEN transaction_type IS NULL         THEN 'missing:transaction_type' END,
        CASE WHEN transaction_date IS NULL         THEN 'missing:transaction_date' END,
        CASE WHEN transaction_gross_amount IS NULL THEN 'missing:transaction_gross_amount' END,
        CASE WHEN transaction_quantity IS NULL     THEN 'missing:transaction_quantity' END
    ], f -> f IS NOT NULL) AS data_quality_flags
FROM {{ ref('stg_openfinance__treasure_titles_transactions') }}
{% if is_incremental() %}
-- watermark rationale: README § Materializations
WHERE ingested_at > (SELECT max(ingested_at) FROM {{ this }})
{% endif %}
QUALIFY row_number() OVER (
    PARTITION BY transaction_id
    ORDER BY ingested_at DESC, snapshot_id DESC
) = 1
