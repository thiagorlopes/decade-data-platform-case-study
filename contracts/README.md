# Contracts

The executable contract artifacts are dbt `schema.yml` files. dbt only executes them from inside `models/`, so the files live there and this directory links to them to avoid drift:

- [`_consumption.yml`](_consumption.yml): the output contract for `fct_holdings` and `fct_movements` (`contract: enforced`, so the build fails on any column or type drift), plus grain and enum tests at error severity.
- [`_canonical.yml`](_canonical.yml): the per-family canonical models, for consumers that need family-specific columns.

Within-record quality rules (the warn-severity DETECT tier) live in `models/canonical/staging/_staging_quality.yml`.
