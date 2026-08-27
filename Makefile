COMPOSE := docker compose
RUN := $(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) dbt

.DEFAULT_GOAL := help
.PHONY: help install build run test docs refresh shell ui clean wealth

# One clean customer, one with resolved duplicates (merged_lots/id_handoff),
# one with a zero_flap glitch. Override: make wealth WEALTH_PARTIES=<uuid ...>
WEALTH_PARTIES := 9c39c85f-da56-58b6-850f-c86d0efd3299 \
                  9e22a589-e861-5dc1-899e-680bd197a983 \
                  11cc5703-4e06-5fb6-b1e9-c444f749d74c

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

# WSL fallback: duckdb auto-opens via xdg-open when present; otherwise open
# the Windows default browser. `true` = no-op, the URL still prints.
OPEN := $(shell command -v xdg-open >/dev/null && echo true || command -v wslview || command -v explorer.exe || echo true)

ui:  ## Browse a snapshot of the warehouse at http://localhost:4213 (never locks builds)
	@command -v duckdb >/dev/null 2>&1 || { \
	  echo "duckdb CLI not found on the host. Install it: https://duckdb.org/install"; exit 1; }
	@test -f warehouse.duckdb || { echo "warehouse.duckdb missing. Run: make build"; exit 1; }
	@pkill -f '[d]uckdb -ui target/ui-snapshot.duckdb' 2>/dev/null; \
	  mkdir -p target && cp warehouse.duckdb target/ui-snapshot.duckdb
	@( sleep 1; $(OPEN) http://localhost:4213 >/dev/null 2>&1 ) &
	@echo "DuckDB UI on a warehouse snapshot: http://localhost:4213  (Ctrl+C to stop; re-run after builds for fresh data)"
	@duckdb -ui target/ui-snapshot.duckdb

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

clean:  ## Remove warehouse and dbt artifacts (host side)
	rm -rf warehouse.duckdb warehouse.duckdb.wal target logs
