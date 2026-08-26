# Decade Data Platform Case Study

This repository contains Thiago Portugues's solution for the hiring process at Decade.

## Table of Contents

**[General information](#general-information)**<br>
**[Prerequisites](#prerequisites)**<br>
**[Installation](#installation)**<br>
**[Development cycle](#development-cycle)**<br>
**[Browsing the data model](#browsing-the-data-model)**<br>

## General Information

Lorem ipsum

## Prerequisites

- Docker Engine + Docker Compose v2
- `make`, `git`

Everything the pipeline needs (Python, dbt, DuckDB CLI) is bundled inside the image. No host-side Python setup required.

Notebook exploration (`notebooks/`) uses jupyterlab + pandas + pyarrow. Those are dev-only and kept out of the image. Install them into a local venv if you need to re-run the notebook:

```bash
pip install jupyterlab==4.6.3 pandas==2.2.3 pyarrow==17.0.0
```

## Installation

```bash
make install     # builds the docker image
```

## Development cycle

After `make install`, the loop when editing models or tests:

```bash
make check       # smoke test the wiring: list declared dbt sources
make parse       # validate project config (fast, no warehouse writes)
make build       # run all dbt models and tests
make test        # re-run tests only against the current warehouse
make shell       # open duckdb CLI on the warehouse (inside container)
make clean       # wipe warehouse and dbt artifacts if state gets stuck
make help        # list all targets
```

`make build` is idempotent: canonical models are incremental keyed on `(snapshot_id, investment_id)` with an `ingested_at` watermark, so reruns only process new arrivals. To reprocess everything after a transform change, `make clean && make build` (equivalent to `dbt build --full-refresh` against a fresh warehouse).

## Browsing the data model

Every staging, intermediate and consumption model carries a description and per-column documentation, sourced from the Open Finance Brasil investment API specs and referenced via shared `{% docs %}` blocks in [`models/canonical/_docs.md`](models/canonical/_docs.md). To read it in your browser:

```bash
make docs-serve    # generates the catalog and serves it at http://localhost:8080
```

The generated site lets you browse the DAG, jump between models, and see the OFB spec fields, enum values and defect handling rules for every column. Docs are built against `warehouse.duckdb`; run `make build` first if it's missing.

## Target Architecture & Environments

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native. The shape below is what production could look like, and the case is designed so the work could be transfered if considered appropriate by the Decade Data Team.

It follows the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices). The doc scales workspace count to team size: two workspaces (dev/prod) for teams up to five engineers, three (dev/staging/prod) beyond that.

Git is the source of truth ("if it isn't in version control, it doesn't exist"), and CI/CD gates promotion between environments. The diagram below is the doc's illustration of one such production deployment workflow at scale, included here for reference rather than as the shape this case commits to:

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

This case study solution ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any computer with no account required; the same dbt models run against Databricks when promoted. The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace through a profile change. That way, we would be able to close one tradeoff this shortcut carries: SQL dialect drift between the two engines.

### Data quality: detect, resolve, guarantee

Target architecture for §2.2. Provider defects split into within-record (a required field empty, a value in the wrong form, a legal value outside its enum, a cross-field contradiction) and across-record (the same holding under two ids, holdings that freeze under a new id, a zero-then-nonzero valuation). The target pipeline splits their handling across three layers so each layer has one job:

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

- **Row-level**: `data_quality_flags` column on every fct and holdings row (e.g. `['missing:purchase_date', 'zero_flap']`). Empty list means clean.
- **Row-level, per-lot verdict**: `admission` column on the intermediate `int_*_positions` tables. `admit` flows to holdings; `reject_duplicate`, `reject_fossil` and `quarantine` stay in the int table for audit.
- **Run-level**: `main_dbt_test__audit.*`, one row per warned row per test per run.
- **Contract-level**: `models/canonical/_canonical.yml` and `models/consumption/_consumption.yml`. The full admission enum and data_quality_flags vocabulary are single-sourced in [`_docs.md`](models/canonical/_docs.md) and rendered on every column that carries them via `make docs-serve`.

**State today**: DETECT and RESOLVE are shipped. DETECT lives in `models/canonical/staging/_staging_quality.yml`; the audit ledger populates `main_dbt_test__audit.*` after `make build`; every warn count is reproduced cell-by-cell in [`notebooks/02_within_record_defects.ipynb`](notebooks/02_within_record_defects.ipynb). RESOLVE lives in `models/canonical/intermediate/` with the `resolve_duplicate_investments` macro for positions, latest-delivery dedup for transactions, and the admission enum contract-tested at error severity. GUARANTEE (the `models/consumption/` holdings views with unique-grain tests and the warn-severity quarantine monitor on `holdings_quarantine`) lands in the follow-up consumption PR.

#### Admission at a glance

| Value | Meaning | Downstream effect |
|---|---|---|
| `admit` | Lot is clean or a resolved conflict winner. | Aggregated into holdings. |
| `reject_duplicate` | Redundant copy of a hard duplicate (all measures agree under one natural key). | Ignored; kept in `int_*` for audit. |
| `reject_fossil` | Frozen zero-valued side of a same-sync conflict (its live sibling is admitted with `zero_conflict_resolved`). | Ignored; kept in `int_*` for audit. |
| `quarantine` | Same-sync conflict with no single live row to pick. | Excluded from holdings; surfaces in `holdings_quarantine`. |

The full `data_quality_flags` vocabulary (lot-grain and holding-grain) is in the [`data_quality_flags` doc block](models/canonical/_docs.md); browse it in the generated site with `make docs-serve`.

#### Quarantine runbook

Rows landing in `holdings_quarantine` mean the classifier refused to guess. Every alert is actionable:

1. **Triage.** `holdings_quarantine` already carries the minimum triage columns (natural key, both investment_ids, quantity, conflicting gross amounts, family). Cross-check the transactions feed for the same account and holding (did a redemption explain the drop?), then look at the next sync (did one copy fossilize while the other moved?).
2. **Resolve.** One of three paths:
   - **Transient** — the next sync disambiguates on its own. No code change; the holding re-admits itself. Close the alert.
   - **Systematic** — a pattern emerges (e.g. the row with the newer `reference_datetime` is always the live one). Encode it as a new classification branch in `resolve_duplicate_investments`, then replay history with `make clean && make build` (the incremental-idempotency deliverable pays for exactly this).
   - **Provider defect** — neither feed explains it. Escalate to the institution with the `main_dbt_test__audit.dq_quarantine_empty` rows as evidence; the raw defect counts in the staging warn tests are the corroborating context.
3. **Meanwhile, the consumer is protected by construction.** Quarantined lots never reach `holdings_*`, so the wealth page under-counts one holding rather than fabricating a number. This is a deliberate product stance: when valuations conflict irreconcilably, a conservative omission beats a made-up value, and the omission is discoverable in the intermediate table.

### Materializations

Layer materializations follow dbt Labs' guidance — [staging as views](https://docs.getdbt.com/best-practices/how-we-structure/2-staging) and the general progression from the [materializations best practices](https://docs.getdbt.com/best-practices/materializations/1-guide-overview): *"Start with a view. When the view gets too long to query for end users, make it a table. When the table gets too long to build, build it incrementally."*

| Layer | Materialization | Why |
|-------|----------------|-----|
| staging | view | Cheap renames/casts read only by the next layer during builds; always fresh, no storage spent on models consumers never query. |
| canonical | incremental | Only records past the watermark (`ingested_at`, the arrival time) are processed each run; `unique_key (snapshot_id, investment_id)` makes re-deliveries an upsert and repeated runs idempotent. Late records still land because the watermark is on arrival, not event time. Replay after a transform fix: `dbt build --full-refresh`. |
| consumption | view | Fine at sample scale. At production concurrency (hundreds of analysts) hot models get promoted to table per the progression above. |

<img width="720" height="596" alt="bundles-branching-0b017c959921574bebad867191cd736b" src="https://github.com/user-attachments/assets/669a223a-aa0a-463a-882a-11d4abe01a05" />

## Data flow: two kinds of incremental

Incremental means two different things in this pipeline.

- **Loading raw**: picking up only the new arrival files. In production, Databricks Auto Loader watches the drop folder and appends what it hasn't seen before. Not implemented here: raw was handed to us as two static parquet files, so there are no "new arrivals". This is what the Databricks target ([Architecture](#architecture)) turns on.
- **Building canonical from raw**: reprocessing only the raw rows newer than the last canonical build (watermark on `ingested_at`), merged by key so re-runs are idempotent. **This is what §3.2 of the brief asks for, and what this repo ships.**


