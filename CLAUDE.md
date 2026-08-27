# Project conventions

## SQL style

- Table and subquery aliases are at least 3 characters and meaningful (`mov`, `dim`, `key_map`). Never single letters.
- SQL keywords uppercase, function names lowercase (`arg_max`, `coalesce`).
- CTE names are short and unprefixed; the filename is the namespace.
- Explicit column lists in every model's final select. `select *` is allowed only from a CTE defined in the same file.
- Column naming: snake_case; `_id` for identifiers, `_at` for timestamps, `_date` for dates, `is_`/`has_` prefixes for booleans.

## Layers

- Folders stay `canonical/` and `consumption/`; dbt prefixes (`stg_`, `int_`, `fct_`, `dim_`) go on model names only.
- Consumers under `consumers/` read the consumption layer only, never canonical or raw.
- Facts carry keys and measures; descriptive attributes live in dims. Join facts to `dim_holding` on `(product_family, holding_key)`.
- Every consumption model has an enforced contract in `contracts/_consumption.yml`. A schema change lands with its contract change in the same commit.
- The five product families fan out through a Jinja loop over one family list. Add a family by extending the list, not by copying a SELECT.

## Docs and comments

- Layer-wide narrative lives once, in the yml or macro header, not repeated across model files.
- Column descriptions reuse `doc()` blocks defined in `_docs.md`; define once, reference everywhere.
- Prose follows plain language: short sentences, active voice, no invented shorthand, no em dashes.

## Rules

@.claude/rules/readme.md
