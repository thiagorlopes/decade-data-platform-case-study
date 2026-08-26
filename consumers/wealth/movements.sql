-- The movements behind the customer's holdings. Each movement is tagged with
-- the current holding it belongs to by matching its investment_id against the
-- holding's contributing ids; the tag is NULL when the movement's lot is no
-- longer in the portfolio (closed or handed off).
-- Parameter: SET VARIABLE party_id = '<uuid>'; (see `make wealth`).
WITH current_holdings AS (
    SELECT account_id, product_family, holding_key, holding_name, investment_ids
    FROM fct_holdings
    WHERE party_id = getvariable('party_id')
    QUALIFY dense_rank() OVER (
        PARTITION BY account_id, product_family
        ORDER BY snapshot_created_at DESC, snapshot_id DESC
    ) = 1
)

SELECT
    m.transaction_date,
    m.institution_name,
    m.account_id,
    m.product_family,
    h.holding_name,
    h.holding_key,
    m.movement_type,
    m.transaction_type,
    m.transaction_type_additional_info,
    m.gross_amount,
    m.net_amount,
    m.currency,
    m.transaction_id,
    m.data_quality_flags
FROM fct_movements AS m
LEFT JOIN current_holdings AS h
    ON h.account_id = m.account_id
    AND h.product_family = m.product_family
    AND list_contains(h.investment_ids, m.investment_id)
WHERE m.party_id = getvariable('party_id')
ORDER BY m.transaction_date, m.transaction_id;
