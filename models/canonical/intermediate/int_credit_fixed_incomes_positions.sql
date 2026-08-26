-- One row per investment (snapshot_id, investment_id), classified but never deleted.
-- Pipeline: join detail+balances, repair within-record defects (notebook 02),
-- derive the natural key from the REPAIRED columns, then classify duplicate
-- groups within each sync (notebook 03). `admission` says what downstream may
-- aggregate; rejected and quarantined rows stay here for audit.
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
        det.investment_type,
        det.debtor_cnpj,
        det.debtor_name,
        det.tax_exempt,
        det.indexer,
        det.pre_fixed_rate,
        det.post_fixed_indexer_percentage,
        det.issue_unit_price,
        det.issue_date,
        det.due_date,
        det.clearing_code,
        det.purchase_date,
        bal.reference_datetime,
        bal.updated_unit_price,
        bal.quantity,
        bal.gross_amount,
        bal.net_amount,
        bal.income_tax_amount,
        bal.financial_transaction_tax_amount,
        bal.blocked_amount,
        bal.purchase_unit_price,
        bal.gross_amount_currency
    FROM {{ ref('stg_openfinance__credit_fixed_incomes_positions_detail') }} AS det
    FULL JOIN {{ ref('stg_openfinance__credit_fixed_incomes_positions_balances') }} AS bal
        USING (snapshot_id, investment_id)
    {% if is_incremental() %}
    -- watermark rationale: README § Materializations
    WHERE greatest(det.ingested_at, bal.ingested_at) > (SELECT max(ingested_at) FROM {{ this }})
    {% endif %}
),

-- Repairs happen here, not in staging, so the staging warn tests keep
-- counting the raw provider defects. debtor_cnpj must be repaired BEFORE
-- key derivation: a decimal-tailed copy would split one holding in two.
repaired AS (
    SELECT * REPLACE (
        {{ clean_cnpj('issuer_cnpj') }}        AS issuer_cnpj,
        {{ clean_cnpj('debtor_cnpj') }}        AS debtor_cnpj,
        {{ blank_to_null('isin_code') }}       AS isin_code,
        {{ clean_indexer('indexer') }}         AS indexer,
        {{ clean_missing_date('purchase_date') }} AS purchase_date
    )
    FROM joined
),

-- (debtor, due_date) alone is not enough: 13 accounts hold two real ISINs
-- under one such pair, so ISIN stays in the key despite being blank in ~220
-- rows (notebook 03 §1.2). Any NULL part means the row cannot be identified
-- and travels alone as missing_key.
keyed AS (
    SELECT *,
        CASE WHEN isin_code IS NOT NULL AND debtor_cnpj IS NOT NULL
                  AND due_date IS NOT NULL
             THEN concat_ws('|', isin_code, debtor_cnpj, due_date)
        END AS natural_key
    FROM repaired
),

{{ resolve_duplicate_investments(extra_flags=[
    ('indexer IS NULL',       'missing:indexer'),
    ('purchase_date IS NULL', 'missing:purchase_date'),
]) }}
