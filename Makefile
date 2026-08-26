COMPOSE := docker compose
RUN := $(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) dbt
DBT_FLAGS := --project-dir . --profiles-dir .

.DEFAULT_GOAL := help
.PHONY: help install check parse build test shell clean docs docs-serve wealth

# One clean customer, one with resolved duplicates (merged_lots/id_handoff),
# one with a zero_flap glitch. Override: make wealth WEALTH_PARTIES=<uuid ...>
WEALTH_PARTIES := 9c39c85f-da56-58b6-850f-c86d0efd3299 \
                  9e22a589-e861-5dc1-899e-680bd197a983 \
                  11cc5703-4e06-5fb6-b1e9-c444f749d74c

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

wealth:  ## Export the wealth consumer output for the sample customers
	@for p in $(WEALTH_PARTIES); do \
	  mkdir -p consumers/wealth/output/$$p; \
	  for q in holdings movements; do \
	    $(COMPOSE) run --rm -T -u $(shell id -u):$(shell id -g) dbt \
	      duckdb -readonly warehouse.duckdb -csv \
	      -c "SET VARIABLE party_id = '$$p';" \
	      -c ".read consumers/wealth/$$q.sql" \
	      > consumers/wealth/output/$$p/$$q.csv; \
	    echo "wrote consumers/wealth/output/$$p/$$q.csv"; \
	  done; \
	done

docs:  ## Generate dbt docs (target/{manifest,catalog,index}.html)
	$(RUN) dbt docs generate $(DBT_FLAGS)

docs-serve: docs  ## Serve dbt docs at http://localhost:8080
	$(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) --service-ports dbt \
	  dbt docs serve $(DBT_FLAGS) --port 8080 --host 0.0.0.0 --no-browser

clean:  ## Remove warehouse and dbt artifacts (host side)
	rm -rf warehouse.duckdb warehouse.duckdb.wal target logs
