-- One row per ticker, mapped to the single well-formed ISIN observed for it
-- across the whole detail feed. Tickers that quote conflicting well-formed
-- ISINs are dropped by the HAVING guard, so imputation in
-- int_variable_incomes_positions never picks between them silently.
-- ponytail: view — small lookup rebuilt from the staging detail; promote to
-- a table if the scan cost ever matters.
{{ config(materialized='view') }}

WITH observations AS (
    SELECT
        ticker,
        isin_code,
        snapshot_created_at
    FROM {{ ref('stg_openfinance__variable_incomes_positions_detail') }}
    WHERE ticker IS NOT NULL AND ticker <> ''
      AND {{ decade.regex_matches('isin_code', '^BR[A-Z0-9]{9}[0-9]$') }}
)

SELECT
    ticker,
    max(isin_code) AS isin_code,
    count(*) AS observation_count,
    min(snapshot_created_at) AS first_seen_at,
    max(snapshot_created_at) AS last_seen_at
FROM observations
GROUP BY ticker
HAVING count(DISTINCT isin_code) = 1
