{# Typed extraction of one JSON field, used by the staging models.

   Casting policy: json_extract_string already returns VARCHAR, so VARCHAR
   targets get no cast; fields the OFB spec marks `required` use CAST so
   malformed data fails the build; optional fields use TRY_CAST and surface
   as NULL. #}
{% macro json_field(column, prefix, path, type, required) -%}
{%- set expr = "json_extract_string(" ~ column ~ ", '" ~ prefix ~ path ~ "')" -%}
{%- if type == 'VARCHAR' -%}
{{ expr }}
{%- elif required -%}
CAST({{ expr }} AS {{ type }})
{%- else -%}
TRY_CAST({{ expr }} AS {{ type }})
{%- endif -%}
{%- endmacro %}

{# positions payload_json carries the API response envelope, hence $.data. #}
{% macro payload_field(path, type, required=false) -%}
{{ json_field('payload_json', '$.data.', path, type, required) }}
{%- endmacro %}

{# transaction_json is flat (no $.data wrapper). #}
{% macro txn_field(path, type, required=false) -%}
{{ json_field('transaction_json', '$.', path, type, required) }}
{%- endmacro %}
