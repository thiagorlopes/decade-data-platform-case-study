-- One row per investment (snapshot_id, investment_id), classified but never deleted.
WITH joined AS (
    -- FULL JOIN because some investments arrive with balances only (no detail payload).
    -- Column order follows staging spec order: envelope, then detail, then balances.
    -- pre_fixed_rate / post_fixed_indexer_percentage appear in both sides; the
    -- detail copy is authoritative (static contract of the security).
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
        det.pre_fixed_rate,
        det.post_fixed_indexer_percentage,
        det.rate_type,
        det.rate_periodicity,
        det.calculation,
        det.indexer,
        det.indexer_additional_info,
        det.issue_unit_price,
        det.due_date,
        det.issue_date,
        det.clearing_code,
        det.purchase_date,
        det.grace_period_date,
        bal.reference_datetime,
        bal.quantity,
        bal.updated_unit_price,
        bal.gross_amount,
        bal.gross_amount_currency AS currency,
        bal.net_amount,
        bal.income_tax_amount,
        bal.financial_transaction_tax_amount,
        bal.blocked_amount,
        bal.purchase_unit_price
    FROM {{ latest_delivery(ref('stg_openfinance__bank_fixed_incomes_positions_detail')) }} AS det
    FULL JOIN {{ latest_delivery(ref('stg_openfinance__bank_fixed_incomes_positions_balances')) }} AS bal
        USING (snapshot_id, investment_id)
    {% if is_incremental() %}
    -- watermark rationale: README § Materializations
    WHERE {{ snapshot_watermark([ref('stg_openfinance__bank_fixed_incomes_positions_detail'),
                                 ref('stg_openfinance__bank_fixed_incomes_positions_balances')]) }}
    {% endif %}
),

repaired AS (
    SELECT * REPLACE (
        {{ clean_cnpj('issuer_cnpj') }}        AS issuer_cnpj,
        {{ blank_to_null('isin_code') }}       AS isin_code,
        {{ clean_indexer('indexer') }}         AS indexer,
        {{ clean_missing_date('purchase_date') }} AS purchase_date
    )
    FROM joined
),

-- Banks re-use ISINs across CDB issuances; (issuer, issue_date, due_date)
-- pins one issuance (notebook 03 §1.2). Any NULL part means the row cannot
-- be identified and travels alone as missing:natural_key.
with_natural_key AS (
    SELECT *,
        CASE WHEN isin_code IS NOT NULL AND issuer_cnpj IS NOT NULL
                  AND issue_date IS NOT NULL AND due_date IS NOT NULL
             THEN concat_ws('|', isin_code, issuer_cnpj, issue_date, due_date)
        END AS natural_key
    FROM repaired
),

{{ resolve_duplicate_investments(extra_flags=[
    ('isin_code IS NULL',     'missing:isin_code'),
    ('issuer_cnpj IS NULL',   'missing:issuer_cnpj'),
    ('issue_date IS NULL',    'missing:issue_date'),
    ('due_date IS NULL',      'missing:due_date'),
    ('indexer IS NULL',       'missing:indexer'),
    ('purchase_date IS NULL', 'missing:purchase_date'),
    ('net_amount > gross_amount + 0.01', 'net:above_gross'),
    ('abs(gross_amount::DOUBLE - quantity::DOUBLE * updated_unit_price::DOUBLE) > greatest(abs(gross_amount::DOUBLE) * 0.005, 0.02)', 'gross:price_mismatch'),
    ('financial_transaction_tax_amount <> 0 AND abs(gross_amount - net_amount - coalesce(income_tax_amount, 0)) <= 0.02', 'financial_transaction_tax:not_deducted'),
]) }}
