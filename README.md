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

Everything else (Python, dbt, DuckDB CLI) is bundled inside the image. No host-side Python setup required.

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
