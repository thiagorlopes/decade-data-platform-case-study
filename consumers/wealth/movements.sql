-- The movements behind the current holdings. Each movement is tied to the
-- current holding it belongs to via the shared holding_key; movements on
-- lots no longer in the portfolio belong to other consumers (cashflow,
-- net worth over time), not this page.
WITH current_holdings AS (
    SELECT account_id, product_family, holding_key
    FROM fct_holdings
    QUALIFY dense_rank() OVER (
        PARTITION BY account_id, product_family
        ORDER BY snapshot_created_at DESC, snapshot_id DESC
    ) = 1
)

SELECT
    mov.transaction_date,
    mov.institution_name,
    mov.account_id,
    mov.product_family,
    dim.holding_name,
    cur.holding_key,
    mov.movement_type,
    mov.transaction_type,
    mov.transaction_type_additional_info,
    mov.gross_amount,
    mov.net_amount,
    mov.currency,
    mov.transaction_id,
    mov.data_quality_flags
FROM fct_movements AS mov
INNER JOIN current_holdings AS cur
    ON cur.account_id = mov.account_id
    AND cur.product_family = mov.product_family
    AND cur.holding_key = mov.holding_key
INNER JOIN dim_holding AS dim
    ON dim.product_family = cur.product_family
    AND dim.holding_key = cur.holding_key
ORDER BY mov.transaction_date, mov.transaction_id;
