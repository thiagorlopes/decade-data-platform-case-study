COMPOSE := docker compose
RUN := $(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) dbt

.DEFAULT_GOAL := help
.PHONY: help install build run test docs refresh shell ui clean

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

ui:  ## Browse warehouse.duckdb read-only at http://localhost:4213 (close before builds)
	@test -f warehouse.duckdb || { echo "warehouse.duckdb missing. Run: make build"; exit 1; }
	@( i=0; until curl -s -o /dev/null http://localhost:4213 || [ $$i -ge 60 ]; do i=$$((i+1)); sleep 0.5; done; \
	  xdg-open http://localhost:4213 || open http://localhost:4213 || explorer.exe "http://localhost:4213" ) >/dev/null 2>&1 &
	$(COMPOSE) run --rm -u $(shell id -u):$(shell id -g) -e HOME=/workspace -p 4213:4214 dbt \
	  sh -c "socat TCP-LISTEN:4214,fork,reuseaddr 'TCP6:[::1]:4213' & exec duckdb -ui -cmd \"ATTACH 'warehouse.duckdb' AS warehouse (READ_ONLY);\""

clean:  ## Remove warehouse and dbt artifacts (host side)
	rm -rf warehouse.duckdb warehouse.duckdb.wal target logs
