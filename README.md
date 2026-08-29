# Decade Data Platform Case Study

[![build](https://github.com/thiagorlopes/decade-data-platform-case-study/actions/workflows/build.yml/badge.svg)](https://github.com/thiagorlopes/decade-data-platform-case-study/actions/workflows/build.yml)

This repository contains Thiago Portugues's solution for the hiring process at Decade.

## Table of Contents

**[General information](#general-information)**<br>
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

## Installation

You need Docker Engine with Docker Compose v2, `make`, and `git`. Build the docker image; this is all you need to run the pipeline end-to-end:

```bash
make install
```

The image ships Python, dbt, and the DuckDB CLI. The `make` targets drive the whole pipeline from inside the container.

Optional: to run the notebooks under `notebooks/` or scoped dbt commands on the host (for example `dbt build --select <model>+`), set up a venv with Python 3.11+:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt && dbt deps
```

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

`make build` is idempotent. Canonical models are incremental with an `ingested_at` watermark, so reruns only process rows at or past the newest arrival. Positions and holdings dedupe on `(snapshot_id, investment_id)`; transactions dedupe on `transaction_id`. To reprocess everything after a transform change, run `make clean && make build`. This equals `dbt build --full-refresh` on a fresh warehouse. To reprocess a bounded window instead, pass `--vars '{"backfill_from": "2024-01-01"}'`: every watermark reopens to that point, the affected snapshots are re-judged, and the upserts absorb the re-touched rows, so no full refresh is needed.

## Querying the warehouse

The loop: edit a model, `make build`, check the numbers.

**`make build`** runs models + tests and writes `warehouse.duckdb`. Run it after every model edit, and first on a fresh clone.

**`make ui`** opens the [DuckDB UI](https://duckdb.org/docs/stable/core_extensions/ui.html) at http://localhost:4213: a schema browser, a notebook-style SQL editor, and result grids, all read-only. **`make shell`** opens the DuckDB CLI inside the container (`.quit` to leave). Close either before a build: DuckDB is single-writer, so an open connection blocks it.

## Browsing the data model

Run `make docs` and open http://localhost:8080 to browse the DAG and read per-column docs: Open Finance Brasil spec fields, enum values, and defect handling rules. They are sourced from the OFB investment API specs through shared `{% docs %}` blocks in [`models/canonical/_docs.md`](models/canonical/_docs.md). Docs render from `warehouse.duckdb`, so run `make build` first if it's missing.

<img width="1828" height="927" alt="image" src="https://github.com/user-attachments/assets/0fc52a71-f6ed-4aed-8fa7-2c66e25bcb2f" />

## Consumers

The wealth page lives in [`consumers/wealth/`](consumers/wealth/): two plain SQL queries over the consumption layer, never raw or staging.

- [`holdings.sql`](consumers/wealth/holdings.sql): what customers hold, valued at each account's latest sync per product family, with `data_quality_flags` on every row.
- [`movements.sql`](consumers/wealth/movements.sql): the movements behind those holdings, joined to their current holding on the shared `holding_key`.

Run them from `make ui`. Add `WHERE party_id = '<uuid>'` to scope to one customer. `make consumers` regenerates the committed CSVs under [`output/`](consumers/wealth/output/) (three sample customers) from these same queries, so the output cannot drift from its SQL. A new consumer follows the same pattern: query `fct_holdings` and `fct_movements` under the contract.

## Contracts

Contracts are dbt `schema.yml` files. `dbt_project.yml` declares [`contracts/`](contracts/) as a model path, so dbt enforces them like anything under `models/`.

- [`contracts/_consumption.yml`](contracts/_consumption.yml): the output contract for `fct_holdings` and `fct_movements`. Grain and enum tests run at error severity.
- [`models/canonical/_canonical.yml`](models/canonical/_canonical.yml): per-family canonical contracts, kept next to their models.
- [`models/staging/_staging_quality.yml`](models/staging/_staging_quality.yml): within-record quality rules. This is the DETECT tier, at warn severity.

On every `dbt build`, dbt compares the compiled output of both facts against the declared columns before writing the table. Any drift fails the build: a renamed or dropped column, a changed type, an undeclared new column. The output of `make build` therefore always matches the contract file, and consumers develop against the declared columns and types without talking to the platform team. A refactor either preserves the contract or updates the file in the same PR; that file change is the review signal.

Schema changes ship as versioned, replayable steps: a model change gated by its contract change in the same PR, replayed over history with `make clean && make build`.

## Data quality: detect, resolve, guarantee

Provider defects (§2.2 of the brief) split into two tiers: within a record and across records. Three layers handle them, one job each: staging detects, intermediate resolves, consumption guarantees.

Two terms recur. A **lot** is one delivered position row from a custodian sync (a row in `int_*_positions`). A **holding** aggregates lots by natural key (account + security), one row per account and security (rows in `int_*_holdings` and `fct_holdings`).

The three stages run inside every `dbt build`, one layer each: raw parquet → staging (detect) → intermediate (resolve) → fct (guarantee) → consumers. Ownership decides severity:

| Owner                        | Layer | Severity              | On failure                                  |
|------------------------------|-------|-----------------------|---------------------------------------------|
| Us (envelope: ids, grain)    | stg   | error                 | Build halts. Fix ingestion.                 |
| Provider (payload content)   | stg   | warn + store_failures | Build continues. Rows land in audit ledger. |
| Us (resolution logic)        | fct   | error                 | Build halts. `int_` transform is buggy.     |
| Provider (unrepairable rows) | fct   | warn via `data_quality_flags` | Row admitted with a flag. Consumer decides. |

How a consumer finds out which happened (§2.2's closing question):

- **Row-level**: `data_quality_flags` on every fct and holdings row (e.g. `['purchase_date:missing', 'gross:zero_transient']`). Empty list means clean.
- **Per-lot verdict**: the `admission` column on `int_*_positions`. `admit` flows to the holdings views; `reject_duplicate`, `reject_zero_duplicate` and `quarantine` stay in the positions table for audit.
- **Dropped movement twins**: anti-join `int_*_transactions` to `fct_movements` on `transaction_id`; every missing row has a surviving copy flagged `transaction_id:reissued`.
- **Run-level**: `main_dbt_test__audit.*`, one row per warned row per test per run.
- **Contract-level**: `models/canonical/_canonical.yml`. The admission enum and flag vocabulary are single-sourced in [`_docs.md`](models/canonical/_docs.md) and render on every column via `make docs`.

The full reference lives in [`docs/data-quality-reference.md`](docs/data-quality-reference.md): the three stages folder by folder with the full stage diagram, the admission verdicts, the complete flag vocabulary, the quarantine runbook, which fields the platform recalculates versus quotes, and two audits of defects beyond the brief's list.

## Architecture and operations

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native, following the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices): git is the source of truth, and CI/CD gates promotion between environments. The shape below is what production could look like, and the case is designed so the work could be transferred if considered appropriate by the Decade Data Team.

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

This case study solution ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any computer with no account required. The same models build on Databricks with `--target prod`. Where the two engines disagree on SQL spelling, a small set of `adapter.dispatch` macros carries the difference, so the model files stay engine-neutral.

The two targets lay out schemas differently, on purpose:

- **Prod fans out by layer.** On Databricks each layer lands in its own schema: `decade_staging`, `decade_canonical`, `decade_consumption`, plus `decade_dbt_test__audit` for stored test failures. That makes the layer boundary from the [Compliance](#compliance) section a grant target: consumers get `decade_consumption` and nothing else.
- **Dev stays flat.** The local warehouse is one DuckDB file per developer, so schema fan-out buys no isolation there and the consumer queries keep their bare table names.

The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace through a profile change. In that shared workspace, Asset Bundles deploy each engineer's job under their own prefix and the dev profile writes to a per-user schema, so concurrent runs from different branches cannot overwrite each other. `generate_schema_name` in [`macros/schemas.sql`](macros/schemas.sql) is the seam where that per-user prefix goes; it is documented there and deliberately not built, because the single current workspace is prod only.

#### Running against prod

Set three environment variables (`DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DATABRICKS_TOKEN`), then pass the target:

```bash
dbt build --target prod --exclude-resource-type unit_test
```

Unit tests are excluded on Databricks because their yml fixtures carry DuckDB array literals; porting the fixtures to SQL format is the known follow-up. Everything else, including contracts, data tests, and the incremental merges, runs on both engines.

### Two kinds of incremental

Incremental means two different things in this pipeline.

- **Loading raw**: picking up only new arrival files. In production, Databricks Auto Loader watches the drop folder and appends what it hasn't seen. Not implemented here: raw arrived as two static parquet files, so there are no new arrivals.
- **Building canonical from raw**: reprocessing only the snapshots with arrivals at or past the newest one already built (watermark on `ingested_at`), merged by key so re-runs are idempotent. **This is what §3.2 of the brief asks for, and what this repo ships.**

### Orchestration

All the orchestrator has to do is run two commands on timers:

- `dbt build`, every few minutes: matches the arrival cadence of the raw feeds. The job is watermarked and idempotent, so a repeated or overlapping run leaves the same result as a single run.
- `dbt source freshness`, on its own cadence: detects a stalled feed, the signal an alert would page on in production. Thresholds live in `models/_sources.yml`: warn after one quiet hour, error after six, on `ingested_at`. Staleness never blocks the build, so consumers keep reading correct data that is merely old. On this static sample the command always reports stale; that is the signal working, not a defect.

In the Databricks target this is a two-task Workflows job. Airflow, Dagster, or cron can do the same work, because ordering, retries, and state live in dbt and the watermark. The scheduler stays free of pipeline logic, so swapping it is a profile-sized change.

### Materializations

Materializations follow dbt Labs' guidance, [staging as views](https://docs.getdbt.com/best-practices/how-we-structure/2-staging) and the [progression](https://docs.getdbt.com/best-practices/materializations/1-guide-overview): *"Start with a view. When the view gets too long to query for end users, make it a table. When the table gets too long to build, build it incrementally."*

| Layer | Materialization | Why |
|-------|----------------|-----|
| staging | view | Cheap renames and casts, read only during builds: always fresh, no storage spent on models consumers never query. |
| intermediate (positions) | incremental | Reprocesses whole snapshots at or past the watermark: duplicate classification compares rows within one sync, so a late or re-delivered row is re-judged with the siblings that already landed. The `(snapshot_id, investment_id)` key makes re-touched rows an upsert, so reruns stay idempotent. |
| intermediate (transactions) | incremental | Same watermark, upserting on `transaction_id`: a re-delivered movement replaces its earlier copy, and the latest arrival wins. |
| intermediate (holdings) | view | Cross-sync flags need lag/lead over the whole natural-key timeline, which a view sees for free. Fine at sample scale, though each reader recomputes the deduplicated movement stream (about twenty macro runs per build); when volume outgrows this, persist the stream and the holdings as tables per the progression above. |
| consumption | table | Contract-enforced union of the five families, read by every consumer and ad-hoc query. Built once per run, not recomputed per query. |

### Physical layout

Locally the warehouse is one 62 MB DuckDB file; no layout tuning pays for itself at that size. These decisions are for the Databricks target, where the canonical layer absorbs millions of records a day and layout decides how much data each query reads.

The layout serves four query patterns:

| Pattern | Shape | Reader |
|---|---|---|
| Wealth page | one customer, latest snapshot | product, point lookup |
| Net worth over time | one customer, full history | product, timeline scan |
| Portfolio analytics | many customers, bounded dates | analysts and services |
| The build itself | whole snapshots at or past the watermark | the incremental job |

Three decisions serve them:

- **Cluster by customer, then time.** Both facts are Delta tables with [liquid clustering](https://docs.databricks.com/aws/en/tables/clustering): `(party_id, snapshot_created_at)` for holdings, `(party_id, transaction_date)` for movements. Every product query filters on one customer first, so file skipping cuts a point lookup to a handful of files. Hive-style partitioning on `party_id` would create the small-file problem by design: one folder per customer. The clustering keys live in `dbt_project.yml` (`liquid_clustered_by`); the DuckDB adapter ignores them.
- **Compact toward ~128 MB files.** A build every few minutes writes small files all day. Auto compaction and optimized writes keep files near target, so the file count tracks data volume, not run count.
- **Let cost grow with customers, not history.** Storage grows linearly with customers, a point query reads one cluster, and build compute follows the arrival rate. At ten times the customers: ten times the storage, the same wealth-page latency, builds still sized by arrivals per window.

## Compliance

The sample is synthetic, so the repo can commit query outputs (`consumers/wealth/output/`); production outputs never land in git. In production every field is personal financial data under LGPD, Brazil's data protection law, and five boundaries would apply:

- **The layer boundary is the access boundary.** Raw and staging stay locked to the pipeline's service principal; consumers get grants on the consumption schema only. "Never read raw" is an ACL, not a convention.
- **Consumption is pseudonymous.** The ids are opaque UUIDs, and the layer carries no names or personal documents. Re-identification needs the customer registry, which lives outside this platform.
- **Erasure is a clustered delete, then a purge.** The facts cluster on `party_id`, so one targeted `DELETE` uses the same key that serves the wealth page. The purge then covers raw, staging, Delta time travel, and expiring backups.
- **Consent bounds what the pipeline holds.** Consent has a scope and an expiry; revocation stops ingestion and triggers erasure. Raw is purged once reprocessing no longer needs it. A new use, such as model training, needs a new legal basis.
- **Access is logged; data stays encrypted and in Brazil.** Audit logs record every read of the consumption schema. Encryption is the default. Storage stays in a Brazilian region.

These five boundaries are the platform's technical measures. The organizational side of LGPD (a data protection officer, records of processing, incident response) lives outside this repo.

## Deliberately left out

The brief asks what was left out and why. Three entries.

### A test on the watermark boundary

Each incremental run processes only new rows: rows whose `ingested_at` is at or after the last stamp already processed. That "at or after" is the `>=` in `snapshot_watermark`, and it guards against a specific failure. All rows of one arrival batch share one `ingested_at` value. If a run starts while a batch is still landing, it sees only part of that batch. With `>=`, the next run takes the whole batch again and the late rows arrive. With `>`, the next run would skip the batch and silently drop them.

No automated test covers this line. dbt unit tests run with `is_incremental` off, so they never execute the filter. A mutation pass confirmed the blind spot: change `>=` to `>` and every test in the project still passes, while nineteen other rule mutations each fail a unit test.

Today the check is manual: build twice over the same raw files and confirm the warehouse is byte-identical. The missing test is a two-run CI job: build, add a late row stamped with the boundary `ingested_at`, rebuild, assert the row arrived. It is the first test to add when the loader goes live.

### A Claude skill for the quality vocabulary

The [data quality reference](docs/data-quality-reference.md) is nearly an agent skill already. Point Claude at the doc, add the triage queries, and an analyst gets fast answers: what a flag means, why a replay went negative, whether to trust a field, how to work a quarantined lot up to escalation. It is left out because a skill distills a workflow that has already repeated and stabilized. Good answers also need the business domain: how each institution reports in practice, which defects matter to which consumers, and how escalation with an institution works. Both come from operating the platform, so the operating comes first and the skill after.

### Three descriptive-field defects

An audit over the descriptive attributes of `dim_holding` ([details](docs/data-quality-reference.md#beyond-the-listed-defects)) found three defects. The platform ships all three as the provider sent them. None moves a number: no balance, quantity or movement total reads these fields, so the wealth math is unaffected. Each fix is cheap but lost the time to work that touches the numbers a consumer acts on. The recipes are below so the next person can pick them up.

**A placeholder value in `post_fixed_indexer_percentage`.** 1,569 admitted lot rows carry `-0.000016`, the only negative value in the feed, repeating to the last digit: a placeholder, not rounding. Every other bank and credit row carries `1.000000` or `1.020000`. It reaches 114 of the 5,296 rows in `dim_holding`. Recipe: warn on `post_fixed_indexer_percentage < 0` in `_staging_quality.yml`, then null the value and flag the row, the same shape `clean_missing_date` uses for `0001-01-01`.

**Lots of one holding disagree on `indexer`.** 202 of the 5,296 rows in `dim_holding` draw from lots naming more than one indexer, most often `CDI` against `IPCA` (100 times). `arg_max(indexer, snapshot_created_at)` settles it, so the lot written last wins and the consumer never learns the lots disagreed. Recipe: raise an `indexer:unstable` flag and settle by majority vote instead of write order.

**Treasury indexers contradict their own product name.** A Tesouro Direto title names its indexer in its own name, yet `Tesouro Selic 2031` ships `indexer = OUTROS`, as do `Tesouro IPCA+ 2029` and `Tesouro Renda+ 2044`: 3 of the 8 treasury rows in `dim_holding`. The provider stamps `OUTROS` on a minority of every treasury title's lots, and `arg_max` sometimes lands on one; 375 lot rows carry an indexer their own product name rules out. Recipe: read the indexer off the product name, which is authoritative for Tesouro Direto, and warn when the payload disagrees.
