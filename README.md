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

- Python 3.10–3.12
- `make`, `git`
- (optional) DuckDB CLI for `make shell` — install with `curl -L https://install.duckdb.org | bash`

## Installation

```bash
make install
```

## Build

```bash
make check     # prove the wiring: lists the declared dbt sources
make build     # run all dbt models and tests
make shell     # open duckdb CLI on the warehouse (requires DuckDB CLI)
make help      # list all targets
```
