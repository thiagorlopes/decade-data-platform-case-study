{#
    Schema layout per target.

    Databricks (prod): each layer lands in its own schema so the layer
    boundary is also the access boundary. Grants attach to schemas:
    consumers get consumption, nobody else reads staging or canonical.
    Test failures land in dbt_test__audit.

    DuckDB (dev): one flat schema. The local warehouse is one file per
    developer, so schema fan-out buys no isolation and would break the
    bare table names used by consumers/ and the notebooks.

    Future multi-workspace note: when dev moves to a shared Databricks
    workspace, extend the non-prod branch to prefix the developer's own
    schema (target.schema is per-developer there), so two people running
    the same DAG never overwrite each other. Not built now: the single
    current workspace is prod only.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.type == 'databricks' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
