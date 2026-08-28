# Decade Data Platform Case Study

This repository contains Thiago Portugues's solution for the hiring process at Decade.

## Table of Contents

**[General information](#general-information)**<br>
**[Prerequisites](#prerequisites)**<br>
**[Installation](#installation)**<br>
**[Development cycle](#development-cycle)**<br>
**[Querying the warehouse](#querying-the-warehouse)**<br>
**[Browsing the data model](#browsing-the-data-model)**<br>
**[Contracts](#contracts)**<br>
**[Consumers](#consumers)**<br>

## General Information

This repo turns Open Finance Brasil investment snapshots into two consumption-ready fact tables (`fct_holdings`, `fct_movements`) using dbt on DuckDB. Raw parquet lands in `data/`, dbt transforms it through staging, intermediate, and consumption layers, and enforced contracts guarantee the output shape.

For architecture and design rationale, see [Target Architecture & Environments](#target-architecture--environments) and [Data quality: detect, resolve, guarantee](#data-quality-detect-resolve-guarantee) below.

## Prerequisites

- Docker Engine with Docker Compose v2
- `make` and `git`

The docker image ships Python, dbt, and the DuckDB CLI. You don't need a host-side Python install to run the pipeline.

Notebooks under `notebooks/` are dev-only and stay out of the image. To re-run them, install the deps into a local venv:

```bash
pip install jupyterlab==4.6.3 pandas==2.2.3 pyarrow==17.0.0
```

## Installation

```bash
make install     # build the docker image
```

The `make` targets cover the whole pipeline. For scoped dbt commands, such as `dbt build --select <model>+`, install dbt on the host with the same pinned versions the image uses:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Development cycle

After `make install`, use these targets to iterate:

| Command | What it does |
|---|---|
| `make build` | Run models + tests. The safe default. |
| `make run` | Run models only. Faster when you know tests will pass. |
| `make test` | Run tests against the current warehouse. No rebuild. |
| `make docs` | Regenerate the docs catalog and serve at http://localhost:8080. |
| `make refresh` | `build` + `docs` in one shot. Use after changing SQL to see updated docs. |
| `make consumers` | Regenerate the CSVs under `consumers/wealth/output/` from the committed queries. |
| `make shell` | Open the DuckDB CLI on `warehouse.duckdb` inside the container. |
| `make ui` | Browse the warehouse in the DuckDB UI. See [Querying the warehouse](#querying-the-warehouse). |
| `make clean` | Wipe the warehouse and dbt artifacts. Use when state gets stuck. |
| `make help` | List all targets. |

`make build` is idempotent. Canonical models are incremental, keyed on `(snapshot_id, investment_id)` with an `ingested_at` watermark, so reruns only process snapshots with new arrivals. To reprocess everything after a transform change: `make clean && make build` (equivalent to `dbt build --full-refresh` on a fresh warehouse).

## Querying the warehouse

The typical loop: edit a model, `make build`, then check the numbers with one of these.

**`make ui`** opens the [DuckDB UI](https://duckdb.org/docs/stable/core_extensions/ui.html) at http://localhost:4213: a schema browser, a notebook-style SQL editor, and result grids. It needs the [duckdb CLI](https://duckdb.org/install) on the host and opens the warehouse read-only. Close it before running `make build`. DuckDB is single-writer, so an open connection blocks the build.

**`make shell`** opens the DuckDB CLI inside the container. Use it for quick raw SQL, or when you can't install duckdb on the host. Same rule: close it before a build.

## Browsing the data model

Every staging and intermediate model carries a description and per-column docs, sourced from the Open Finance Brasil investment API specs and referenced through shared `{% docs %}` blocks in [`models/canonical/_docs.md`](models/canonical/_docs.md).

Run `make docs` and open http://localhost:8080. The site lets you browse the DAG, jump between models, and read OFB spec fields, enum values, and defect handling rules per column. Docs render from `warehouse.duckdb` — run `make build` first if it's missing.

<img width="1828" height="927" alt="image" src="https://github.com/user-attachments/assets/0fc52a71-f6ed-4aed-8fa7-2c66e25bcb2f" />

<img width="1898" height="972" alt="image" src="https://github.com/user-attachments/assets/d09a46c7-526f-417b-baf8-16c565e4b369" />

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

## Consumers

The wealth page lives in [`consumers/wealth/`](consumers/wealth/): two plain SQL queries over the consumption layer, never raw or staging.

- [`holdings.sql`](consumers/wealth/holdings.sql): what customers hold, valued at each account's latest sync per product family, with `data_quality_flags` on every row.
- [`movements.sql`](consumers/wealth/movements.sql): the movements behind those holdings, each tagged with the current holding it belongs to by matching its `investment_id` against the holding's contributing ids.

Run them from `make ui`. Add `WHERE party_id = '<uuid>'` to scope to one customer. The committed output under [`output/`](consumers/wealth/output/) covers three sample customers. `make consumers` regenerates it from the committed queries, so the CSVs cannot drift from the SQL that claims to produce them. A new consumer follows the same pattern: query `fct_holdings` / `fct_movements`, whose columns, types and flag vocabulary are contract-enforced in [`contracts/_consumption.yml`](contracts/_consumption.yml).

## Target Architecture & Environments

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native. The shape below is what production could look like, and the case is designed so the work could be transfered if considered appropriate by the Decade Data Team.

It follows the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices). The doc scales workspace count to team size: two workspaces (dev/prod) for teams up to five engineers, three (dev/staging/prod) beyond that.

Git is the source of truth ("if it isn't in version control, it doesn't exist"), and CI/CD gates promotion between environments. The diagram below is the doc's illustration of one such production deployment workflow at scale, included here for reference rather than as the shape this case commits to:

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

This case study solution ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any computer with no account required; the same dbt models run against Databricks when promoted. The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace through a profile change. That way, we would be able to close one tradeoff this shortcut carries: SQL dialect drift between the two engines.

### Orchestration

All the orchestrator has to do is run two commands on timers:

- `dbt build`, every few minutes: matches the arrival cadence of the raw feeds. The job is watermarked and idempotent, so a repeated or overlapping run leaves the same result as a single run.
- `dbt source freshness`, on its own cadence: pages the on-call when a feed stalls. The thresholds live in `models/_sources.yml`: warn after one quiet hour, error after six, measured on `ingested_at`. Staleness never blocks the build, so consumers keep reading correct data that is merely old. On this static sample the command always reports stale; that is the signal working against week-old data, not a defect.

In the Databricks target this is a two-task Workflows job. Airflow, Dagster, or cron can do the same work, because each command is self-contained: ordering, retries, and state all live in dbt and the watermark. This keeps the scheduler free of pipeline logic, so swapping it is a profile-sized change.

### Data quality: detect, resolve, guarantee

Target architecture for §2.2. Provider defects split into within-record (a required field empty, a value in the wrong form, a legal value outside its enum, a cross-field contradiction) and across-record (the same holding under two ids, holdings that freeze under a new id, a zero-then-nonzero valuation). The target pipeline splits their handling across three layers so each layer has one job:

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

- **Row-level**: `data_quality_flags` column on every fct and holdings row (e.g. `['missing:purchase_date', 'zero:transient']`). Empty list means clean.
- **Row-level, per-lot verdict**: `admission` column on the intermediate `int_*_positions` tables. `admit` flows to the holdings views; `reject_duplicate`, `reject_zero_duplicate` and `quarantine` stay in the positions table for audit.
- **Run-level**: `main_dbt_test__audit.*`, one row per warned row per test per run.
- **Contract-level**: `models/canonical/_canonical.yml`. The full admission enum and data_quality_flags vocabulary are single-sourced in [`_docs.md`](models/canonical/_docs.md) and rendered on every column that carries them via `make docs`.

**State today**: three stages, one folder each.

**DETECT** lives in `models/staging/`. Rules sit in `_staging_quality.yml`. After `make build`, the audit ledger lands in `main_dbt_test__audit.*`. Every warn count is reproduced cell-by-cell in [`notebooks/02_within_record_defects.ipynb`](notebooks/02_within_record_defects.ipynb).

**RESOLVE** lives in `models/canonical/intermediate/`. Positions are deduped by the `resolve_duplicate_investments` macro. Transactions use latest-delivery dedup. The admission enum is contract-tested at error severity. The cross-sync flags (`zero:transient`, `investment_id:replaced`, `investment_id:multiple`, `zero:lot_kept`) are columns on the `int_*_holdings` views in the same folder. Those views have unique-grain tests and are materialized as views (not tables), so downstream `lag`/`lead` over the full sync history stays cheap.

**GUARANTEE** lives in `models/consumption/`. `fct_holdings` and `fct_movements` each union the five families into one conformed shape. dbt contracts are enforced, so the build fails on column or type drift. Grain tests run at error severity. Consumers under `consumers/` read those two models and nothing below them.

#### Admission at a glance

| Value | Meaning | Downstream effect |
|---|---|---|
| `admit` | Lot is clean or a resolved conflict winner. | Aggregated into holdings. |
| `reject_duplicate` | Redundant copy of a hard duplicate (all measures agree under one natural key). | Ignored; kept in `int_*` for audit. |
| `reject_zero_duplicate` | Frozen zero-valued side of a same-sync conflict (its live sibling is admitted with `zero:duplicate_dropped`). | Ignored; kept in `int_*` for audit. |
| `quarantine` | Same-sync conflict with no single live row to pick. | Excluded from holdings; kept in `int_*_positions` (query `WHERE admission = 'quarantine'`) for audit. |

#### Flags at a glance

Every flag follows the shape `family:detail`, so a consumer selects a whole class with one prefix filter (`WHERE flag LIKE 'missing:%'`). Lot flags are added in `int_*_positions`, holding flags in `int_*_holdings`, movement flags in `fct_movements`.

| Grain | Flag | Meaning |
|---|---|---|
| Lot | `missing:<column>` | A spec-required column arrived empty and could not be repaired (`missing:indexer`, `missing:isin_code`, ...). |
| Lot | `missing:natural_key` | The record has no identity to merge on. It becomes its own holding, keyed by its investment_id. |
| Lot | `zero:duplicate_dropped` | The sync delivered two copies of the lot, one live and one zero. The live copy was kept; the zero copy was dropped. |
| Holding | `investment_id:multiple` | The provider keeps two or more live position records for the security at once. The holding sums them. |
| Holding | `investment_id:replaced` | The provider retired one id and issued a new one for the same security. Movements do not carry over between them. |
| Holding | `zero:lot_kept` | One of the summed lots is worth zero while its siblings are live. It was kept, not dropped like a `zero:duplicate_dropped`. |
| Holding | `zero:transient` | Gross went to zero for one sync and came back, with quantity unchanged. |
| Holding | `stale:quantity` | The balance quantity disagrees with the quantity replayed from movements. Prefer `quantity_derived`. |
| Holding | `movements:incomplete` | The replay is infeasible even under the most favorable ordering, so movements must be missing. Keep the provider's quantity, with a caveat. |
| Movement | `missing:transaction_date` | No usable movement date. The movement counts in totals but has no place on a timeline. |

The long-form version of each entry lives in the [`data_quality_flags` doc block](models/canonical/_docs.md) and renders on every column that carries it via `make docs`.

#### Quarantine runbook

Quarantined lots live in `int_*_positions` with `admission = 'quarantine'`: the classifier refused to guess. Every occurrence is actionable:

1. **Triage.** Query the family's `int_*_positions` filtered on `admission = 'quarantine'` for the natural key, both investment_ids, quantity and the conflicting gross amounts. Cross-check the transactions feed for the same account and holding (did a redemption explain the drop?), then look at the next sync (did one copy fossilize while the other moved?).
2. **Resolve.** One of three paths:
   - **Transient**: the next sync disambiguates on its own. No code change; the holding re-admits itself.
   - **Systematic**: a pattern emerges (e.g. the row with the newer `reference_datetime` is always the live one). Encode it as a new classification branch in `resolve_duplicate_investments`, then replay history with `make clean && make build` (the incremental-idempotency deliverable pays for exactly this).
   - **Provider defect**: neither feed explains it. Escalate to the institution with the staging warn tests as corroborating evidence.
3. **Meanwhile, the consumer is protected by construction.** Quarantined lots never reach `int_*_holdings`, so the wealth page under-counts one holding rather than fabricating a number. This is a deliberate product stance: when valuations conflict irreconcilably, a conservative omission beats a made-up value, and the omission is discoverable in the positions table.

#### Beyond the listed defects

The brief warns that "an institution respecting [the spec] is a hope, not a guarantee." So the §2.2 list is illustrative, not exhaustive. Two audits ran against the built warehouse.

**Listed classes in new forms.** The case authors seeded the announced defect classes in forms the brief does not name. The intermediate layer's repair macros handle them. Raw counts stay visible in the staging warn tests. When the repair cannot recover the value, the row carries a flag in `data_quality_flags`; a fully repaired value carries no flag.

| Form | Class it belongs to | Where handled | Flag on the row | Raw count |
|---|---|---|---|---|
| `0001-01-01` placeholder dates (.NET `DateTime.MinValue`) | Required field arriving empty | `clean_missing_date` | `missing:<column>` for the nulled date, e.g. `missing:purchase_date` | 1 951 |
| Blank strings on natural-key fields | Required field arriving empty | `blank_to_null` | `missing:natural_key` when no identity survives | see warn tests |
| `'IPC-A'` for `'IPCA'` (plausible market spelling) | Legal value outside the enumeration | `clean_indexer` | none, fully repaired | 2 |
| `1970-01-01` placeholder dates (Unix epoch zero) on transaction dates | Required field arriving empty | `clean_missing_date` | `missing:transaction_date` on `fct_movements` | 3 001 |
| CNPJ with decimal tail (`92894922000108.00`) | Right concept, wrong form (named) | `clean_cnpj` | none, fully repaired | 1 370 |

**Unlisted classes, all zero hits.** Nine defect classes the brief does not name and the sample does not contain. Zero hits shows the seeding stuck to the announced classes. It does not prove these defects are absent in production. In production, each would become a warn test in `_staging_quality.yml`. The sample does not justify permanent tests for data that is not there.

| Probe | Rationale |
|---|---|
| Same `transaction_id`, conflicting `transaction_amount` | Transactions-side analogue of the redundant-copies defect |
| Negative `transaction_amount` or `gross_amount` | Sign errors on values the domain treats as positive |
| Transaction dated after its own snapshot | Envelope violation: the payload references a future the snapshot can't see |
| Holding switching currency between syncs | Cross-sync contradiction not covered by `zero:transient` |
| Holding dropout (present, absent one sync, present again) | Missing-row cousin of `zero:transient`; the provider drops the row instead of zeroing it |
| Zero quantity with positive gross_amount | Mirror of the `zero:transient` defect at a single row |
| Quantity change with no transaction behind it | Cross-feed reconciliation: positions and transactions disagreeing on a movement |

The last probe is also a modeling finding. Quantities never move in the sample. Every seeded across-record defect keys on "quantity unchanged" because quantity is the only invariant the sample offers.

### Materializations

Layer materializations follow dbt Labs' guidance — [staging as views](https://docs.getdbt.com/best-practices/how-we-structure/2-staging) and the general progression from the [materializations best practices](https://docs.getdbt.com/best-practices/materializations/1-guide-overview): *"Start with a view. When the view gets too long to query for end users, make it a table. When the table gets too long to build, build it incrementally."*

| Layer | Materialization | Why |
|-------|----------------|-----|
| staging | view | Cheap renames/casts read only by the next layer during builds; always fresh, no storage spent on models consumers never query. |
| intermediate (positions) | incremental | Each run reprocesses every snapshot that received an arrival past the watermark (`ingested_at`, the arrival time), whole, not row by row. Duplicate classification compares rows within one sync, so a late or re-delivered row must be re-judged with the siblings that already landed; `unique_key (snapshot_id, investment_id)` makes the re-touched rows an upsert, so repeated runs stay idempotent. Replay after a transform fix: `dbt build --full-refresh`. |
| intermediate (holdings) | view | Cross-sync flags need lag/lead over the whole natural-key timeline, which a view sees for free without re-materializing prior syncs. Fine at sample scale; promote to table per the progression above if the timeline outgrows a view. |
| consumption | table | Contract-enforced union of the five families. Read by every consumer and by ad-hoc queries. Stored as a table so the guarantee layer is built once per run, not recomputed on every query. |

<img width="720" height="596" alt="bundles-branching-0b017c959921574bebad867191cd736b" src="https://github.com/user-attachments/assets/669a223a-aa0a-463a-882a-11d4abe01a05" />

### Physical layout

Locally the warehouse is one 62 MB DuckDB file, and at that size no layout tuning pays for itself. The decisions below are for the Databricks target, where the canonical layer absorbs millions of records a day and layout decides how much data each query reads.

The layout serves four query patterns:

| Pattern | Shape | Reader |
|---|---|---|
| Wealth page | one customer, latest snapshot | product, point lookup |
| Net worth over time | one customer, full history | product, timeline scan |
| Portfolio analytics | many customers, bounded dates | analysts and services |
| The build itself | whole snapshots past the watermark | the incremental job |

Three decisions serve them:

- **Cluster by customer, then time.** Both facts are Delta tables with [liquid clustering](https://docs.databricks.com/aws/en/tables/clustering): `(party_id, snapshot_created_at)` for holdings, `(party_id, transaction_date)` for movements. Every product query filters on one customer first, so file skipping cuts a point lookup to a handful of files no matter how many customers connect. We cluster instead of partitioning Hive-style because `party_id` has far too many values for a partition key: one folder per customer creates the small-file problem by design.
- **Compact toward ~128 MB files.** A build every few minutes writes small files all day. Auto compaction and optimized writes keep files near the 128 MB target, so the file count tracks data volume, not run count.
- **Let cost grow with customers, not with history.** Storage grows linearly with connected customers. A point query reads one cluster, so its cost stays flat as customers grow. Build compute follows the arrival rate, because the watermark reprocesses only snapshots with new arrivals. At ten times the customers: ten times the storage, the same wealth-page latency, and builds still sized by arrivals per window.

### Compliance

The sample is synthetic, so the repo can commit query outputs (`consumers/wealth/output/`); production outputs never land in git. In production every field is personal financial data under LGPD, Brazil's data protection law, and five boundaries would apply:

- **The layer boundary is the access boundary.** Raw and staging hold provider payloads verbatim and stay locked to the pipeline's service principal. Consumers get Unity Catalog grants on the consumption schema only. The rule "consumers read consumption, never raw" stops being a convention and becomes an ACL.
- **Consumption is pseudonymous.** `party_id`, `account_id`, and `investment_id` are opaque UUIDs end to end. The consumption layer carries product attributes (fund names, issuer CNPJs, tickers) and no customer names or personal documents. Re-identification requires the customer registry, which lives outside this platform.
- **Erasure is a clustered delete, then a purge.** LGPD gives customers the right to have their data deleted on request. The facts cluster on `party_id`, so step one is a targeted `DELETE` that touches only that customer's files; the same key that serves the wealth page serves erasure. A `DELETE` alone is not erasure: the rows survive in raw, in staging, and in Delta time travel. Full erasure also purges the raw and staging copies, runs `VACUUM` past the retention window so old table versions forget the rows, and lets backups expire on a stated schedule.
- **Consent bounds what the pipeline may hold.** Open Finance consent has a scope and an expiry. When a customer revokes it, ingestion stops for that connection and the erasure path runs. Raw is kept only as long as reprocessing needs it, then purged on a stated retention window. Data serves the consented purpose only; a new use, such as model training, needs a new legal basis.
- **Access is logged; data stays encrypted and in Brazil.** Unity Catalog audit logs record every read of the consumption schema. Encryption in transit and at rest is the platform default. Data stays in a Brazilian region, where the customers and their Open Finance consent live.

These five boundaries are the platform's technical measures. The organizational side of LGPD (a data protection officer, records of processing, incident response) lives outside this repo.

## Data flow: two kinds of incremental

Incremental means two different things in this pipeline.

- **Loading raw**: picking up only the new arrival files. In production, Databricks Auto Loader watches the drop folder and appends what it hasn't seen before. Not implemented here: raw was handed to us as two static parquet files, so there are no "new arrivals". This is what the Databricks target ([Architecture](#architecture)) turns on.
- **Building canonical from raw**: reprocessing only the raw rows newer than the last canonical build (watermark on `ingested_at`), merged by key so re-runs are idempotent. **This is what §3.2 of the brief asks for, and what this repo ships.**


