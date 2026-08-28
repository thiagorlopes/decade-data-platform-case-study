-- fct_movements must be free of the duplicates the feed delivers: no group
-- of movements identical on every business field may span two or more
-- investment_ids of one holding, unless those ids were admitted together in
-- some sync (real lots, whose identical movements are real repeats). Any
-- row returned here is a cross-id twin the cross_id_movements macro failed
-- to collapse.
{% set families = ['bank_fixed_incomes', 'credit_fixed_incomes', 'funds', 'treasure_titles', 'variable_incomes'] %}
WITH ids_live_together AS (
    {% for family in families %}
    SELECT DISTINCT lot_a.investment_id AS id_a, lot_b.investment_id AS id_b
    FROM {{ ref('int_' ~ family ~ '_positions') }} AS lot_a
    JOIN {{ ref('int_' ~ family ~ '_positions') }} AS lot_b
        ON  lot_a.snapshot_id   = lot_b.snapshot_id
        AND lot_a.account_id    = lot_b.account_id
        AND lot_a.natural_key   = lot_b.natural_key
        AND lot_a.investment_id < lot_b.investment_id
    WHERE lot_a.admission = 'admit' AND lot_b.admission = 'admit'
    {{ 'UNION' if not loop.last }}
    {% endfor %}
),

same_event AS (
    SELECT
        product_family,
        account_id,
        holding_key,
        transaction_date,
        movement_type,
        transaction_type,
        transaction_type_additional_info,
        quantity,
        gross_amount,
        currency,
        list(DISTINCT investment_id) AS ids
    FROM {{ ref('fct_movements') }}
    GROUP BY ALL
    HAVING count(DISTINCT investment_id) > 1
)

SELECT * FROM same_event
WHERE NOT EXISTS (
    SELECT 1 FROM ids_live_together
    WHERE list_contains(ids, id_a)
      AND list_contains(ids, id_b)
)
