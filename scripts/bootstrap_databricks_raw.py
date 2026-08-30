#!/usr/bin/env python3
"""Load the static raw parquet sample into Databricks Unity Catalog.

`models/_sources.yml` resolves to `{catalog}.raw_openfinance.{positions,transactions}`
on the prod target. This script makes those tables exist: schema, Volume,
upload, CTAS. Idempotent (safe to re-run each CI build) because the sample
is static; `CREATE OR REPLACE TABLE` rewrites the same bytes.

Env:
  DATABRICKS_HOST, DATABRICKS_TOKEN, DATABRICKS_HTTP_PATH (all required)
  DATABRICKS_CATALOG (defaults to `decade`)
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import StatementState

CATALOG = os.environ.get("DATABRICKS_CATALOG", "decade")
SCHEMA = "raw_openfinance"
VOLUME = "files"
FILES = {
    "positions": "data/raw/raw_positions.parquet",
    "transactions": "data/raw/raw_transactions.parquet",
}


def warehouse_id_from_http_path(http_path: str) -> str:
    # /sql/1.0/warehouses/<id>
    return http_path.rstrip("/").rsplit("/", 1)[-1]


def run_sql(client: WorkspaceClient, warehouse_id: str, sql: str) -> None:
    print(f"SQL: {sql}", flush=True)
    resp = client.statement_execution.execute_statement(
        statement=sql, warehouse_id=warehouse_id, wait_timeout="50s"
    )
    statement_id = resp.statement_id
    state = resp.status.state
    while state in (StatementState.PENDING, StatementState.RUNNING):
        time.sleep(2)
        resp = client.statement_execution.get_statement(statement_id)
        state = resp.status.state
    if state != StatementState.SUCCEEDED:
        raise RuntimeError(f"SQL failed ({state}): {resp.status.error}")


def main() -> int:
    http_path = os.environ["DATABRICKS_HTTP_PATH"]
    warehouse_id = warehouse_id_from_http_path(http_path)

    client = WorkspaceClient()
    run_sql(client, warehouse_id, f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{SCHEMA}")
    run_sql(
        client,
        warehouse_id,
        f"CREATE VOLUME IF NOT EXISTS {CATALOG}.{SCHEMA}.{VOLUME}",
    )

    for table, local_path in FILES.items():
        remote = f"/Volumes/{CATALOG}/{SCHEMA}/{VOLUME}/raw_{table}.parquet"
        print(f"Upload: {local_path} -> {remote}", flush=True)
        with Path(local_path).open("rb") as fh:
            client.files.upload(remote, fh, overwrite=True)
        run_sql(
            client,
            warehouse_id,
            f"CREATE OR REPLACE TABLE {CATALOG}.{SCHEMA}.{table} "
            f"AS SELECT * FROM read_files('{remote}', format => 'parquet')",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
