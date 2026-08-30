-- Static contract of each holding across families. Grain: one row per
-- (product_family, holding_key). Attributes are latest observed values across
-- admitted lots; no SCD, later provider corrections overwrite earlier ones.
-- Join fct_holdings on (product_family, holding_key).

WITH bank AS (
    SELECT
        'bank_fixed_incomes'                                   AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        max_by(investment_type, snapshot_created_at)          AS holding_name,
        max_by(isin_code, snapshot_created_at)                AS isin_code,
        max_by(issuer_cnpj, snapshot_created_at)              AS issuer_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_name,
        CAST(NULL AS STRING)                                  AS fund_cnpj,
        CAST(NULL AS STRING)                                  AS ticker,
        max_by(investment_type, snapshot_created_at)          AS investment_type,
        max_by(indexer, snapshot_created_at)                  AS indexer,
        max_by(pre_fixed_rate, snapshot_created_at)           AS pre_fixed_rate,
        max_by(post_fixed_indexer_percentage, snapshot_created_at) AS post_fixed_indexer_percentage,
        max_by(issue_date, snapshot_created_at)               AS issue_date,
        max_by(due_date, snapshot_created_at)                 AS due_date,
        max_by(purchase_date, snapshot_created_at)            AS purchase_date
    FROM {{ ref('int_bank_fixed_incomes_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
),

credit AS (
    SELECT
        'credit_fixed_incomes'                                 AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        max_by(coalesce(debtor_name, investment_type), snapshot_created_at) AS holding_name,
        max_by(isin_code, snapshot_created_at)                AS isin_code,
        max_by(issuer_cnpj, snapshot_created_at)              AS issuer_cnpj,
        max_by(debtor_cnpj, snapshot_created_at)              AS debtor_cnpj,
        max_by(debtor_name, snapshot_created_at)              AS debtor_name,
        CAST(NULL AS STRING)                                  AS fund_cnpj,
        CAST(NULL AS STRING)                                  AS ticker,
        max_by(investment_type, snapshot_created_at)          AS investment_type,
        max_by(indexer, snapshot_created_at)                  AS indexer,
        max_by(pre_fixed_rate, snapshot_created_at)           AS pre_fixed_rate,
        max_by(post_fixed_indexer_percentage, snapshot_created_at) AS post_fixed_indexer_percentage,
        max_by(issue_date, snapshot_created_at)               AS issue_date,
        max_by(due_date, snapshot_created_at)                 AS due_date,
        max_by(purchase_date, snapshot_created_at)            AS purchase_date
    FROM {{ ref('int_credit_fixed_incomes_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
),

funds AS (
    SELECT
        'funds'                                                AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        max_by(fund_name, snapshot_created_at)                AS holding_name,
        max_by(isin_code, snapshot_created_at)                AS isin_code,
        CAST(NULL AS STRING)                                  AS issuer_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_name,
        max_by(fund_cnpj, snapshot_created_at)                AS fund_cnpj,
        CAST(NULL AS STRING)                                  AS ticker,
        CAST(NULL AS STRING)                                  AS investment_type,
        CAST(NULL AS STRING)                                  AS indexer,
        CAST(NULL AS DECIMAL(12,6))                            AS pre_fixed_rate,
        CAST(NULL AS DECIMAL(12,6))                            AS post_fixed_indexer_percentage,
        CAST(NULL AS DATE)                                     AS issue_date,
        CAST(NULL AS DATE)                                     AS due_date,
        CAST(NULL AS DATE)                                     AS purchase_date
    FROM {{ ref('int_funds_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
),

treasure AS (
    SELECT
        'treasure_titles'                                      AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        max_by(product_name, snapshot_created_at)             AS holding_name,
        max_by(isin_code, snapshot_created_at)                AS isin_code,
        CAST(NULL AS STRING)                                  AS issuer_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_name,
        CAST(NULL AS STRING)                                  AS fund_cnpj,
        CAST(NULL AS STRING)                                  AS ticker,
        CAST(NULL AS STRING)                                  AS investment_type,
        max_by(indexer, snapshot_created_at)                  AS indexer,
        max_by(pre_fixed_rate, snapshot_created_at)           AS pre_fixed_rate,
        max_by(post_fixed_indexer_percentage, snapshot_created_at) AS post_fixed_indexer_percentage,
        CAST(NULL AS DATE)                                     AS issue_date,
        max_by(due_date, snapshot_created_at)                 AS due_date,
        max_by(purchase_date, snapshot_created_at)            AS purchase_date
    FROM {{ ref('int_treasure_titles_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
),

variable AS (
    SELECT
        'variable_incomes'                                     AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        max_by(ticker, snapshot_created_at)                   AS holding_name,
        max_by(isin_code, snapshot_created_at)                AS isin_code,
        max_by(issuer_cnpj, snapshot_created_at)              AS issuer_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_cnpj,
        CAST(NULL AS STRING)                                  AS debtor_name,
        CAST(NULL AS STRING)                                  AS fund_cnpj,
        max_by(ticker, snapshot_created_at)                   AS ticker,
        CAST(NULL AS STRING)                                  AS investment_type,
        CAST(NULL AS STRING)                                  AS indexer,
        CAST(NULL AS DECIMAL(12,6))                            AS pre_fixed_rate,
        CAST(NULL AS DECIMAL(12,6))                            AS post_fixed_indexer_percentage,
        CAST(NULL AS DATE)                                     AS issue_date,
        CAST(NULL AS DATE)                                     AS due_date,
        CAST(NULL AS DATE)                                     AS purchase_date
    FROM {{ ref('int_variable_incomes_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
)

SELECT * FROM bank
UNION ALL SELECT * FROM credit
UNION ALL SELECT * FROM funds
UNION ALL SELECT * FROM treasure
UNION ALL SELECT * FROM variable
