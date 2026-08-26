-- One row per lot (snapshot_id, investment_id), classified but never deleted.
-- Pipeline: join detail+balances, repair within-record defects (notebook 02),
-- derive the natural key from the REPAIRED columns, then classify duplicate
-- groups within each sync (notebook 03). `admission` says what downstream may
-- aggregate; rejected and quarantined rows stay here for audit.
WITH joined AS (
    -- FULL JOIN because some lots arrive with balances only (no detail payload).
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
        bal.gross_amount_currency
    FROM {{ ref('stg_openfinance__treasure_titles_positions_detail') }} AS det
    FULL JOIN {{ ref('stg_openfinance__treasure_titles_positions_balances') }} AS bal
        USING (snapshot_id, investment_id)
    {% if is_incremental() %}
    -- watermark rationale: README § Materializations
    WHERE greatest(det.ingested_at, bal.ingested_at) > (SELECT max(ingested_at) FROM {{ this }})
    {% endif %}
),

-- Repairs happen here, not in staging, so the staging warn tests keep
-- counting the raw provider defects.
repaired AS (
    SELECT * REPLACE (
        {{ clean_indexer('indexer') }}         AS indexer,
        {{ desentinel_date('purchase_date') }} AS purchase_date
    )
    FROM joined
),

-- Tesouro Direto has one title per name ("Tesouro Selic 2031"); ISIN would
-- be the cleaner key but is blank in ~400 rows, and no account maps one name
-- to two real ISINs (notebook 03 §1.2).
keyed AS (
    SELECT *, product_name AS natural_key
    FROM repaired
),

{{ classify_and_admit(extra_flags=[
    ('indexer IS NULL',       'missing:indexer'),
    ('purchase_date IS NULL', 'missing:purchase_date'),
]) }}
