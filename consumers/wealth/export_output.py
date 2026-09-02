"""Regenerate the committed wealth output under consumers/wealth/output/.

Runs holdings.sql and movements.sql against decade.duckdb, scoped to the
three sample customers, and writes one CSV per query per customer. Run it
with `make consumers` after `make build`, so the committed output always
matches the committed queries.
"""

import sys
from pathlib import Path

import duckdb

SAMPLE_PARTIES = [
    "9c39c85f-da56-58b6-850f-c86d0efd3299",
    "9e22a589-e861-5dc1-899e-680bd197a983",
    "11cc5703-4e06-5fb6-b1e9-c444f749d74c",
]

WEALTH_DIR = Path(__file__).resolve().parent
WAREHOUSE = WEALTH_DIR.parent.parent / "decade.duckdb"

# The committed queries return every customer. To scope one query to one
# customer, insert a WHERE clause at a stable anchor line: the final QUALIFY
# in holdings.sql, the final ORDER BY in movements.sql. The anchor must
# appear exactly once, so a query edit that moves it fails loudly here
# instead of exporting the wrong rows.
EXPORTS = [
    ("holdings.sql", "holdings.csv", "QUALIFY dense_rank() OVER (", "WHERE fct.party_id = '{party_id}'"),
    ("movements.sql", "movements.csv", "ORDER BY mov.transaction_date", "WHERE mov.party_id = '{party_id}'"),
    ("net_worth_over_time.sql", "net_worth_over_time.csv", "GROUP BY mov.party_id", "AND mov.party_id = '{party_id}'"),
]


def scoped_query(sql_text, anchor, where_clause, party_id):
    if sql_text.count(anchor) != 1:
        sys.exit(f"anchor {anchor!r} not found exactly once; update EXPORTS to match the query")
    where_line = where_clause.format(party_id=party_id) + "\n"
    return sql_text.replace(anchor, where_line + anchor).rstrip().rstrip(";")


def main():
    if not WAREHOUSE.exists():
        sys.exit("decade.duckdb missing. Run: make build")
    con = duckdb.connect(str(WAREHOUSE), read_only=True)
    for party_id in SAMPLE_PARTIES:
        party_dir = WEALTH_DIR / "output" / party_id
        party_dir.mkdir(parents=True, exist_ok=True)
        for sql_file, csv_file, anchor, where_clause in EXPORTS:
            sql_text = (WEALTH_DIR / sql_file).read_text()
            query = scoped_query(sql_text, anchor, where_clause, party_id)
            # Write to a temp file first, so an empty result never
            # clobbers the committed CSV.
            target = party_dir / csv_file
            tmp_target = party_dir / (csv_file + ".tmp")
            rows = con.execute(
                f"COPY ({query}) TO '{tmp_target}' (HEADER, NULL 'NULL')"
            ).fetchone()[0]
            if rows == 0:
                tmp_target.unlink()
                sys.exit(f"{target} came out empty; is {party_id} still in the sample?")
            tmp_target.replace(target)
            print(f"{target.relative_to(WEALTH_DIR.parent.parent)}: {rows} rows")


if __name__ == "__main__":
    main()
