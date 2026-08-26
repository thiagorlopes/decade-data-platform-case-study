# Contracts

The executable contract artifacts are dbt `schema.yml` files; `contracts/` is declared as a dbt model path, so dbt parses and enforces them from here.

- [`_consumption.yml`](_consumption.yml): the output contract for `fct_holdings` and `fct_movements`, plus grain and enum tests at error severity.

## What `contract: enforced` guarantees

On every `dbt build`, before materializing, dbt compares the compiled output of `fct_holdings` and `fct_movements` against the columns declared in `_consumption.yml`. Any drift kills the build, so the bad table never exists for a consumer to read:

- a column is **renamed or dropped**: build fails (missing from the contract's column set)
- a column's **type changes** (e.g. an amount silently becomes `varchar`): build fails
- a **new column appears** without being declared: build fails

The consequence for consumers: whatever `make build` produced is guaranteed to match this file. A team can develop against the declared columns and types without talking to the platform team, and a platform-side refactor can never break a consumer silently; it either preserves the contract or is forced to change this file in the same PR, which is the review signal.

The per-family canonical contracts live next to their models in [`models/canonical/_canonical.yml`](../models/canonical/_canonical.yml), and the within-record quality rules (the warn-severity DETECT tier) in [`models/canonical/staging/_staging_quality.yml`](../models/canonical/staging/_staging_quality.yml).
