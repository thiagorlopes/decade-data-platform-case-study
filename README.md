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

## Architecture

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native. The shape below is what production could look like, and the case is designed so the work could be transfered if considered appropriate by the Decade Data Team.

It follows the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices). The doc scales workspace count to team size: two workspaces (dev/prod) for teams up to five engineers, three (dev/staging/prod) beyond that.

Git is the source of truth ("if it isn't in version control, it doesn't exist"), and CI/CD gates promotion between environments. The diagram below is the doc's illustration of one such production deployment workflow at scale, included here for reference rather than as the shape this case commits to:

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

This case study solution ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any computer with no account required; the same dbt models run against Databricks when promoted. The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace through a profile change. That way, we would be able to close one tradeoff this shortcut carries: SQL dialect drift between the two engines.

<img width="720" height="596" alt="bundles-branching-0b017c959921574bebad867191cd736b" src="https://github.com/user-attachments/assets/669a223a-aa0a-463a-882a-11d4abe01a05" />

## Data flow: two kinds of incremental

Incremental means two different things in this pipeline.

- **Loading raw**: picking up only the new arrival files. In production, Databricks Auto Loader watches the drop folder and appends what it hasn't seen before. Not implemented here: raw was handed to us as two static parquet files, so there are no "new arrivals". This is what the Databricks target ([Architecture](#architecture)) turns on.
- **Building canonical from raw**: reprocessing only the raw rows newer than the last canonical build (watermark on `ingested_at`), merged by key so re-runs are idempotent. **This is what §3.2 of the brief asks for, and what this repo ships.**


