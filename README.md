# Decade Data Platform Case Study

[![build](https://github.com/thiagorlopes/decade-data-platform-case-study/actions/workflows/build.yml/badge.svg)](https://github.com/thiagorlopes/decade-data-platform-case-study/actions/workflows/build.yml)

This repository contains Thiago Portugues's solution for the hiring process at Decade.

## Table of Contents

**[General information](#general-information)**<br>
**[Prerequisites](#prerequisites)**<br>
**[Installation](#installation)**<br>
**[Development cycle](#development-cycle)**<br>
**[Querying the warehouse](#querying-the-warehouse)**<br>
**[Browsing the data model](#browsing-the-data-model)**<br>
**[Consumers](#consumers)**<br>
**[Contracts](#contracts)**<br>
**[Data quality: detect, resolve, guarantee](#data-quality-detect-resolve-guarantee)**<br>
**[Architecture and operations](#architecture-and-operations)**<br>
**[Compliance](#compliance)**<br>
**[Deliberately left out](#deliberately-left-out)**<br>

## General Information

The visible deliverable is under [`consumers/wealth/`](consumers/wealth/): two SQL queries and their committed CSV output, answering what one customer holds and the movements behind it. Everything else in this repo exists to make that query cheap to write and safe to trust.

Two raw Open Finance Brasil feeds land in `data/`: **positions** (balance snapshots) and **transactions** (the movements behind them). dbt on DuckDB transforms both into a small consumption layer under an enforced output contract: `fct_holdings` and `fct_movements` for keys and measures, `dim_holding` for the descriptive attributes both facts join to. The wealth queries read only those three tables. A new consumer for a different question does the same, without touching raw or talking to the platform author.

For design rationale, see [Data quality: detect, resolve, guarantee](#data-quality-detect-resolve-guarantee) and [Architecture and operations](#architecture-and-operations) below.

## Prerequisites

- Docker Engine with Docker Compose v2
- `make` and `git`
- Python 3.11+ (only if you want to run notebooks or scoped `dbt` commands on the host)

## Installation

Build the docker image. This is all you need to run the pipeline end-to-end:

```bash
make install
```

The image ships Python, dbt, and the DuckDB CLI. The `make` targets drive the whole pipeline from inside the container.

### Optional: host-side Python environment

Set up a local venv if you want to:

- run the notebooks under `notebooks/` (they are dev-only and stay out of the image), or
- run scoped dbt commands on the host, for example `dbt build --select <model>+`.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
dbt deps                       # dbt_packages/ is gitignored; a fresh clone has none
```

`requirements.txt` pins the same `dbt` and `duckdb` versions the image uses, plus `notebook` and `pandas` for the notebooks. One venv covers both cases.

## Development cycle

Run `make install` once, then `make build`. Everything else works from the built warehouse.

| Command | What it does |
|---|---|
| `make build` | Run models + tests. The safe default. |
| `make docs` | Serve the docs catalog at http://localhost:8080. |
| `make consumers` | Regenerate the CSVs under `consumers/wealth/output/`. |
| `make ui` / `make shell` | Query the warehouse. Both need a built warehouse. See [Querying the warehouse](#querying-the-warehouse). |
| `make clean` | Wipe the warehouse and dbt artifacts. Use when state gets stuck. |

Run `make help` for the full list, including partial variants like `make run` (models only), `make test` (tests only), and `make deps` (install dbt packages; every compiling target runs it first).

`make build` is idempotent. Canonical models are incremental with an `ingested_at` watermark, so reruns only process rows at or past the newest arrival. Positions and holdings dedupe on `(snapshot_id, investment_id)`; transactions dedupe on `transaction_id`. To reprocess everything after a transform change, run `make clean && make build`. This equals `dbt build --full-refresh` on a fresh warehouse.

## Querying the warehouse

The typical loop: edit a model, rebuild, then check the numbers.

**`make build`** runs models + tests and writes `warehouse.duckdb`. Run it after every model edit, and before the first `make ui` or `make shell` on a fresh clone.

**`make ui`** opens the [DuckDB UI](https://duckdb.org/docs/stable/core_extensions/ui.html) at http://localhost:4213: a schema browser, a notebook-style SQL editor, and result grids. The warehouse opens read-only. Close it before running `make build`. DuckDB is single-writer, so an open connection blocks the build.

**`make shell`** opens the DuckDB CLI inside the container: a terminal alternative to `make ui`. Same rule: close it before a build. Type `.quit` or press Ctrl-D to leave.

## Browsing the data model

Every staging and intermediate model carries a description and per-column docs, sourced from the Open Finance Brasil investment API specs and referenced through shared `{% docs %}` blocks in [`models/canonical/_docs.md`](models/canonical/_docs.md).

Run `make docs` and open http://localhost:8080. The site lets you browse the DAG, jump between models, and read OFB spec fields, enum values, and defect handling rules per column. Docs render from `warehouse.duckdb`, so run `make build` first if it's missing.

<img width="1828" height="927" alt="image" src="https://github.com/user-attachments/assets/0fc52a71-f6ed-4aed-8fa7-2c66e25bcb2f" />

<img width="1898" height="972" alt="image" src="https://github.com/user-attachments/assets/d09a46c7-526f-417b-baf8-16c565e4b369" />

## Consumers

The wealth page lives in [`consumers/wealth/`](consumers/wealth/): two plain SQL queries over the consumption layer, never raw or staging.

- [`holdings.sql`](consumers/wealth/holdings.sql): what customers hold, valued at each account's latest sync per product family, with `data_quality_flags` on every row.
- [`movements.sql`](consumers/wealth/movements.sql): the movements behind those holdings, each joined to the current holding it belongs to on the shared `holding_key`.

Run them from `make ui`. Add `WHERE party_id = '<uuid>'` to scope to one customer. The committed output under [`output/`](consumers/wealth/output/) covers three sample customers. `make consumers` regenerates it from the committed queries, so the CSVs cannot drift from the SQL that claims to produce them. A new consumer follows the same pattern: query `fct_holdings` / `fct_movements`, whose columns, types and flag vocabulary are contract-enforced in [`contracts/_consumption.yml`](contracts/_consumption.yml).

## Contracts

Contracts are dbt `schema.yml` files. `dbt_project.yml` declares [`contracts/`](contracts/) as a model path, so dbt parses and enforces the files there like anything under `models/`.

- [`contracts/_consumption.yml`](contracts/_consumption.yml): the output contract for `fct_holdings` and `fct_movements`. Grain and enum tests run at error severity.
- [`models/canonical/_canonical.yml`](models/canonical/_canonical.yml): per-family canonical contracts, kept next to their models.
- [`models/staging/_staging_quality.yml`](models/staging/_staging_quality.yml): within-record quality rules. This is the DETECT tier, at warn severity.

### What `contract: enforced` guarantees

On every `dbt build`, dbt compares the compiled output of `fct_holdings` and `fct_movements` against the columns declared in `contracts/_consumption.yml`. It does this before writing the table. The build fails on any drift, so a broken table never reaches a consumer:

- a column is **renamed or dropped**
- a column's **type changes** (for example, an amount silently becomes `varchar`)
- a **new column appears** without being declared

What this means for consumers: the output of `make build` always matches the contract file. Teams can develop against the declared columns and types without talking to the platform team. A platform-side refactor cannot break a consumer silently. It either preserves the contract, or it must update the contract file in the same PR. That file change is the review signal.

## Data quality: detect, resolve, guarantee

Provider defects (§2.2 of the brief) split into two tiers. Within a record: a required field empty, a value in the wrong form, a legal value outside its enum, a cross-field contradiction. Across records: the same holding under two ids, holdings that freeze under a new id, a zero-then-nonzero valuation. The pipeline handles them in three layers so each layer has one job.

Two terms recur below. A **lot** is one delivered position row from a custodian sync (a row in `int_*_positions`). A **holding** aggregates lots by natural key (account + security), one row per account and security (rows in `int_*_holdings` and `fct_holdings`).

```
dbt build (every run)

raw parquet ─→ STAGING (views, 1:1 flatten) ─→ INTERMEDIATE (incremental) ─→ CANONICAL fct ─→ consumers/
                         DETECT                          RESOLVE                    GUARANTEE

  ┌────────────────────────────┐   ┌─────────────────────────┐   ┌──────────────────────────┐
  │ envelope (ours) → ERROR    │   │ no payload tests here   │   │ output contract → ERROR  │
  │   not_null snapshot_id     │   │ logic instead:          │   │   not_null natural key   │
  │   not_null investment_id   │   │   normalize forms       │   │   not_null reference_dt  │
  │   not_null ingested_at     │   │     (strip CNPJ tail,   │   │   grain uniqueness       │
  │   unique grain             │   │      map IPC-A → IPCA)  │   │   enums clean post-map   │
  │   build DIES: bug is ours  │   │ build data_quality_flags│   │   build DIES: our        │
  ├────────────────────────────┤   │     for what cannot be  │   │     resolution failed    │
  │ payload (theirs) → WARN    │   │     repaired            │   ├──────────────────────────┤
  │   not_null required        │   │   dedupe across records │   │ data_quality_flags → WARN│
  │   format regex             │   └─────────────────────────┘   │   count stays visible    │
  │   accepted_values          │                                 └──────────────────────────┘
  │   cross-field rules        │
  │   store_failures: true     │
  └────────────────────────────┘
              │
              ▼
   main_dbt_test__audit.*  ◀── provider defect ledger (row-level, queryable)
```

| Owner                        | Layer | Severity              | On failure                                  |
|------------------------------|-------|-----------------------|---------------------------------------------|
| Us (envelope: ids, grain)    | stg   | error                 | Build halts. Fix ingestion.                 |
| Provider (payload content)   | stg   | warn + store_failures | Build continues. Rows land in audit ledger. |
| Us (resolution logic)        | fct   | error                 | Build halts. `int_` transform is buggy.     |
| Provider (unrepairable rows) | fct   | warn via `data_quality_flags` | Row admitted with a flag. Consumer decides. |

How a consumer finds out which happened (§2.2's closing question):

- **Row-level**: `data_quality_flags` column on every fct and holdings row (e.g. `['purchase_date:missing', 'gross:zero_transient']`). Empty list means clean.
- **Row-level, per-lot verdict**: `admission` column on the intermediate `int_*_positions` tables. `admit` flows to the holdings views; `reject_duplicate`, `reject_zero_duplicate` and `quarantine` stay in the positions table for audit.
- **Row-level, dropped movement twins**: anti-join `int_*_transactions` to `fct_movements` on `transaction_id`; every missing row has a surviving copy flagged `transaction_id:reissued`. The `cross_id_dedup_semantics` unit test pins that rule.
- **Run-level**: `main_dbt_test__audit.*`, one row per warned row per test per run.
- **Contract-level**: `models/canonical/_canonical.yml`. The full admission enum and data_quality_flags vocabulary are single-sourced in [`_docs.md`](models/canonical/_docs.md) and rendered on every column that carries them via `make docs`.

The three stages live one folder each:

- **DETECT**, in `models/staging/`. Rules sit in `_staging_quality.yml`; warned rows land in the `main_dbt_test__audit.*` ledger. Every warn count is reproduced cell-by-cell in [`notebooks/02_within_record_defects.ipynb`](notebooks/02_within_record_defects.ipynb).
- **RESOLVE**, in `models/canonical/intermediate/`. The latest arrival wins when a record is re-delivered (`latest_lot_delivery`). Duplicates collapse across investment_ids (`resolve_duplicate_investments` for positions, `cross_id_movements` for movements). What cannot be repaired is admitted with a flag in `data_quality_flags`; what cannot be resolved at all is quarantined.
- **GUARANTEE**, in `models/consumption/`. `fct_holdings` and `fct_movements` union the five families into one conformed shape under enforced contracts, with grain tests at error severity. Consumers read those models and nothing below them.

The full reference lives in [`docs/data-quality-reference.md`](docs/data-quality-reference.md): the admission verdicts, the complete flag vocabulary, the quarantine runbook, which fields the platform recalculates versus quotes, and two audits of defects beyond the brief's list.

## Architecture and operations

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native. The shape below is what production could look like, and the case is designed so the work could be transferred if considered appropriate by the Decade Data Team.

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

It follows the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices). The doc scales workspace count to team size: two workspaces (dev/prod) for teams up to five engineers, three (dev/staging/prod) beyond that.

Git is the source of truth ("if it isn't in version control, it doesn't exist"), and CI/CD gates promotion between environments. The diagrams below are the doc's illustration of one such production deployment workflow at scale, included here for reference rather than as the shape this case commits to:

<img width="720" height="596" alt="bundles-branching-0b017c959921574bebad867191cd736b" src="https://github.com/user-attachments/assets/669a223a-aa0a-463a-882a-11d4abe01a05" />

This case study solution ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any computer with no account required; the same dbt models run against Databricks when promoted. The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace through a profile change. That way, we would be able to close one tradeoff this shortcut carries: SQL dialect drift between the two engines.

### Orchestration

All the orchestrator has to do is run two commands on timers:

- `dbt build`, every few minutes: matches the arrival cadence of the raw feeds. The job is watermarked and idempotent, so a repeated or overlapping run leaves the same result as a single run.
- `dbt source freshness`, on its own cadence: pages the on-call when a feed stalls. The thresholds live in `models/_sources.yml`: warn after one quiet hour, error after six, measured on `ingested_at`. Staleness never blocks the build, so consumers keep reading correct data that is merely old. On this static sample the command always reports stale; that is the signal working against week-old data, not a defect.

In the Databricks target this is a two-task Workflows job. Airflow, Dagster, or cron can do the same work, because each command is self-contained: ordering, retries, and state all live in dbt and the watermark. This keeps the scheduler free of pipeline logic, so swapping it is a profile-sized change.

### Two kinds of incremental

Incremental means two different things in this pipeline.

- **Loading raw**: picking up only the new arrival files. In production, Databricks Auto Loader watches the drop folder and appends what it hasn't seen before. Not implemented here: raw was handed to us as two static parquet files, so there are no "new arrivals". This is what the Databricks target above turns on.
- **Building canonical from raw**: reprocessing only the snapshots with arrivals at or past the newest one already built (watermark on `ingested_at`), merged by key so re-runs are idempotent. **This is what §3.2 of the brief asks for, and what this repo ships.**

### Materializations

Layer materializations follow dbt Labs' guidance: [staging as views](https://docs.getdbt.com/best-practices/how-we-structure/2-staging) and the general progression from the [materializations best practices](https://docs.getdbt.com/best-practices/materializations/1-guide-overview): *"Start with a view. When the view gets too long to query for end users, make it a table. When the table gets too long to build, build it incrementally."*

| Layer | Materialization | Why |
|-------|----------------|-----|
| staging | view | Cheap renames/casts read only by the next layer during builds; always fresh, no storage spent on models consumers never query. |
| intermediate (positions) | incremental | Each run reprocesses every snapshot that received an arrival at or past the watermark (`ingested_at`, the arrival time), whole, not row by row. Duplicate classification compares rows within one sync, so a late or re-delivered row must be re-judged with the siblings that already landed; `unique_key (snapshot_id, investment_id)` makes the re-touched rows an upsert, so repeated runs stay idempotent. When a lot is re-delivered with a changed value, the `latest_lot_delivery` macro keeps only the newest arrival of each lot before the join. Replay after a transform fix: `dbt build --full-refresh`. |
| intermediate (holdings) | view | Cross-sync flags need lag/lead over the whole natural-key timeline, which a view sees for free without re-materializing prior syncs. Fine at sample scale; each reader also recomputes the deduplicated movement stream (about twenty macro runs per build). When volume outgrows the views, persist that stream and the holdings as intermediate tables per the progression above. |
| consumption | table | Contract-enforced union of the five families. Read by every consumer and by ad-hoc queries. Stored as a table so the guarantee layer is built once per run, not recomputed on every query. |

### Physical layout

Locally the warehouse is one 62 MB DuckDB file, and at that size no layout tuning pays for itself. The decisions below are for the Databricks target, where the canonical layer absorbs millions of records a day and layout decides how much data each query reads.

The layout serves four query patterns:

| Pattern | Shape | Reader |
|---|---|---|
| Wealth page | one customer, latest snapshot | product, point lookup |
| Net worth over time | one customer, full history | product, timeline scan |
| Portfolio analytics | many customers, bounded dates | analysts and services |
| The build itself | whole snapshots at or past the watermark | the incremental job |

Three decisions serve them:

- **Cluster by customer, then time.** Both facts are Delta tables with [liquid clustering](https://docs.databricks.com/aws/en/tables/clustering): `(party_id, snapshot_created_at)` for holdings, `(party_id, transaction_date)` for movements. Every product query filters on one customer first, so file skipping cuts a point lookup to a handful of files no matter how many customers connect. We cluster instead of partitioning Hive-style because `party_id` has far too many values for a partition key: one folder per customer creates the small-file problem by design.
- **Compact toward ~128 MB files.** A build every few minutes writes small files all day. Auto compaction and optimized writes keep files near the 128 MB target, so the file count tracks data volume, not run count.
- **Let cost grow with customers, not with history.** Storage grows linearly with connected customers. A point query reads one cluster, so its cost stays flat as customers grow. Build compute follows the arrival rate, because the watermark reprocesses only snapshots with new arrivals. At ten times the customers: ten times the storage, the same wealth-page latency, and builds still sized by arrivals per window.

## Compliance

The sample is synthetic, so the repo can commit query outputs (`consumers/wealth/output/`); production outputs never land in git. In production every field is personal financial data under LGPD, Brazil's data protection law, and five boundaries would apply:

- **The layer boundary is the access boundary.** Raw and staging hold provider payloads verbatim and stay locked to the pipeline's service principal. Consumers get Unity Catalog grants on the consumption schema only. The rule "consumers read consumption, never raw" stops being a convention and becomes an ACL.
- **Consumption is pseudonymous.** `party_id`, `account_id`, and `investment_id` are opaque UUIDs end to end. The consumption layer carries product attributes (fund names, issuer CNPJs, tickers) and no customer names or personal documents. Re-identification requires the customer registry, which lives outside this platform.
- **Erasure is a clustered delete, then a purge.** LGPD gives customers the right to have their data deleted on request. The facts cluster on `party_id`, so step one is a targeted `DELETE` that touches only that customer's files; the same key that serves the wealth page serves erasure. A `DELETE` alone is not erasure: the rows survive in raw, in staging, and in Delta time travel. Full erasure also purges the raw and staging copies, runs `VACUUM` past the retention window so old table versions forget the rows, and lets backups expire on a stated schedule.
- **Consent bounds what the pipeline may hold.** Open Finance consent has a scope and an expiry. When a customer revokes it, ingestion stops for that connection and the erasure path runs. Raw is kept only as long as reprocessing needs it, then purged on a stated retention window. Data serves the consented purpose only; a new use, such as model training, needs a new legal basis.
- **Access is logged; data stays encrypted and in Brazil.** Unity Catalog audit logs record every read of the consumption schema. Encryption in transit and at rest is the platform default. Data stays in a Brazilian region, where the customers and their Open Finance consent live.

These five boundaries are the platform's technical measures. The organizational side of LGPD (a data protection officer, records of processing, incident response) lives outside this repo.

## Deliberately left out

The brief asks what was left out and why. Two entries.

### A test on the watermark boundary

The `>=` in `snapshot_watermark` is load-bearing. One arrival batch shares one `ingested_at` stamp, so a run that read a batch mid-landing must re-read that batch whole on the next run. No automated test pins this. dbt unit tests run with `is_incremental` off, so no fixture can reach the comparison. A mutation pass confirmed the gap: flipping `>=` to `>` passes every test in the project, while nineteen other rule mutations fail their unit test.

The verification is manual instead: build twice over the same raw files and the warehouse is byte-identical. The closing check would be a two-run CI job that builds, lands a late row carrying the boundary stamp, rebuilds, and asserts the row arrived. At this repo's scale the manual check earns its keep; that CI job is the first test to add when the loader goes live.

### Three descriptive-field defects

An audit over the descriptive attributes of `dim_holding` ([details](docs/data-quality-reference.md#beyond-the-listed-defects)) found three defects there. The platform ships all three exactly as the provider sent them. Each one is real and measured below. None of them moves a number: no balance, quantity or movement total reads these fields, so the wealth math is unaffected.

Each would need a detection rule and a repair, and both are cheap. They lost the time to work that touches the numbers a consumer acts on. The recipes are written out so the next person can pick them up.

**A placeholder value in `post_fixed_indexer_percentage`.** 1,569 admitted lot rows carry `-0.000016`. A percentage of an indexer cannot be negative. That value is the only negative one in the feed and it repeats to the last digit, so it is a placeholder rather than a rounding artifact. Every other bank and credit row carries `1.000000` or `1.020000`. It reaches 114 of the 5,296 rows in `dim_holding`. The recipe: warn on `post_fixed_indexer_percentage < 0` in `_staging_quality.yml`, then null the value and flag the row, the same shape `clean_missing_date` already uses for `0001-01-01`.

**Lots of one holding disagree on `indexer`.** 202 of the 5,296 rows in `dim_holding` draw from lots that name more than one indexer. `CDI` against `IPCA` on the same security is the most common pair, 100 times. `dim_holding` resolves the disagreement with `arg_max(indexer, snapshot_created_at)`, so the lot written last wins and the consumer never learns the lots disagreed. The recipe: raise an `indexer:unstable` flag on the holding, and settle the value by majority vote instead of by write order.

**Treasury indexers contradict their own product name.** A Tesouro Direto title names its indexer in its title. `Tesouro Selic 2031` ships `indexer = OUTROS`. `Tesouro IPCA+ 2029` and `Tesouro Renda+ 2044` do the same. That is 3 of the 8 treasury rows in `dim_holding`. The provider stamps `OUTROS` on a minority of the lots of every treasury title, and `arg_max` sometimes lands on one of them. 375 lot rows carry an indexer their own product name rules out. The recipe: read the indexer off the product name for Tesouro Direto, where the name is authoritative, and warn when the payload disagrees.
