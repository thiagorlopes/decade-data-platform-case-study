-- Net worth over time, proxied by cumulative net flows: what the customer
-- put in minus what came out, month by month, across every product family.
-- Movements on lots no longer held count too, so the series covers the whole
-- history, not just the current portfolio. Historical market values are not
-- available from the providers; the holdings consumer carries the current
-- valuation that marks the end of the curve to market.
WITH monthly AS (
    SELECT
        mov.party_id,
        date_trunc('month', mov.transaction_date)::DATE AS month_date,
        sum(
            CASE WHEN mov.movement_type = 'ENTRADA'
                THEN coalesce(mov.net_amount, mov.gross_amount)
                ELSE -coalesce(mov.net_amount, mov.gross_amount)
            END
        ) AS net_flow
    FROM decade.consumption.fct_movements AS mov
    WHERE mov.transaction_date IS NOT NULL
    GROUP BY mov.party_id, date_trunc('month', mov.transaction_date)
)

SELECT
    party_id,
    month_date,
    round(net_flow::DOUBLE, 2) AS net_flow,
    round(sum(net_flow) OVER (
        PARTITION BY party_id
        ORDER BY month_date
    )::DOUBLE, 2) AS cumulative_net_flow
FROM monthly
ORDER BY party_id, month_date;
