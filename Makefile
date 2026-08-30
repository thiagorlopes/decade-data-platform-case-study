COMPOSE := docker compose
RUN := $(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) dbt

export DOCKER_UID := $(shell id -u)
export DOCKER_GID := $(shell id -g)

.DEFAULT_GOAL := help
.PHONY: help install deps build run test docs refresh consumers shell ui ui-stop clean

# DuckDB is single-writer: targets that write decade.duckdb pause the UI
# service to release its read lock, then start it again so an open browser
# tab reconnects on its own.
define with_write_lock
@ui_up=$$($(COMPOSE) ps -q --status running ui 2>/dev/null); \
[ -z "$$ui_up" ] || $(COMPOSE) stop ui; \
$(1); rc=$$?; \
[ -z "$$ui_up" ] || $(COMPOSE) start ui; \
exit $$rc
endef

help:  ## List targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z_-]+:.*##/ {printf "  \033[36m%-11s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

install:  ## Build the docker image (Python + dbt + duckdb CLI)
	$(COMPOSE) build

# dbt_packages/ is gitignored, so a fresh clone has none. Every target that
# compiles the project depends on this one. Versions come from package-lock.yml.
deps:  ## Install dbt packages into dbt_packages/
	$(RUN) dbt deps

build: deps  ## Run models + tests (pauses the UI while it holds the write lock)
	$(call with_write_lock,$(RUN) dbt build)

run: deps  ## Run models only (no tests)
	$(call with_write_lock,$(RUN) dbt run)

test: deps  ## Run tests only
	$(call with_write_lock,$(RUN) dbt test)

docs: deps  ## Regenerate docs catalog + serve at localhost:8080 (safe to run with `make ui`)
	$(RUN) dbt docs generate --target read_only
	$(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) --service-ports dbt \
	  dbt docs serve --port 8080 --host 0.0.0.0 --no-browser

refresh: build docs  ## Rebuild models + regenerate & serve docs

consumers:  ## Regenerate the wealth output CSVs from the committed queries
	$(RUN) python consumers/wealth/export_output.py

shell:  ## Open duckdb CLI on the warehouse (read-write; pauses the UI)
	@test -f decade.duckdb || { echo "decade.duckdb missing. Run: make build"; exit 1; }
	$(call with_write_lock,$(RUN) duckdb decade.duckdb)

ui:  ## Browse decade.duckdb read-only at http://localhost:4213 (stays up until `make ui-stop`)
	@test -f decade.duckdb || { echo "decade.duckdb missing. Run: make build"; exit 1; }
	$(COMPOSE) up -d ui
	@i=0; until curl -s -o /dev/null http://localhost:4213 || [ $$i -ge 60 ]; do i=$$((i+1)); sleep 0.5; done
	@( xdg-open http://localhost:4213 || open http://localhost:4213 || explorer.exe "http://localhost:4213" ) >/dev/null 2>&1 || true
	@echo "DuckDB UI at http://localhost:4213 (query with full paths: decade.consumption.fct_holdings). Stop with: make ui-stop"

ui-stop:  ## Stop the DuckDB UI container
	$(COMPOSE) rm -sf ui

clean: ui-stop  ## Remove warehouse and dbt artifacts (host side)
	rm -rf decade.duckdb decade.duckdb.wal target logs
