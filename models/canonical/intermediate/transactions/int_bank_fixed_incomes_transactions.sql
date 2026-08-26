-- One row per transaction_id: re-delivered copies collapse to the latest delivery.
-- Column order follows staging spec order; per-amount currency siblings are dropped
-- and transaction_gross_amount_currency stands in as the row's `currency` stamp.
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
    transaction_date,
    transaction_unit_price,
    transaction_quantity,
    transaction_gross_amount,
    transaction_gross_amount_currency AS currency,
    income_tax_amount,
    financial_transaction_tax_amount,
    transaction_net_amount,
    remuneration_rate,
    indexer_percentage,
    transaction_id,
    count(*) OVER (PARTITION BY transaction_id) AS n_copies
FROM {{ ref('stg_openfinance__bank_fixed_incomes_transactions') }}
{% if is_incremental() %}
-- watermark rationale: README § Materializations
WHERE ingested_at > (SELECT max(ingested_at) FROM {{ this }})
{% endif %}
QUALIFY row_number() OVER (
    PARTITION BY transaction_id
    ORDER BY ingested_at DESC, snapshot_id DESC
) = 1
