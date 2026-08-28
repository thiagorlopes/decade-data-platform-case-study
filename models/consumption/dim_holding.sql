-- Static contract of each holding across families. Grain: one row per
-- (product_family, holding_key). Attributes are latest observed values across
-- admitted lots; no SCD, later provider corrections overwrite earlier ones.
-- Join fct_holdings on (product_family, holding_key).

WITH bank AS (
    SELECT
        'bank_fixed_incomes'                                   AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        arg_max(investment_type, snapshot_created_at)          AS holding_name,
        arg_max(isin_code, snapshot_created_at)                AS isin_code,
        arg_max(issuer_cnpj, snapshot_created_at)              AS issuer_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_name,
        CAST(NULL AS VARCHAR)                                  AS fund_cnpj,
        CAST(NULL AS VARCHAR)                                  AS ticker,
        arg_max(investment_type, snapshot_created_at)          AS investment_type,
        arg_max(indexer, snapshot_created_at)                  AS indexer,
        arg_max(pre_fixed_rate, snapshot_created_at)           AS pre_fixed_rate,
        arg_max(post_fixed_indexer_percentage, snapshot_created_at) AS post_fixed_indexer_percentage,
        arg_max(issue_date, snapshot_created_at)               AS issue_date,
        arg_max(due_date, snapshot_created_at)                 AS due_date,
        arg_max(purchase_date, snapshot_created_at)            AS purchase_date
    FROM {{ ref('int_bank_fixed_incomes_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
),

credit AS (
    SELECT
        'credit_fixed_incomes'                                 AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        arg_max(coalesce(debtor_name, investment_type), snapshot_created_at) AS holding_name,
        arg_max(isin_code, snapshot_created_at)                AS isin_code,
        arg_max(issuer_cnpj, snapshot_created_at)              AS issuer_cnpj,
        arg_max(debtor_cnpj, snapshot_created_at)              AS debtor_cnpj,
        arg_max(debtor_name, snapshot_created_at)              AS debtor_name,
        CAST(NULL AS VARCHAR)                                  AS fund_cnpj,
        CAST(NULL AS VARCHAR)                                  AS ticker,
        arg_max(investment_type, snapshot_created_at)          AS investment_type,
        arg_max(indexer, snapshot_created_at)                  AS indexer,
        arg_max(pre_fixed_rate, snapshot_created_at)           AS pre_fixed_rate,
        arg_max(post_fixed_indexer_percentage, snapshot_created_at) AS post_fixed_indexer_percentage,
        arg_max(issue_date, snapshot_created_at)               AS issue_date,
        arg_max(due_date, snapshot_created_at)                 AS due_date,
        arg_max(purchase_date, snapshot_created_at)            AS purchase_date
    FROM {{ ref('int_credit_fixed_incomes_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
),

funds AS (
    SELECT
        'funds'                                                AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        arg_max(fund_name, snapshot_created_at)                AS holding_name,
        arg_max(isin_code, snapshot_created_at)                AS isin_code,
        CAST(NULL AS VARCHAR)                                  AS issuer_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_name,
        arg_max(fund_cnpj, snapshot_created_at)                AS fund_cnpj,
        CAST(NULL AS VARCHAR)                                  AS ticker,
        CAST(NULL AS VARCHAR)                                  AS investment_type,
        CAST(NULL AS VARCHAR)                                  AS indexer,
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
        arg_max(product_name, snapshot_created_at)             AS holding_name,
        arg_max(isin_code, snapshot_created_at)                AS isin_code,
        CAST(NULL AS VARCHAR)                                  AS issuer_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_name,
        CAST(NULL AS VARCHAR)                                  AS fund_cnpj,
        CAST(NULL AS VARCHAR)                                  AS ticker,
        CAST(NULL AS VARCHAR)                                  AS investment_type,
        arg_max(indexer, snapshot_created_at)                  AS indexer,
        arg_max(pre_fixed_rate, snapshot_created_at)           AS pre_fixed_rate,
        arg_max(post_fixed_indexer_percentage, snapshot_created_at) AS post_fixed_indexer_percentage,
        CAST(NULL AS DATE)                                     AS issue_date,
        arg_max(due_date, snapshot_created_at)                 AS due_date,
        arg_max(purchase_date, snapshot_created_at)            AS purchase_date
    FROM {{ ref('int_treasure_titles_positions') }}
    WHERE admission = 'admit'
    GROUP BY 1, 2
),

variable AS (
    SELECT
        'variable_incomes'                                     AS product_family,
        coalesce(natural_key, investment_id)                   AS holding_key,
        arg_max(ticker, snapshot_created_at)                   AS holding_name,
        arg_max(isin_code, snapshot_created_at)                AS isin_code,
        arg_max(issuer_cnpj, snapshot_created_at)              AS issuer_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_cnpj,
        CAST(NULL AS VARCHAR)                                  AS debtor_name,
        CAST(NULL AS VARCHAR)                                  AS fund_cnpj,
        arg_max(ticker, snapshot_created_at)                   AS ticker,
        CAST(NULL AS VARCHAR)                                  AS investment_type,
        CAST(NULL AS VARCHAR)                                  AS indexer,
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
