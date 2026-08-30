{#
    Schema layout: every layer lands in its own schema on both targets.
    On Databricks the schema boundary is also the access boundary, so
    grants attach to schemas (consumers get consumption, nobody else
    reads staging or canonical). On DuckDB the same layout keeps one
    mental model across environments and stops the UI browser from
    flattening every layer into main.

    Custom schema names come from the +schema config in dbt_project.yml
    per layer; test failures land in dbt_test__audit through the same
    macro (dbt passes 'dbt_test__audit' as custom_schema_name).

    Future multi-workspace note: when dev moves to a shared Databricks
    workspace, extend the else branch to prefix the developer's own
    schema (target.schema is per-developer there), so two people running
    the same DAG never overwrite each other. Not built now: the single
    current workspace is prod only.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
