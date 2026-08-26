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
        any_value(currency)                AS currency,
        count(*)                                        AS n_lots,
        array_agg(investment_id ORDER BY investment_id) AS investment_ids,
        bool_or(coalesce(gross_amount, 0) = 0)          AS has_zero_lot,
        flatten(array_agg(data_quality_flags))                    AS lot_flags
    FROM admitted
    GROUP BY snapshot_id, account_id, holding_key
),

{{ holding_timeline() }}

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
    {{ holding_data_quality_flags() }} AS data_quality_flags
FROM timeline
