# Project conventions

## SQL style

- Table and subquery aliases are at least 3 characters and meaningful (`mov`, `dim`, `key_map`). Never single letters.
- SQL keywords uppercase, function names lowercase (`arg_max`, `coalesce`).
- CTE names are short and unprefixed; the filename is the namespace.
- Explicit column lists in every model's final select. `select *` is allowed only from a CTE defined in the same file.
- Column naming: snake_case; `_id` for identifiers, `_at` for timestamps, `_date` for dates, `is_`/`has_` prefixes for booleans.

## Layers

- Top-level split: `staging/` (prefix `stg_`), `canonical/` (prefix `int_`, in its `intermediate/` folder), and `consumption/` (`fct_` and `dim_`).
- Staging is 1:1 with a source table. Rename and cast only, no joins.
- Intermediate composes staging (or other intermediates) with business logic.
- Consumption exposes contracted `fct_` and `dim_` for consumers.
- Refs stay in-layer or up: `stg_` refs one `source()`, `int_` refs `stg_` or `int_`, `fct_`/`dim_` refs `int_` (or `stg_` if the shape is already right).
- Consumers under `consumers/` read the consumption layer only, never canonical or raw.
- Facts carry keys and measures; descriptive attributes live in dims. Join facts to `dim_holding` on `(product_family, holding_key)`.
- Every consumption model has an enforced contract in `contracts/_consumption.yml`. A schema change lands with its contract change in the same commit.
- The five product families fan out through a Jinja loop over one family list. Add a family by extending the list, not by copying a SELECT.

## Docs and comments

- Layer-wide narrative lives once, in the yml or macro header, not repeated across model files.
- Column descriptions reuse `doc()` blocks defined in `_docs.md`; define once, reference everywhere.
- Prose follows plain language: short sentences, active voice, no invented shorthand, no em dashes.

## dbt commands

- Use `dbt build`, not `dbt run`. Build runs tests in the same step and catches data issues immediately.
- Always pass a selector and quiet flags: `dbt build --select <model> --quiet --warn-error-options '{"error": ["NoNodesForSelectionCriteria"]}'`.
- Never run the whole project without the user asking for it. Preview results with `dbt show --select <model> --limit 10`.
