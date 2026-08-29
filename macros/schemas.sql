{#
    Schema layout per target.

    Databricks (prod): each layer lands in its own schema so the layer
    boundary is also the access boundary. Grants attach to schemas:
    consumers get decade_consumption, nobody else reads decade_staging
    or decade_canonical. Test failures land in decade_dbt_test__audit.

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
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
