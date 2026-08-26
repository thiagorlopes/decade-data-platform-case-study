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
        det.fund_name,
        det.fund_cnpj,
        det.anbima_category,
        bal.reference_date,
        bal.gross_amount,
        bal.net_amount,
        bal.income_tax_amount,
        bal.financial_transaction_tax_amount,
        bal.blocked_amount,
        bal.quota_quantity,
        bal.quota_gross_price,
        bal.gross_amount_currency
    FROM {{ ref('stg_openfinance__funds_positions_detail') }} AS det
    FULL JOIN {{ ref('stg_openfinance__funds_positions_balances') }} AS bal
        USING (snapshot_id, investment_id)
    {% if is_incremental() %}
    -- watermark rationale: README § Materializations
    WHERE greatest(det.ingested_at, bal.ingested_at) > (SELECT max(ingested_at) FROM {{ this }})
    {% endif %}
),

-- fund_cnpj is clean in today's data; the repair is kept as a guard because
-- it is also the natural key, and a decimal-tailed copy would split a fund.
repaired AS (
    SELECT * REPLACE (
        {{ clean_cnpj('fund_cnpj') }} AS fund_cnpj
    )
    FROM joined
),

-- One open-ended fund maps to exactly one CNPJ (notebook 03 §1.2).
with_natural_key AS (
    SELECT *, fund_cnpj AS natural_key
    FROM repaired
),

{{ resolve_duplicate_investments(qty_col='quota_quantity', extra_flags=[
    ('gross_amount IS NULL',   'missing:gross_amount'),
    ('quota_quantity IS NULL', 'missing:quota_quantity'),
]) }}
