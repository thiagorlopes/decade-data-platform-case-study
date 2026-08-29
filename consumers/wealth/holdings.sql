-- What customers hold, valued at each account's latest sync per family.
-- Reads the consumption layer only, never raw or staging.
SELECT
    fct.institution_name,
    fct.account_id,
    fct.product_family,
    dim.holding_name,
    fct.holding_key,
    -- plain columns are the platform's resolved, row-consistent numbers;
    -- _reported columns are the provider's claims, for reconciliation.
    -- The contract keeps full precision; the page rounds for reading.
    round(fct.unit_price::DOUBLE, 4) AS unit_price,
    round(fct.quantity::DOUBLE, 6) AS quantity,
    round(fct.gross_amount::DOUBLE, 2) AS gross_amount,
    round(fct.quantity_reported::DOUBLE, 6) AS quantity_reported,
    round(fct.gross_amount_reported::DOUBLE, 2) AS gross_amount_reported,
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
ORDER BY fct.gross_amount DESC NULLS LAST, fct.holding_key;
