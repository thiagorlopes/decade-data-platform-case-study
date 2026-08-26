-- One row per investment (snapshot_id, investment_id), classified but never deleted.
WITH joined AS (
    -- FULL JOIN because some investments arrive with balances only (no detail payload).
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
        det.issuer_cnpj,
        det.isin_code,
        det.ticker,
        bal.reference_date,
        bal.price_factor,
        bal.gross_amount,
        bal.blocked_amount,
        bal.quantity,
        bal.closing_price,
        bal.gross_amount_currency
    FROM {{ ref('stg_openfinance__variable_incomes_positions_detail') }} AS det
    FULL JOIN {{ ref('stg_openfinance__variable_incomes_positions_balances') }} AS bal
        USING (snapshot_id, investment_id)
    {% if is_incremental() %}
    -- watermark rationale: README § Materializations
    WHERE greatest(det.ingested_at, bal.ingested_at) > (SELECT max(ingested_at) FROM {{ this }})
    {% endif %}
),

-- issuer_cnpj is clean in today's data; the repair is kept as a guard.
repaired AS (
    SELECT * REPLACE (
        {{ clean_cnpj('issuer_cnpj') }}   AS issuer_cnpj,
        {{ blank_to_null('isin_code') }}  AS isin_code,
        {{ blank_to_null('ticker') }}     AS ticker
    )
    FROM joined
),

-- ticker alone: ISIN is blank in ~900 rows and would fragment the key; no
-- account quotes two real ISINs under one ticker (notebook 03 §1.2).
keyed AS (
    SELECT *, ticker AS natural_key
    FROM repaired
),

{{ resolve_duplicate_investments() }}
