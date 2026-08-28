-- What customers hold, valued at each account's latest sync per family.
-- Reads the consumption layer only, never raw or staging.
SELECT
    fct.institution_name,
    fct.account_id,
    fct.product_family,
    dim.holding_name,
    fct.holding_key,
    -- movements are the reliable record of quantity (stale:quantity in
    -- data_quality_flags); fall back to the provider's number only when the
    -- movements are incomplete and the replay cannot be trusted
    CASE WHEN list_contains(fct.data_quality_flags, 'movements:incomplete')
         THEN fct.quantity
         ELSE coalesce(fct.quantity_derived, fct.quantity)
    END AS quantity,
    fct.quantity AS quantity_reported,
    fct.gross_amount,
    fct.currency,
    fct.snapshot_created_at AS valued_at,
    fct.data_quality_flags
FROM fct_holdings AS fct
LEFT JOIN dim_holding AS dim
    ON dim.product_family = fct.product_family
    AND dim.holding_key = fct.holding_key
QUALIFY dense_rank() OVER (
    PARTITION BY fct.account_id, fct.product_family
    ORDER BY fct.snapshot_created_at DESC, fct.snapshot_id DESC
) = 1
ORDER BY fct.gross_amount DESC, fct.holding_key;
