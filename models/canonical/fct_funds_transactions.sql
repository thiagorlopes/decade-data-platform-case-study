-- One row per transaction (snapshot_id, payload_source, investment_id, transaction_id).
-- Pass-through of staging: materializes the view as the consumable table.
SELECT * FROM {{ ref('stg_openfinance__funds_transactions') }}
