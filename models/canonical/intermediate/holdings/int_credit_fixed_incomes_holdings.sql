WITH admitted AS (
    SELECT * FROM {{ ref('int_credit_fixed_incomes_positions') }}
    WHERE admission = 'admit'
),

{{ replay_quantity(ref('int_credit_fixed_incomes_transactions')) }},

holding AS (
    SELECT
        snapshot_id,
        account_id,
        coalesce(natural_key, admitted.investment_id)   AS holding_key,
        any_value(party_id)                             AS party_id,
        any_value(snapshot_created_at)                  AS snapshot_created_at,
        CAST(any_value(reference_datetime) AS DATE)     AS reference_date,
        any_value(institution_id)                       AS institution_id,
        any_value(institution_name)                     AS institution_name,
        any_value(investment_type)                      AS investment_type,
        any_value(isin_code)                            AS isin_code,
        any_value(debtor_name)                          AS debtor_name,
        sum(quantity)                                   AS quantity,
        sum(replay.replay_quantity)                     AS quantity_derived,
        sum(gross_amount)                               AS gross_amount,
        sum(net_amount)                                 AS net_amount,
        any_value(currency)                AS currency,
        count(*)                                        AS n_investment_ids,
        array_agg(admitted.investment_id ORDER BY admitted.investment_id) AS investment_ids,
        bool_or(coalesce(gross_amount, 0) = 0)          AS has_zero_lot,
        bool_or(replay.min_running_total < -0.001
                OR coalesce(replay.n_qty_receipts, 0) = 0)          AS has_incomplete_replay,
        bool_or(abs(quantity - replay.replay_quantity) >= 0.001)    AS has_stale_lot,
        flatten(array_agg(data_quality_flags))                    AS lot_flags
    FROM admitted
    LEFT JOIN replay ON admitted.investment_id = replay.investment_id
    GROUP BY snapshot_id, account_id, holding_key
),

{{ holding_timeline() }}

SELECT
    snapshot_created_at,
    reference_date,
    snapshot_id,
    account_id,
    party_id,
    institution_id,
    institution_name,
    holding_key,
    investment_type,
    isin_code,
    debtor_name,
    quantity,
    quantity_derived,
    gross_amount,
    net_amount,
    currency,
    n_investment_ids,
    investment_ids,
    {{ holding_data_quality_flags() }} AS data_quality_flags
FROM timeline
