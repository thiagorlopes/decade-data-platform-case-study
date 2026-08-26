-- One row per transaction_id: re-delivered copies collapse to the latest delivery.
-- Column order follows staging spec order; transaction_unit_price_currency is
-- dropped and transaction_amount_currency stands in as the row's `currency`
-- stamp (this family has no gross-amount column).
{{ config(unique_key='transaction_id') }}

SELECT
    snapshot_id,
    payload_source,
    snapshot_created_at,
    institution_id,
    institution_name,
    party_id,
    account_id,
    connection_id,
    investment_id,
    ingested_at,
    movement_type,
    transaction_type,
    transaction_type_additional_info,
    {{ clean_missing_date('transaction_date') }} AS transaction_date,
    price_factor,
    transaction_unit_price,
    transaction_quantity,
    transaction_amount,
    transaction_amount_currency AS currency,
    transaction_id,
    broker_note_id
FROM {{ ref('stg_openfinance__variable_incomes_transactions') }}
{% if is_incremental() %}
-- watermark rationale: README § Materializations
WHERE ingested_at > (SELECT max(ingested_at) FROM {{ this }})
{% endif %}
QUALIFY row_number() OVER (
    PARTITION BY transaction_id
    ORDER BY ingested_at DESC, snapshot_id DESC
) = 1
