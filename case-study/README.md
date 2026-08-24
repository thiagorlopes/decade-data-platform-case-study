# Data Platform Case Study

## Start here

Read `Data Platform Case Study.pdf` first. It is the full brief — context, inputs, deliverables, constraints, evaluation criteria, submission instructions.

## Files

| file | purpose |
|---|---|
| `Data Platform Case Study.pdf` | The case brief. Read this first. |
| `raw_positions.parquet` | Investment position payloads, as the institutions delivered them. |
| `raw_transactions.parquet` | Investment transaction payloads for the same holdings. |

## What is in the data

Both files carry the same delivery metadata, one row per record as delivered:

| column | meaning |
|---|---|
| `institution_id`, `institution_name` | the institution holding the data |
| `party_id` | the customer |
| `account_id` | the account the holding sits in |
| `connection_id` | one customer's link to one institution |
| `snapshot_id` | one sync of one connection |
| `snapshot_created_at` | when that sync started |
| `investment_id` | the institution's key for the holding |
| `investment_type` | `BANK_FIXED_INCOMES`, `CREDIT_FIXED_INCOMES`, `FUNDS`, `TREASURE_TITLES`, `VARIABLE_INCOMES` |
| `s3_uri` | the object the payload landed as |
| `ingested_at` | when it reached us |

`raw_positions.parquet` adds:

| column | meaning |
|---|---|
| `payload_kind` | `detail` (what the instrument is) or `balances` (what it is worth) |
| `payload_json` | the institution's payload, verbatim |

`raw_transactions.parquet` adds:

| column | meaning |
|---|---|
| `payload_source` | `transactions` or `transactions-current`. The API exposes movements through two endpoints; this records which one delivered the row |
| `page` | the page of that endpoint's paginated response |
| `query_window` | the date range the page reported having been asked for |
| `transaction_json` | one movement object, verbatim |

Every payload column holds the institution's JSON as it arrived, shaped `{"data": …, "meta": …, "links": …}`. The fields inside `data` are those of the Open Finance Brasil Investments API. The specification is public and reading it is part of the work.

All data is synthetic. No real customer appears in these files.

## Submission

See §6 of the PDF ("Submission instructions"). In short: a GitHub repository, `contracts/`, `consumers/`, a `README.md` covering how to run it end-to-end and what you deliberately left out, and a short video walkthrough.

If anything is unclear, please contact us.
