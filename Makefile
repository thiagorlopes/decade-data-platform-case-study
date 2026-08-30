COMPOSE := docker compose
RUN := $(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) dbt

.DEFAULT_GOAL := help
.PHONY: help install deps build run test docs refresh consumers shell ui clean

help:  ## List targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z_-]+:.*##/ {printf "  \033[36m%-11s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

install:  ## Build the docker image (Python + dbt + duckdb CLI)
	$(COMPOSE) build

# dbt_packages/ is gitignored, so a fresh clone has none. Every target that
# compiles the project depends on this one. Versions come from package-lock.yml.
deps:  ## Install dbt packages into dbt_packages/
	$(RUN) dbt deps

build: deps  ## Run models + tests
	$(RUN) dbt build

run: deps  ## Run models only (no tests)
	$(RUN) dbt run

test: deps  ## Run tests only
	$(RUN) dbt test

docs: deps  ## Regenerate docs catalog + serve at localhost:8080 (safe to run with `make ui`)
	$(RUN) dbt docs generate --target read_only
	$(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) --service-ports dbt \
	  dbt docs serve --port 8080 --host 0.0.0.0 --no-browser

refresh: build docs  ## Rebuild models + regenerate & serve docs

consumers:  ## Regenerate the wealth output CSVs from the committed queries
	$(RUN) python consumers/wealth/export_output.py

shell:  ## Open duckdb CLI on the warehouse
	@test -f warehouse.duckdb || { echo "warehouse.duckdb missing. Run: make build"; exit 1; }
	$(RUN) duckdb warehouse.duckdb

ui:  ## Browse warehouse.duckdb read-only at http://localhost:4213 (close before builds)
	@test -f warehouse.duckdb || { echo "warehouse.duckdb missing. Run: make build"; exit 1; }
	@( i=0; until curl -s -o /dev/null http://localhost:4213 || [ $$i -ge 60 ]; do i=$$((i+1)); sleep 0.5; done; \
	  xdg-open http://localhost:4213 || open http://localhost:4213 || explorer.exe "http://localhost:4213" ) >/dev/null 2>&1 &
	$(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) -e HOME=/workspace -p 4213:4214 dbt \
	  sh -c "socat TCP-LISTEN:4214,fork,reuseaddr 'TCP6:[::1]:4213' & exec duckdb -readonly warehouse.duckdb -ui"

clean:  ## Remove warehouse and dbt artifacts (host side)
	rm -rf warehouse.duckdb warehouse.duckdb.wal target logs
