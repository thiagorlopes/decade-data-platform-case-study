WITH admitted AS (
    SELECT * FROM {{ ref('int_bank_fixed_incomes_positions') }}
    WHERE admission = 'admit'
),

movements_clean AS
    {{ cross_id_movements(ref('int_bank_fixed_incomes_transactions'),
                          ref('int_bank_fixed_incomes_positions')) }},

{{ replay_quantity('movements_clean') }},

lots AS (
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
        sum(quantity)                                   AS quantity,
        sum(gross_amount)                               AS gross_amount,
        sum(net_amount)                                 AS net_amount,
        any_value(currency)                AS currency,
        coalesce(
            CAST(sum(quantity::DOUBLE * updated_unit_price::DOUBLE) / nullif(sum(quantity::DOUBLE), 0) AS DECIMAL(38, 10)),
            CAST(avg(updated_unit_price::DOUBLE) AS DECIMAL(38, 10))
        )                                               AS unit_price,
        count(*)                                        AS n_investment_ids,
        array_agg(admitted.investment_id ORDER BY admitted.investment_id) AS investment_ids,
        bool_or(coalesce(gross_amount, 0) = 0)          AS has_zero_lot,
        flatten(array_agg(data_quality_flags))                    AS lot_flags
    FROM admitted
    GROUP BY snapshot_id, account_id, holding_key
),

{{ holding_replay() }},

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
    quantity,
    quantity_derived,
    gross_amount,
    net_amount,
    currency,
    unit_price,
    n_investment_ids,
    investment_ids,
    {{ holding_data_quality_flags() }} AS data_quality_flags
FROM timeline
