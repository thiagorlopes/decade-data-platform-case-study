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
**[Contracts](#contracts)**<br>
**[Consumers](#consumers)**<br>

## General Information

The visible deliverable is under [`consumers/wealth/`](consumers/wealth/): two SQL queries and their committed CSV output, answering what one customer holds and the movements behind it. Everything else in this repo exists to make that query cheap to write and safe to trust.

Two raw Open Finance Brasil feeds land in `data/`: **positions** (balance snapshots) and **transactions** (the movements behind them). dbt on DuckDB transforms both into a small consumption layer under an enforced output contract: `fct_holdings` and `fct_movements` for keys and measures, `dim_holding` for the descriptive attributes both facts join to. The wealth queries read only those three tables. A new consumer for a different question does the same, without touching raw or talking to the platform author.

For architecture and design rationale, see [Target Architecture & Environments](#target-architecture--environments) and [Data quality: detect, resolve, guarantee](#data-quality-detect-resolve-guarantee) below.

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

**`make ui`** opens the [DuckDB UI](https://duckdb.org/docs/stable/core_extensions/ui.html) at http://localhost:4213: a schema browser, a notebook-style SQL editor, and result grids. It runs the DuckDB CLI inside the container and publishes the UI port, so nothing needs to be installed on the host beyond a browser. The warehouse opens read-only. Close it before running `make build`. DuckDB is single-writer, so an open connection blocks the build.

**`make shell`** opens the DuckDB CLI inside the container. Use it for quick raw SQL, or when you can't install duckdb on the host. Same rule: close it before a build. To leave the shell, type `.quit` or press Ctrl-D.

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
- [`movements.sql`](consumers/wealth/movements.sql): the movements behind those holdings, each joined to the current holding it belongs to on the shared `holding_key`.

Run them from `make ui`. Add `WHERE party_id = '<uuid>'` to scope to one customer. The committed output under [`output/`](consumers/wealth/output/) covers three sample customers. `make consumers` regenerates it from the committed queries, so the CSVs cannot drift from the SQL that claims to produce them. A new consumer follows the same pattern: query `fct_holdings` / `fct_movements`, whose columns, types and flag vocabulary are contract-enforced in [`contracts/_consumption.yml`](contracts/_consumption.yml).

## Target Architecture & Environments

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native. The shape below is what production could look like, and the case is designed so the work could be transfered if considered appropriate by the Decade Data Team.

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

- **Row-level**: `data_quality_flags` column on every fct and holdings row (e.g. `['purchase_date:missing', 'gross:zero_transient']`). Empty list means clean.
- **Row-level, per-lot verdict**: `admission` column on the intermediate `int_*_positions` tables. `admit` flows to the holdings views; `reject_duplicate`, `reject_zero_duplicate` and `quarantine` stay in the positions table for audit.
- **Row-level, dropped movement twins**: anti-join `int_*_transactions` to `fct_movements` on `transaction_id`; every missing row has a surviving copy flagged `transaction_id:reissued`. The `cross_id_dedup_semantics` unit test pins that rule.
- **Run-level**: `main_dbt_test__audit.*`, one row per warned row per test per run.
- **Contract-level**: `models/canonical/_canonical.yml`. The full admission enum and data_quality_flags vocabulary are single-sourced in [`_docs.md`](models/canonical/_docs.md) and rendered on every column that carries them via `make docs`.

**State today**: three stages, one folder each.

**DETECT** lives in `models/staging/`. Rules sit in `_staging_quality.yml`. After `make build`, the audit ledger lands in `main_dbt_test__audit.*`. Every warn count is reproduced cell-by-cell in [`notebooks/02_within_record_defects.ipynb`](notebooks/02_within_record_defects.ipynb).

**RESOLVE** lives in `models/canonical/intermediate/`. Both feeds survive a record re-delivered with a different value: the latest arrival wins. Positions apply this through the `latest_lot_delivery` macro; transactions use the same rule inline. Superseded copies stay countable in the `lot_redelivery` warn ledger. Positions are then deduped across investment_ids by the `resolve_duplicate_investments` macro. Movements the provider re-issued under another investment_id of the same holding collapse to one copy, flagged `transaction_id:reissued`, through the `cross_id_movements` macro; the same deduplicated stream feeds the holding-grain quantity replay. The admission enum is contract-tested at error severity. The cross-sync flags (`gross:zero_transient`, `investment_id:replaced`, `investment_id:multiple`, `lot:zero_kept`) are columns on the `int_*_holdings` views in the same folder. Those views have unique-grain tests and are materialized as views (not tables), so downstream `lag`/`lead` over the full sync history stays cheap.

**GUARANTEE** lives in `models/consumption/`. `fct_holdings` and `fct_movements` each union the five families into one conformed shape. dbt contracts are enforced, so the build fails on column or type drift. Grain tests run at error severity. Consumers under `consumers/` read those two models and nothing below them.

#### Admission at a glance

| Value | Meaning | Downstream effect |
|---|---|---|
| `admit` | Lot is clean or a resolved conflict winner. | Aggregated into holdings. |
| `reject_duplicate` | Redundant copy of a hard duplicate (all measures agree under one natural key). | Ignored; kept in `int_*` for audit. |
| `reject_zero_duplicate` | Frozen zero-valued side of a same-sync conflict (its live sibling is admitted with `lot:zero_copy_dropped`). | Ignored; kept in `int_*` for audit. |
| `quarantine` | Same-sync conflict with no single live row to pick. | Excluded from holdings; kept in `int_*_positions` (query `WHERE admission = 'quarantine'`) for audit. |

#### Flags at a glance

Every flag follows the shape `subject:verdict`: the prefix names the column or entity to doubt, the suffix names the verdict on it. A consumer selects a whole class with one suffix filter (`WHERE flag LIKE '%:missing'`). Lot flags are added in `int_*_positions`, holding flags in `int_*_holdings`, movement flags in `fct_movements`.

| Grain | Flag | Meaning |
|---|---|---|
| Lot | `<column>:missing` | A spec-required column arrived empty and could not be repaired (`indexer:missing`, `isin_code:missing`, ...). |
| Lot | `natural_key:missing` | The record has no identity to merge on. It becomes its own holding, keyed by its investment_id. |
| Lot | `lot:zero_copy_dropped` | The sync delivered two copies of the lot, one live and one zero. The live copy was kept; the zero copy was dropped. |
| Lot | `net:above_gross` | The payload's net exceeds its gross. One of the two is wrong; both are kept as delivered. Do not trust net on this row. |
| Lot | `gross:not_quantity_times_price` | The payload's gross disagrees with its own quantity times unit price. All three fields are kept as delivered. |
| Lot | `financial_transaction_tax:placeholder` | The payload reports a transaction tax that does not exist for the row: net equals gross minus income tax to the cent. The amount is a placeholder, not a tax. |
| Holding | `investment_id:multiple` | The provider keeps two or more live position records for the security at once. The holding sums them. |
| Holding | `investment_id:replaced` | The provider retired one id and issued a new one for the same security. Both ids resolve to the same holding, so its movements and replay follow it across the replacement. |
| Holding | `lot:zero_kept` | One of the summed lots is worth zero while its siblings are live. It was kept, not dropped like a `lot:zero_copy_dropped`. |
| Holding | `gross:zero_transient` | Gross went to zero for one sync and came back, with quantity unchanged. |
| Holding | `quantity_reported:stale` | The balance quantity disagrees with the quantity replayed from movements. The plain quantity column already prefers the replay; the provider's number stays in `quantity_reported`. |
| Holding | `movements:incomplete` | The replay is infeasible even under the most favorable ordering, so movements must be missing. Keep the provider's quantity and caveat it. The feed serves only recent history, so gaps are expected ([why](#the-feed-serves-only-recent-history)). |
| Holding | `holding:matured` | The due date has passed and the institution still reports a balance. This flag discloses a fact. It changes no number. Only the three families that carry a due date raise it. |
| Movement | `transaction_date:missing` | No usable movement date. The movement counts in totals but has no place on a timeline. |
| Movement | `transaction_id:reissued` | The provider re-delivered this movement under another investment_id of the same holding, with a fresh transaction_id. This copy stands for the copies; its twins were dropped. |

The long-form version of each entry lives in the [`data_quality_flags` doc block](models/canonical/_docs.md) and renders on every column that carries it via `make docs`.

#### The feed serves only recent history

The transactions endpoint returns a bounded slice of history. That limit
is how a replay can go negative with nobody at fault, so
`movements:incomplete` is usually a gap in the feed rather than an error
by the provider.

Three facts measured on this sample:

- Every holding carries its opening acquisition at its true date, back to 2019.
- 99.6% of third-and-later movements land on or after 2025-08-19.
- The syncs run from 2026-07-28 to 2026-08-21, so that start date is a trailing twelve months.

The feed never serves trades struck between the purchase and the start of
that window. A ledger can therefore show a sell whose matching buy is
missing, and the replay runs negative through no fault of the data. All
1,094 occurrences are that case. None is a holding with no receipts at all.

The platform refuses rather than guesses. A holding whose replay is
infeasible keeps the provider's `quantity`, carries `movements:incomplete`,
and tells the consumer so. It does not publish a derived number it cannot
support.

Breakage tracks how many movements are visible, not how old the purchase
is. The flag never fires on holdings with one or two movements, and it
reaches 49% at six or more.

#### Field trust at a glance

Every field earns its treatment from evidence, not hope. Quantity is a
write-once field in this feed (zero of ten thousand raw position records
ever update it), so the platform recalculates it from the movements ledger
and publishes the resolved number as the plain `quantity` column. Prices update every
sync and drive gross, so `unit_price` is exposed as the maintained half of
the provider's valuation. Gross and net stay as the provider's marks, on
the provider's own basis, with that basis disclosed in the contract; they
cannot be recomputed without inventing data, but they can be cross-checked
against the record itself, and the `net:above_gross` and
`gross:not_quantity_times_price` flags carry the verdicts. The naming carries the
same rule: a plain column (`quantity`, `gross_amount`) is a number the
platform stands behind, and the plain columns of a row agree with each
other; a `_reported` column is the provider's original claim, kept for
reconciliation; net exists only as `net_amount_reported` because nothing
can vouch for it. In one line: recalculate what an independent source can
prove, quote and disclose what only the provider knows, and
contradiction-check everything inside the record.

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
| `0001-01-01` placeholder dates (.NET `DateTime.MinValue`) | Required field arriving empty | `clean_missing_date` | `<column>:missing` for the nulled date, e.g. `purchase_date:missing` | 1 951 |
| Blank strings on natural-key fields | Required field arriving empty | `blank_to_null` | `natural_key:missing` when no identity survives | see warn tests |
| `'IPC-A'` for `'IPCA'` (plausible market spelling) | Legal value outside the enumeration | `clean_indexer` | none, fully repaired | 2 |
| `1970-01-01` placeholder dates (Unix epoch zero) on transaction dates | Required field arriving empty | `clean_missing_date` | `transaction_date:missing` on `fct_movements` | 3 001 |
| CNPJ with decimal tail (`92894922000108.00`) | Right concept, wrong form (named) | `clean_cnpj` | none, fully repaired | 1 370 |
| `9900` placeholder quantity on duplicated position records | Required field arriving empty | co-admission rule in `cross_id_movements` | `gross:not_quantity_times_price` | 1 722 |
| `88.90` placeholder transaction tax, constant across position sizes and never subtracted from net | Required field arriving empty | flag only, amounts kept as delivered | `financial_transaction_tax:placeholder` | 1 877 |

**Unlisted classes, all zero hits.** Nine defect classes the brief does not name and the sample does not contain. Zero hits shows the seeding stuck to the announced classes. It does not prove these defects are absent in production. In production, each would become a warn test in `_staging_quality.yml`. The sample does not justify permanent tests for data that is not there.

| Probe | Rationale |
|---|---|
| Same `transaction_id`, conflicting `transaction_amount` | Transactions-side analogue of the redundant-copies defect |
| Negative `transaction_amount` or `gross_amount` | Sign errors on values the domain treats as positive |
| Transaction dated after its own snapshot | Envelope violation: the payload references a future the snapshot can't see |
| Holding switching currency between syncs | Cross-sync contradiction not covered by `gross:zero_transient` |
| Holding dropout (present, absent one sync, present again) | Missing-row cousin of `gross:zero_transient`; the provider drops the row instead of zeroing it |
| Zero quantity with positive gross_amount | Mirror of the `gross:zero_transient` defect at a single row |
| Quantity change with no transaction behind it | Cross-feed reconciliation: positions and transactions disagreeing on a movement |

The last probe is also a modeling finding. Quantities never move in the sample. Every seeded across-record defect keys on "quantity unchanged" because quantity is the only invariant the sample offers.

**Unlisted classes found and left unhandled.** A third audit ran over the descriptive attributes of `dim_holding` and found three defects there. The platform ships all three as they arrive. They are measured and written up under [Deliberately left out: three descriptive-field defects](#deliberately-left-out-three-descriptive-field-defects).

### Materializations

Layer materializations follow dbt Labs' guidance — [staging as views](https://docs.getdbt.com/best-practices/how-we-structure/2-staging) and the general progression from the [materializations best practices](https://docs.getdbt.com/best-practices/materializations/1-guide-overview): *"Start with a view. When the view gets too long to query for end users, make it a table. When the table gets too long to build, build it incrementally."*

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
- **Building canonical from raw**: reprocessing only the snapshots with arrivals at or past the newest one already built (watermark on `ingested_at`), merged by key so re-runs are idempotent. **This is what §3.2 of the brief asks for, and what this repo ships.**



### Deliberately left out: a test on the watermark boundary

The `>=` in `snapshot_watermark` is load-bearing. One arrival batch shares one `ingested_at` stamp, so a run that read a batch mid-landing must re-read that batch whole on the next run. No automated test pins this. dbt unit tests run with `is_incremental` off, so no fixture can reach the comparison. A mutation pass confirmed the gap: flipping `>=` to `>` passes every test in the project, while nineteen other rule mutations fail their unit test.

The verification is manual instead: build twice over the same raw files and the warehouse is byte-identical. The closing check would be a two-run CI job that builds, lands a late row carrying the boundary stamp, rebuilds, and asserts the row arrived. At this repo's scale the manual check earns its keep; that CI job is the first test to add when the loader goes live.

### Deliberately left out: three descriptive-field defects

The audit found three defects in the descriptive attributes of `dim_holding`. The platform ships all three exactly as the provider sent them. Each one is real and measured below. None of them moves a number: no balance, quantity or movement total reads these fields, so the wealth math is unaffected.

Each would need a detection rule and a repair, and both are cheap. They lost the time to work that touches the numbers a consumer acts on. The recipes are written out so the next person can pick them up.

**A placeholder value in `post_fixed_indexer_percentage`.** 1,569 admitted lot rows carry `-0.000016`. A percentage of an indexer cannot be negative. That value is the only negative one in the feed and it repeats to the last digit, so it is a placeholder rather than a rounding artifact. Every other bank and credit row carries `1.000000` or `1.020000`. It reaches 114 of the 5,296 rows in `dim_holding`. The recipe: warn on `post_fixed_indexer_percentage < 0` in `_staging_quality.yml`, then null the value and flag the row, the same shape `clean_missing_date` already uses for `0001-01-01`.

**Lots of one holding disagree on `indexer`.** 202 of the 5,296 rows in `dim_holding` draw from lots that name more than one indexer. `CDI` against `IPCA` on the same security is the most common pair, 100 times. `dim_holding` resolves the disagreement with `arg_max(indexer, snapshot_created_at)`, so the lot written last wins and the consumer never learns the lots disagreed. The recipe: raise an `indexer:unstable` flag on the holding, and settle the value by majority vote instead of by write order.

**Treasury indexers contradict their own product name.** A Tesouro Direto title names its indexer in its title. `Tesouro Selic 2031` ships `indexer = OUTROS`. `Tesouro IPCA+ 2029` and `Tesouro Renda+ 2044` do the same. That is 3 of the 8 treasury rows in `dim_holding`. The provider stamps `OUTROS` on a minority of the lots of every treasury title, and `arg_max` sometimes lands on one of them. 375 lot rows carry an indexer their own product name rules out. The recipe: read the indexer off the product name for Tesouro Direto, where the name is authoritative, and warn when the payload disagrees.
