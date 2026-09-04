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
        det.issuer_cnpj,
        det.isin_code,
        det.ticker,
        bal.reference_date,
        bal.price_factor,
        bal.gross_amount,
        bal.gross_amount_currency AS currency,
        bal.blocked_amount,
        bal.quantity,
        bal.closing_price
    FROM {{ latest_lot_delivery(ref('stg_openfinance__variable_incomes_positions_detail')) }} AS det
    FULL JOIN {{ latest_lot_delivery(ref('stg_openfinance__variable_incomes_positions_balances')) }} AS bal
        USING (snapshot_id, investment_id)
    {% if is_incremental() %}
    -- watermark rationale: README § Materializations
    WHERE {{ snapshot_watermark([ref('stg_openfinance__variable_incomes_positions_detail'),
                                 ref('stg_openfinance__variable_incomes_positions_balances')]) }}
    {% endif %}
),

-- issuer_cnpj is clean in today's data; the repair is kept as a guard.
repaired AS (
    SELECT {{ decade.star_replace({
        'issuer_cnpj': clean_cnpj('issuer_cnpj'),
        'isin_code':   blank_to_null('isin_code'),
        'ticker':      blank_to_null('ticker')
    }) }}
    FROM joined
),

-- Impute isin_code from the instrument map when the delivered value was
-- blank. The map's HAVING guard keeps ambiguous tickers out, so imputation
-- never picks between conflicting values silently. Column list mirrors joined.
imputed AS (
    SELECT
        rep.snapshot_id,
        rep.investment_id,
        rep.snapshot_created_at,
        rep.institution_id,
        rep.institution_name,
        rep.party_id,
        rep.account_id,
        rep.connection_id,
        rep.ingested_at,
        rep.issuer_cnpj,
        coalesce(rep.isin_code, map.isin_code) AS isin_code,
        rep.ticker,
        rep.reference_date,
        rep.price_factor,
        rep.gross_amount,
        rep.currency,
        rep.blocked_amount,
        rep.quantity,
        rep.closing_price,
        (rep.isin_code IS NULL AND map.isin_code IS NOT NULL) AS is_isin_imputed
    FROM repaired AS rep
    LEFT JOIN {{ ref('int_variable_incomes_instruments') }} AS map
        ON rep.ticker = map.ticker
),

-- ticker alone: ISIN is blank in ~900 rows and would fragment the key; no
-- account quotes two real ISINs under one ticker (notebook 03 §1.2).
with_natural_key AS (
    SELECT *, ticker AS natural_key
    FROM imputed
),

{{ resolve_duplicate_investments(extra_flags=[
    ('ticker IS NULL',    'ticker:missing'),
    ('isin_code IS NULL', 'isin_code:missing'),
    ('is_isin_imputed',   'isin_code:imputed'),
    ('abs(gross_amount::DOUBLE - quantity::DOUBLE * closing_price::DOUBLE / coalesce(price_factor::DOUBLE, 1)) > greatest(abs(gross_amount::DOUBLE) * 0.005, 0.02)', 'gross:not_quantity_times_price'),
]) }}
