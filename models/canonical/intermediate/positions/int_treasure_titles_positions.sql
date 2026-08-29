-- One row per investment (snapshot_id, investment_id), classified but never deleted.
WITH joined AS (
    -- FULL JOIN because some investments arrive with balances only (no detail payload).
    -- Column order follows staging spec order: envelope, then detail, then balances.
    SELECT
        snapshot_id,
        investment_id,
        coalesce(det.snapshot_created_at, bal.snapshot_created_at) AS snapshot_created_at,
        coalesce(det.institution_id,   bal.institution_id)   AS institution_id,
        coalesce(det.institution_name, bal.institution_name) AS institution_name,
        coalesce(det.party_id,         bal.party_id)         AS party_id,
        coalesce(det.account_id,       bal.account_id)       AS account_id,
        coalesce(det.connection_id,    bal.connection_id)    AS connection_id,
        greatest(det.ingested_at, bal.ingested_at) AS ingested_at,
        det.isin_code,
        det.product_name,
        det.indexer,
        det.indexer_additional_info,
        det.pre_fixed_rate,
        det.post_fixed_indexer_percentage,
        det.rate_periodicity,
        det.calculation,
        det.due_date,
        det.purchase_date,
        det.voucher_payment_indicator,
        det.voucher_payment_periodicity,
        det.voucher_payment_periodicity_additional_info,
        bal.reference_datetime,
        bal.updated_unit_price,
        bal.gross_amount,
        bal.gross_amount_currency AS currency,
        bal.net_amount,
        bal.income_tax_amount,
        bal.financial_transaction_tax_amount,
        bal.blocked_amount,
        bal.purchase_unit_price,
        bal.quantity
    FROM {{ latest_delivery(ref('stg_openfinance__treasure_titles_positions_detail')) }} AS det
    FULL JOIN {{ latest_delivery(ref('stg_openfinance__treasure_titles_positions_balances')) }} AS bal
        USING (snapshot_id, investment_id)
    {% if is_incremental() %}
    -- watermark rationale: README § Materializations
    WHERE {{ snapshot_watermark([ref('stg_openfinance__treasure_titles_positions_detail'),
                                 ref('stg_openfinance__treasure_titles_positions_balances')]) }}
    {% endif %}
),

repaired AS (
    SELECT * REPLACE (
        {{ blank_to_null('isin_code') }}       AS isin_code,
        {{ blank_to_null('product_name') }}    AS product_name,
        {{ clean_indexer('indexer') }}         AS indexer,
        {{ clean_missing_date('purchase_date') }} AS purchase_date
    )
    FROM joined
),

-- Tesouro Direto has one title per name ("Tesouro Selic 2031"); ISIN would
-- be the cleaner key but is blank in ~400 rows, and no account maps one name
-- to two real ISINs (notebook 03 §1.2).
with_natural_key AS (
    SELECT *, product_name AS natural_key
    FROM repaired
),

{{ resolve_duplicate_investments(extra_flags=[
    ('product_name IS NULL',  'missing:product_name'),
    ('isin_code IS NULL',     'missing:isin_code'),
    ('indexer IS NULL',       'missing:indexer'),
    ('purchase_date IS NULL', 'missing:purchase_date'),
    ('net_amount > gross_amount + 0.01', 'net:above_gross'),
    ('abs(gross_amount::DOUBLE - quantity::DOUBLE * updated_unit_price::DOUBLE) > greatest(abs(gross_amount::DOUBLE) * 0.005, 0.02)', 'gross:price_mismatch'),
    ('financial_transaction_tax_amount <> 0 AND abs(gross_amount - net_amount - coalesce(income_tax_amount, 0)) <= 0.02', 'financial_transaction_tax:not_deducted'),
]) }}
