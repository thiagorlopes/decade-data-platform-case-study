{# Typed extraction of one JSON field, used by the staging models.

   Casting policy: json_extract_string already returns VARCHAR, so VARCHAR
   targets get no cast; everything else uses TRY_CAST so malformed provider
   values surface as NULL and are caught by the warn-severity not_null tests
   in _staging_quality.yml instead of crashing the view. `required` only
   documents what the OFB spec mandates. #}
{% macro json_field(column, prefix, path, type, required) -%}
{%- set expr = "json_extract_string(" ~ column ~ ", '" ~ prefix ~ path ~ "')" -%}
{%- if type == 'VARCHAR' -%}
{{ expr }}
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

{# Identity columns (cnpj, isin, ticker, product_name) feed the natural keys
   derived in the intermediate layer. A blank string passes IS NOT NULL and
   would silently fragment those keys, so staging normalizes '' to NULL: the
   warn-severity not_null tests then count blanks as the D1 defects they are. #}
{% macro identity_field(path, required=false) -%}
nullif(trim({{ payload_field(path, 'VARCHAR', required) }}), '')
{%- endmacro %}

{# --- within-record repairs (notebook 02), applied in the intermediate layer
   so the staging warn tests keep counting the raw defects. --- #}

{# Providers serialize CNPJs through a numeric type and pick up a decimal
   tail ('92894922000108.00'). Strip the tail, then demand exactly 14 digits;
   anything else degrades to NULL (regexp_extract returns '' on no match). #}
{% macro clean_cnpj(column) -%}
nullif(regexp_extract(regexp_replace({{ column }}, '\.[0-9]+$', ''), '^[0-9]{14}$'), '')
{%- endmacro %}

{# 'IPC-A' is the market's spelling of the OFB enum value 'IPCA'. #}
{% macro clean_indexer(column) -%}
CASE {{ column }} WHEN 'IPC-A' THEN 'IPCA' ELSE {{ column }} END
{%- endmacro %}

{# 0001-01-01 is .NET DateTime.MinValue: a missing date in a date costume. #}
{% macro desentinel_date(column) -%}
nullif({{ column }}, DATE '0001-01-01')
{%- endmacro %}
