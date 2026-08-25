# Column doc blocks shared across staging, intermediate and consumption.
# Descriptions and enum values come from the Open Finance Brasil investment API specs
# (see the header of each staging model for the exact spec file and line anchors).

{% docs ofb_movement_type %}
Direction of the movement from the investment's point of view (spec field `type`).
Spec convention: interest payments and amortizations are recorded as `SAIDA`.
Enum: `ENTRADA`, `SAIDA`.
{% enddocs %}

{% docs ofb_transaction_type_additional_info %}
Free-text description of the movement (spec field `transactionTypeAdditionalInfo`).
Spec rule: filled when `transaction_type = 'OUTROS'`, i.e. the movement is outside the enum domain.
{% enddocs %}

{% docs ofb_transaction_type__bank_fixed_incomes %}
Movement type (spec field `transactionType`).
Enum: `APLICACAO`, `RESGATE`, `CANCELAMENTO`, `VENCIMENTO`, `PAGAMENTO_JUROS`, `AMORTIZACAO`, `TRANSFERENCIA_TITULARIDADE`, `TRANSFERENCIA_CUSTODIA`, `OUTROS`.
When `OUTROS`, `transaction_type_additional_info` carries the description.
{% enddocs %}

{% docs ofb_transaction_type__credit_fixed_incomes %}
Movement type (spec field `transactionType`).
Enum: `COMPRA`, `VENDA`, `CANCELAMENTO`, `VENCIMENTO`, `PAGAMENTO_JUROS`, `AMORTIZACAO`, `PREMIO`, `TRANSFERENCIA_TITULARIDADE`, `TRANSFERENCIA_CUSTODIA`, `MULTA`, `MORA`, `OUTROS`.
When `OUTROS`, `transaction_type_additional_info` carries the description.
{% enddocs %}

{% docs ofb_transaction_type__funds %}
Movement type (spec field `transactionType`).
Enum: `APLICACAO`, `RESGATE`, `AMORTIZACAO`, `COME_COTAS`, `TRANSFERENCIA_COTAS`, `OUTROS`.
When `OUTROS`, `transaction_type_additional_info` carries the description.
{% enddocs %}

{% docs ofb_transaction_type__treasure_titles %}
Movement type (spec field `transactionType`).
Enum: `COMPRA`, `VENDA`, `CANCELAMENTO`, `VENCIMENTO`, `PAGAMENTO_JUROS`, `AMORTIZACAO`, `TRANSFERENCIA_TITULARIDADE`, `TRANSFERENCIA_CUSTODIA`, `OUTROS`.
When `OUTROS`, `transaction_type_additional_info` carries the description.
{% enddocs %}

{% docs ofb_transaction_type__variable_incomes %}
Movement type (spec field `transactionType`).
Enum: `COMPRA`, `VENDA`, `DIVIDENDOS`, `JCP`, `ALUGUEIS`, `TRANSFERENCIA_CUSTODIA`, `TRANSFERENCIA_TITULARIDADE`, `OUTROS`.
When `OUTROS`, `transaction_type_additional_info` carries the description.
{% enddocs %}

{% docs ofb_indexer %}
Reference index used to correct the asset's yield (spec field `remuneration.indexer`).
Enum: `CDI`, `DI`, `TR`, `IPCA`, `IGP_M`, `IGP_DI`, `INPC`, `BCP`, `TLC`, `SELIC`, `PRE_FIXADO`, `OUTROS`.
`PRE_FIXADO` pairs with `pre_fixed_rate`; the others pair with `post_fixed_indexer_percentage`.
{% enddocs %}

{% docs ofb_product_type__bank_fixed_incomes %}
Asset type (spec field `investmentType`). Enum: `CDB`, `RDB`, `LCI`, `LCA`.
{% enddocs %}

{% docs ofb_product_type__credit_fixed_incomes %}
Asset type (spec field `investmentType`). Enum: `DEBENTURES`, `CRI`, `CRA`.
{% enddocs %}

{% docs ofb_tax_exempt %}
Whether the product is tax-incentivized, i.e. income-tax exempt (spec field `taxExemptProduct`).
Enum: `SIM`, `NAO`.
{% enddocs %}

{% docs ofb_anbima_category %}
Fund classification per ANBIMA Deliberation 77 (spec field `anbimaCategory`).
Enum: `RENDA_FIXA`, `ACOES`, `MULTIMERCADO`, `CAMBIAL`.
{% enddocs %}
