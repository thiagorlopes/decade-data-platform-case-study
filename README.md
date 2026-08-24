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

During past interviews, it became apparent that Decade uses Databricks extensively for its data workflows. For that reason, the chosen architecture in this case is based on this premise. The idea is that learnings from this case could be extended to production. 

The destination architecture is based on [Developer best practices on Databricks](https://docs.databricks.com/gcp/en/developers/best-practices) Databricks official documentation. 

<img width="720" height="596" alt="image" src="https://github.com/user-attachments/assets/73081923-a49f-4392-99d1-86f3e6cad1c1" />

However, we won't start from the get go with databricks. The case needs to be reproducible. So, we are starting with this simplified architecture.

<img width="720" height="596" alt="bundles-branching-0b017c959921574bebad867191cd736b" src="https://github.com/user-attachments/assets/669a223a-aa0a-463a-882a-11d4abe01a05" />


