{# Shared pieces of the canonical position and transaction models. #}

{% macro payload_field(side, path, type) -%}
TRY_CAST(json_extract_string({{ side }}.payload_json, '$.data.{{ path }}') AS {{ type }})
{%- endmacro %}

{# FULL JOIN because some lots arrive with balances only (no detail payload). #}
{% macro from_positions(family) -%}
FROM (SELECT * FROM {{ source('raw_openfinance', 'positions') }}
      WHERE investment_type = '{{ family }}' AND payload_kind = 'detail') AS det
FULL JOIN (SELECT * FROM {{ source('raw_openfinance', 'positions') }}
      WHERE investment_type = '{{ family }}' AND payload_kind = 'balances') AS bal
USING (snapshot_id, investment_id)
{%- endmacro %}

{# transaction_json is flat (no $.data wrapper) and needs no join. #}
{% macro txn_field(path, type) -%}
TRY_CAST(json_extract_string(transaction_json, '$.{{ path }}') AS {{ type }})
{%- endmacro %}

{% macro from_transactions(family) -%}
FROM {{ source('raw_openfinance', 'transactions') }}
WHERE investment_type = '{{ family }}'
{%- endmacro %}
