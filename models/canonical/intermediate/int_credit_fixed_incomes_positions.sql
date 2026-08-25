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
        {{ clean_indexer('indexer') }}         AS indexer,
        {{ desentinel_date('purchase_date') }} AS purchase_date
    )
    FROM joined
),

-- (debtor, due_date) alone is not enough: 13 accounts hold two real ISINs
-- under one such pair, so ISIN stays in the key despite being blank in ~220
-- rows (notebook 03 §1.2). Any NULL part means the row cannot be identified
-- and travels alone as missing_identity.
keyed AS (
    SELECT *,
        CASE WHEN isin_code IS NOT NULL AND debtor_cnpj IS NOT NULL
                  AND due_date IS NOT NULL
             THEN concat_ws('|', isin_code, debtor_cnpj, due_date)
        END AS natural_key
    FROM repaired
),

-- Duplicate groups: two or more investment_ids under one key in one sync.
-- ponytail: group stats assume a snapshot never straddles two incremental
-- batches (ingestion writes snapshots atomically); revisit if that changes.
groups AS (
    SELECT
        snapshot_id,
        account_id,
        natural_key,
        count(DISTINCT quantity)                 AS n_qty,
        count(DISTINCT gross_amount)             AS n_gross,
        count(*) FILTER (WHERE gross_amount > 0) AS n_live
    FROM keyed
    WHERE natural_key IS NOT NULL
    GROUP BY ALL
    HAVING count(DISTINCT investment_id) > 1
),

-- The notebook 03 §2 ladder: quantities differ = partition (real lots),
-- everything agrees = hard_dup (redundant copies), same quantity but gross
-- disagrees = conflict (one side is usually a frozen-zero fossil).
classified AS (
    SELECT
        keyed.*,
        CASE WHEN groups.n_qty IS NULL   THEN 'sole'
             WHEN groups.n_qty > 1       THEN 'partition'
             WHEN groups.n_gross <= 1    THEN 'hard_dup'
             ELSE 'conflict' END AS dup_class,
        groups.n_live,
        row_number() OVER (
            PARTITION BY keyed.snapshot_id, keyed.account_id, keyed.natural_key
            ORDER BY (keyed.gross_amount IS NULL), keyed.investment_id
        ) AS dedup_rank
    FROM keyed
    LEFT JOIN groups
        ON  keyed.snapshot_id = groups.snapshot_id
        AND keyed.account_id  = groups.account_id
        AND keyed.natural_key = groups.natural_key
)

SELECT
    * EXCLUDE (dup_class, n_live, dedup_rank),
    CASE
        WHEN dup_class = 'hard_dup' AND dedup_rank > 1 THEN 'reject_duplicate'
        WHEN dup_class = 'conflict' AND n_live = 1
             AND coalesce(gross_amount, 0) = 0         THEN 'reject_fossil'
        WHEN dup_class = 'conflict' AND n_live <> 1    THEN 'quarantine'
        ELSE 'admit'
    END AS admission,
    list_filter([
        CASE WHEN natural_key IS NULL THEN 'missing_identity' END,
        CASE WHEN dup_class = 'conflict' AND n_live = 1 AND gross_amount > 0
             THEN 'zero_conflict_resolved' END,
        CASE WHEN indexer IS NULL THEN 'missing:indexer' END,
        CASE WHEN purchase_date IS NULL THEN 'missing:purchase_date' END
    ], f -> f IS NOT NULL) AS dq_flags
FROM classified
