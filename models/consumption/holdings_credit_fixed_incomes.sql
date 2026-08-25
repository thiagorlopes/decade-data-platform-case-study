-- One row per holding per sync: admitted lots aggregated on the natural key.
-- Missing-identity lots use their investment_id as key and travel alone.
-- Cross-sync flags (zero_flap, id_handoff) need the holding-grain timeline,
-- so they are computed here rather than in the intermediate layer.
WITH admitted AS (
    SELECT * FROM {{ ref('int_credit_fixed_incomes_positions') }}
    WHERE admission = 'admit'
),

holding AS (
    SELECT
        snapshot_id,
        account_id,
        coalesce(natural_key, investment_id)            AS holding_key,
        any_value(snapshot_created_at)                  AS snapshot_created_at,
        any_value(institution_name)                     AS institution_name,
        any_value(investment_type)                      AS investment_type,
        any_value(isin_code)                            AS isin_code,
        any_value(debtor_name)                          AS debtor_name,
        sum(quantity)                                   AS quantity,
        sum(gross_amount)                               AS gross_amount,
        any_value(gross_amount_currency)                AS currency,
        count(*)                                        AS n_lots,
        array_agg(investment_id ORDER BY investment_id) AS investment_ids,
        bool_or(coalesce(gross_amount, 0) = 0)          AS has_zero_lot,
        flatten(array_agg(dq_flags))                    AS lot_flags
    FROM admitted
    GROUP BY snapshot_id, account_id, holding_key
),

timeline AS (
    SELECT
        *,
        lag(gross_amount)   OVER win AS prev_gross,
        lead(gross_amount)  OVER win AS next_gross,
        lag(quantity)       OVER win AS prev_qty,
        lead(quantity)      OVER win AS next_qty,
        lag(investment_ids) OVER win AS prev_ids
    FROM holding
    WINDOW win AS (
        PARTITION BY account_id, holding_key
        ORDER BY snapshot_created_at, snapshot_id
    )
)

SELECT
    snapshot_created_at,
    snapshot_id,
    account_id,
    institution_name,
    holding_key,
    investment_type,
    isin_code,
    debtor_name,
    quantity,
    gross_amount,
    currency,
    n_lots,
    investment_ids,
    list_distinct(lot_flags || list_filter([
        CASE WHEN n_lots > 1 THEN 'merged_lots' END,
        CASE WHEN n_lots > 1 AND has_zero_lot THEN 'zero_gross_lot' END,
        CASE WHEN gross_amount = 0 AND prev_gross > 0 AND next_gross > 0
                  AND quantity = prev_qty AND quantity = next_qty
             THEN 'zero_flap' END,
        CASE WHEN len(list_filter(investment_ids, id -> NOT list_contains(prev_ids, id))) > 0
              AND len(list_filter(prev_ids, id -> NOT list_contains(investment_ids, id))) > 0
             THEN 'id_handoff' END
    ], f -> f IS NOT NULL)) AS dq_flags
FROM timeline
