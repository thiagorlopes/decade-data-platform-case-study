# Contracts

The executable contract artifacts are dbt `schema.yml` files; `contracts/` is declared as a dbt model path, so dbt parses and enforces them from here.

- [`_consumption.yml`](_consumption.yml): the output contract for `fct_holdings` and `fct_movements` (`contract: enforced`, so the build fails on any column or type drift), plus grain and enum tests at error severity.

The per-family canonical contracts live next to their models in [`models/canonical/_canonical.yml`](../models/canonical/_canonical.yml), and the within-record quality rules (the warn-severity DETECT tier) in [`models/canonical/staging/_staging_quality.yml`](../models/canonical/staging/_staging_quality.yml).
