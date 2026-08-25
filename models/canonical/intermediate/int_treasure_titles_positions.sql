-- One row per lot (snapshot_id, investment_id): the lot's detail and balances
-- staging rows joined into a single record.
-- FULL JOIN because some lots arrive with balances only (no detail payload);
-- has_detail / has_balances mark which payloads actually arrived.
SELECT
    snapshot_id,
    investment_id,
    det.snapshot_id IS NOT NULL AS has_detail,
    bal.snapshot_id IS NOT NULL AS has_balances,
    coalesce(det.snapshot_created_at, bal.snapshot_created_at) AS snapshot_created_at,
    coalesce(det.institution_id,   bal.institution_id)   AS institution_id,
    coalesce(det.institution_name, bal.institution_name) AS institution_name,
    coalesce(det.party_id,         bal.party_id)         AS party_id,
    coalesce(det.account_id,       bal.account_id)       AS account_id,
    coalesce(det.connection_id,    bal.connection_id)    AS connection_id,
    -- max of the two arrival times; coalesce pairing keeps greatest() away from NULLs
    greatest(coalesce(det.ingested_at, bal.ingested_at), coalesce(bal.ingested_at, det.ingested_at)) AS ingested_at,
    det.isin_code,
    det.product_name,
    det.indexer,
    det.pre_fixed_rate,
    det.post_fixed_indexer_percentage,
    det.due_date,
    det.purchase_date,
    bal.reference_datetime,
    bal.updated_unit_price,
    bal.gross_amount,
    bal.net_amount,
    bal.income_tax_amount,
    bal.financial_transaction_tax_amount,
    bal.blocked_amount,
    bal.purchase_unit_price,
    bal.quantity,
    bal.currency
FROM {{ ref('stg_openfinance__treasure_titles_positions_detail') }} AS det
FULL JOIN {{ ref('stg_openfinance__treasure_titles_positions_balances') }} AS bal
    USING (snapshot_id, investment_id)
{% if is_incremental() %}
-- watermark on arrival time: late records carry a fresh ingested_at and still land;
-- a re-delivered record passes the filter and overwrites via unique_key;
-- reprocessing after a transform fix = dbt build --full-refresh
WHERE greatest(coalesce(det.ingested_at, bal.ingested_at), coalesce(bal.ingested_at, det.ingested_at))
    > (SELECT max(ingested_at) FROM {{ this }})
{% endif %}
