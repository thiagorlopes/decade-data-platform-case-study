-- What one customer holds, valued at each account's latest sync per family.
-- Reads the consumption layer only, never raw or staging.
-- Parameter: SET VARIABLE party_id = '<uuid>'; (see `make wealth`).
SELECT
    fct.institution_name,
    fct.account_id,
    fct.product_family,
    dim.holding_name,
    fct.holding_key,
    fct.quantity,
    fct.gross_amount,
    fct.currency,
    fct.snapshot_created_at AS valued_at,
    fct.data_quality_flags
FROM fct_holdings AS fct
LEFT JOIN dim_holding AS dim
    ON dim.product_family = fct.product_family
    AND dim.holding_key = fct.holding_key
WHERE fct.party_id = getvariable('party_id')
QUALIFY dense_rank() OVER (
    PARTITION BY fct.account_id, fct.product_family
    ORDER BY fct.snapshot_created_at DESC, fct.snapshot_id DESC
) = 1
ORDER BY fct.gross_amount DESC, fct.holding_key;
