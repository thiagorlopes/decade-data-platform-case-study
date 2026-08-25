# Decade Data Platform Case Study

This repository contains Thiago Portugues's solution for the hiring process at Decade.

## Table of Contents

**[General information](#general-information)**<br>
**[Prerequisites](#prerequisites)**<br>
**[Installation](#installation)**<br>
**[Build](#build)**<br>
**[Data quality](#data-quality-detect-resolve-guarantee)**<br>

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

## Build

```bash
make check       # prove the wiring: lists the declared dbt sources
make build       # run all dbt models and tests
make shell       # open duckdb CLI on the warehouse (inside container)
make help        # list all targets
```

## Target Architecture & Environments

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native. The shape below is what production could look like, and the case is designed so the work could be transfered if considered appropriate by the Decade Data Team.

It follows the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices). The doc scales workspace count to team size: two workspaces (dev/prod) for teams up to five engineers, three (dev/staging/prod) beyond that.

Git is the source of truth ("if it isn't in version control, it doesn't exist"), and CI/CD gates promotion between environments. The diagram below is the doc's illustration of one such production deployment workflow at scale, included here for reference rather than as the shape this case commits to:

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

This case study solution ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any computer with no account required; the same dbt models run against Databricks when promoted. The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace through a profile change. That way, we would be able to close one tradeoff this shortcut carries: SQL dialect drift between the two engines.

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

## Data quality: detect, resolve, guarantee

Provider defects (§2.2) split into within-record (a required field empty, a value in the wrong form, a legal value outside its enum, a cross-field contradiction) and across-record (the same holding under two ids, holdings that freeze under a new id, a zero-then-nonzero valuation). The pipeline splits their handling across three layers so each layer has one job:

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
  │   build DIES: bug is ours  │   │   build dq_flags[]      │   │   build DIES: our        │
  ├────────────────────────────┤   │     for what cannot be  │   │     resolution failed    │
  │ payload (theirs) → WARN    │   │     repaired            │   ├──────────────────────────┤
  │   not_null required        │   │   dedupe across records │   │ dq_flags column → WARN   │
  │   format regex             │   └─────────────────────────┘   │   count stays visible    │
  │   accepted_values          │                                 └──────────────────────────┘
  │   cross-field rules        │
  │   store_failures: true     │
  └────────────────────────────┘
              │
              ▼
   main_dbt_test__audit.*  ◀── provider defect ledger (row-level, queryable)
```

| Owner                           | Layer | Severity              | On failure                                       |
|---------------------------------|-------|-----------------------|--------------------------------------------------|
| Us (envelope: ids, grain)       | stg   | error                 | Build halts. Fix ingestion.                      |
| Provider (payload content)      | stg   | warn + store_failures | Build continues. Rows land in audit ledger.      |
| Us (resolution logic)           | fct   | error                 | Build halts. `int_` transform is buggy.          |
| Provider (unrepairable rows)    | fct   | warn via `dq_flags`   | Row admitted with a flag. Consumer decides.      |

How a consumer finds out which happened (§2.2's closing question):

- **Row-level**: `dq_flags` column on the fct table (`['missing:purchase_date']`, etc.).
- **Run-level**: `main_dbt_test__audit.*` — one row per warned row, per test, per run.
- **Contract-level**: `contracts/` (symlink to `_canonical.yml`) — what fct promises is *never* wrong, enforced as error.

**State today**: the DETECT column is in (`models/canonical/staging/_staging_quality.yml`, notebook `06_within_record_defects.ipynb`). RESOLVE and GUARANTEE are the next models to land against this shape.

