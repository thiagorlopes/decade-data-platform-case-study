COMPOSE := docker compose
RUN := $(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) dbt

.DEFAULT_GOAL := help
.PHONY: help install build run test docs refresh shell clean

help:  ## List targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z_-]+:.*##/ {printf "  \033[36m%-11s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

install:  ## Build the docker image (Python + dbt + duckdb CLI)
	$(COMPOSE) build

build:  ## Run models + tests
	$(RUN) dbt build

run:  ## Run models only (no tests)
	$(RUN) dbt run

test:  ## Run tests only
	$(RUN) dbt test

docs:  ## Regenerate docs catalog + serve at localhost:8080
	$(RUN) dbt docs generate
	$(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) --service-ports dbt \
	  dbt docs serve --port 8080 --host 0.0.0.0 --no-browser

refresh: build docs  ## Rebuild models + regenerate & serve docs

shell:  ## Open duckdb CLI on the warehouse
	$(RUN) duckdb warehouse.duckdb

clean:  ## Remove warehouse and dbt artifacts (host side)
	rm -rf warehouse.duckdb warehouse.duckdb.wal target logs
