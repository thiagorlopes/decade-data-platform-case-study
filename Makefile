COMPOSE := docker compose
RUN := $(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) dbt
DBT_FLAGS := --project-dir . --profiles-dir .

.DEFAULT_GOAL := help
.PHONY: help install check parse build test shell clean docs docs-serve

help:  ## List targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z_-]+:.*##/ {printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

install:  ## Build the docker image (Python + dbt + duckdb CLI)
	$(COMPOSE) build

check:  ## Prove the wiring: list declared dbt sources
	$(RUN) dbt ls $(DBT_FLAGS) --resource-type source

parse:  ## Validate dbt project config
	$(RUN) dbt parse $(DBT_FLAGS)

build:  ## Run all dbt models and tests
	$(RUN) dbt build $(DBT_FLAGS)

test:  ## Run dbt tests only
	$(RUN) dbt test $(DBT_FLAGS)

shell:  ## Open duckdb CLI on the warehouse
	$(RUN) duckdb warehouse.duckdb

docs:  ## Generate dbt docs (target/{manifest,catalog,index}.html)
	$(RUN) dbt docs generate $(DBT_FLAGS)

docs-serve: docs  ## Serve dbt docs at http://localhost:8080
	$(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) --service-ports dbt \
	  dbt docs serve $(DBT_FLAGS) --port 8080 --host 0.0.0.0 --no-browser

clean:  ## Remove warehouse and dbt artifacts (host side)
	rm -rf warehouse.duckdb warehouse.duckdb.wal target logs
