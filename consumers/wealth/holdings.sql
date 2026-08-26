-- What one customer holds, valued at each account's latest sync per family.
-- Reads the consumption layer only, never raw or staging.
-- Parameter: SET VARIABLE party_id = '<uuid>'; (see `make wealth`).
SELECT
    institution_name,
    account_id,
    product_family,
    holding_name,
    holding_key,
    quantity,
    gross_amount,
    currency,
    snapshot_created_at AS valued_at,
    data_quality_flags
FROM fct_holdings
WHERE party_id = getvariable('party_id')
QUALIFY dense_rank() OVER (
    PARTITION BY account_id, product_family
    ORDER BY snapshot_created_at DESC, snapshot_id DESC
) = 1
ORDER BY gross_amount DESC, holding_key;
