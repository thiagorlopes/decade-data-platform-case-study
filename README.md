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

Decade runs its data workflows on Databricks, so the target architecture for this case is Databricks-native — the shape below is what production looks like, and the case is designed so the work transfers directly.

It follows the Databricks [developer best practices](https://docs.databricks.com/gcp/en/developers/best-practices). The doc scales workspace count to team size — two workspaces (dev/prod) for teams up to five engineers, three (dev/staging/prod) beyond that — with git as the source of truth ("if it isn't in version control, it doesn't exist") and CI/CD gating promotion between environments. The diagram below is the doc's illustration of one such production deployment workflow at scale, included here for reference rather than as the shape this case commits to:

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

The case study ships a two-environment slice of that target: **DuckDB for dev, Databricks for prod**. DuckDB keeps the pipeline reproducible on any laptop with no account required; the same dbt models run against Databricks when promoted. The upgrade path to the full target is replacing DuckDB with a Databricks dev workspace — a profile change, not a rewrite — which also closes the one tradeoff this shortcut carries: SQL dialect drift between the two engines.

<img width="720" height="596" alt="bundles-branching-0b017c959921574bebad867191cd736b" src="https://github.com/user-attachments/assets/669a223a-aa0a-463a-882a-11d4abe01a05" />


