# Decade Data Platform Case Study

This repository contains Thiago Portugues's solution for the hiring process at Decade.

## Table of Contents

**[General information](#general-information)**<br>
**[Prerequisites](#prerequisites)**<br>
**[Installation](#installation)**<br>
**[Build](#build)**<br>

## General Information

Lorem ipsum

## Prerequisites

- Docker Engine + Docker Compose v2
- `make`, `git`

Everything the pipeline needs (Python, dbt, DuckDB CLI) is bundled inside the image. No host-side Python setup required.

Notebook exploration (`notebooks/`) uses jupyterlab + pandas + pyarrow. Those are dev-only and kept out of the image — install them into a local venv if you need to re-run the notebook:

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

## Architecture

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native. The shape below is what production could look like, and the case is designed so the work could be transfered if considered appropriate by the Decade Data Team.

It follows the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices). The doc scales workspace count to team size: two workspaces (dev/prod) for teams up to five engineers, three (dev/staging/prod) beyond that, with git as the source of truth ("if it isn't in version control, it doesn't exist") and CI/CD gating promotion between environments. The diagram below is the doc's illustration of one such production deployment workflow at scale, included here for reference rather than as the shape this case commits to:

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

This case study solution ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any computer with no account required; the same dbt models run against Databricks when promoted. The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace through a profile change. That way, we would be able to close one tradeoff this shortcut carries: SQL dialect drift between the two engines.

<img width="720" height="596" alt="bundles-branching-0b017c959921574bebad867191cd736b" src="https://github.com/user-attachments/assets/669a223a-aa0a-463a-882a-11d4abe01a05" />

## Data flow — where "incremental" applies

Two independent incremental mechanisms live in this pipeline. Do not conflate them:

- **Ingestion tier** — *"which arrival files have I loaded into raw?"* File-level, checkpoint-tracked. **Out of scope for this dev slice**: raw was delivered as static parquet files, so there is no arrival stream to demonstrate. **In scope for the target architecture** described in [Architecture](#architecture): promoting to the Databricks dev workspace turns this on as first-class — Auto Loader appends new files into a Hive-partitioned Bronze table (`data/raw/{table}/ingestion_date=YYYY-MM-DD/*.parquet`), tracked by its own checkpoint state. Sources yml gains `hive_partitioning=true` on the `external_location`; canonical models are unchanged.
- **Processing tier** — *"which arrival times have I already built canonical for?"* SQL watermark on `ingested_at`, dbt `is_incremental()` filter, MERGE on `unique_key`. **This is what §3.2 of the brief asks for, and what this repo ships.** DuckDB's parquet reader handles per-row-group predicate pushdown against the flat raw file, so the processing-tier incremental doesn't pay full-scan cost even without hive partitioning — the same mechanism Databricks/Spark uses on Delta files at production scale.


