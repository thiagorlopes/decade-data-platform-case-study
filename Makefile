PY := .venv/bin/python
DBT := .venv/bin/dbt
DBT_FLAGS := --project-dir . --profiles-dir .

.DEFAULT_GOAL := help
.PHONY: help install check parse build test shell clean

help:  ## List targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z_-]+:.*##/ {printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

install:  ## Create venv and install dependencies
	python3 -m venv .venv
	$(PY) -m pip install -r requirements.txt

check:  ## Prove the wiring: list declared dbt sources
	$(DBT) ls $(DBT_FLAGS) --resource-type source

parse:  ## Validate dbt project config
	$(DBT) parse $(DBT_FLAGS)

build:  ## Run all dbt models and tests
	$(DBT) build $(DBT_FLAGS)

test:  ## Run dbt tests only
	$(DBT) test $(DBT_FLAGS)

shell:  ## Open duckdb CLI on the warehouse
	duckdb warehouse.duckdb

clean:  ## Remove warehouse and dbt artifacts
	rm -rf warehouse.duckdb warehouse.duckdb.wal target logs
