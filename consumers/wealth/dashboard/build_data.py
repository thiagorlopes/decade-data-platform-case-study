"""Build data.js for the wealth dashboard.

Reads the committed consumer CSVs under consumers/wealth/output/ and embeds
them as one JS object, so index.html opens from file:// with no server and
no CSV parsing in the browser. Rerun after `make consumers`.
"""

from pathlib import Path
import json

import duckdb

WEALTH_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = WEALTH_DIR / "output"
TARGET = Path(__file__).resolve().parent / "data.js"


def rows(con, path):
    res = con.execute("SELECT * FROM read_csv_auto(?, nullstr='NULL')", [str(path)])
    cols = [col[0] for col in res.description]
    return [dict(zip(cols, row)) for row in res.fetchall()]


def main():
    con = duckdb.connect()
    parties = {}
    for party_dir in sorted(OUTPUT_DIR.iterdir()):
        if not party_dir.is_dir():
            continue
        holdings = rows(con, party_dir / "holdings.csv")
        series = rows(con, party_dir / "net_worth_over_time.csv")
        parties[party_dir.name] = {
            "valuation_date": max(str(hld["reference_date"]) for hld in holdings),
            "series": [
                {"date": str(pnt["month_date"]), "value": pnt["cumulative_net_flow"]}
                for pnt in series
            ],
            "holdings": [
                {
                    "name": hld["holding_name"],
                    "institution": hld["institution_name"],
                    "family": hld["product_family"],
                    "key": hld["holding_key"],
                    "value": hld["gross_amount"],
                    "reported": hld["gross_amount_reported"],
                    "flags": hld["data_quality_flags"],
                }
                for hld in holdings
            ],
        }
    TARGET.write_text(
        "window.DECADE_DATA = " + json.dumps(parties, ensure_ascii=False) + ";\n"
    )
    print(f"{TARGET}: {len(parties)} parties")


if __name__ == "__main__":
    main()
