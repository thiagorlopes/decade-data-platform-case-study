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

{% docs ofb_investment_id %}
Unique identifier of the customer-product relationship (spec field `investmentId`),
immutable within the transmitting institution.
{% enddocs %}

{% docs ofb_transaction_id %}
Unique identifier assigned by the institution to individualize the movement (spec field `transactionId`).
{% enddocs %}

{% docs ofb_transaction_date %}
Date of the movement (spec field `transactionDate`).
{% enddocs %}

{% docs ofb_transaction_unit_price %}
Gross unit price traded in the movement (spec field `transactionUnitPrice.amount`).
For ownership/custody transfers, the spec mandates the acquisition unit price of the security.
{% enddocs %}

{% docs ofb_transaction_quantity %}
Quantity of securities involved in the movement (spec field `transactionQuantity`).
{% enddocs %}

{% docs ofb_transaction_gross_amount %}
Gross value of the movement: unit price x quantity (spec field `transactionGrossValue.amount`).
{% enddocs %}

{% docs ofb_transaction_net_amount %}
Net value of the movement, after taxes (spec field `transactionNetValue.amount`).
{% enddocs %}

{% docs ofb_income_tax_amount %}
Income tax (IR) on the movement (spec field `incomeTax.amount`).
{% enddocs %}

{% docs ofb_income_tax_provision %}
Provision for income tax (IR) on the position (spec field `incomeTax.amount` / `incomeTaxProvision.amount`).
{% enddocs %}

{% docs ofb_financial_transaction_tax_amount %}
Financial transaction tax (IOF) on the movement (spec field `financialTransactionTax.amount`).
{% enddocs %}

{% docs ofb_financial_transaction_tax_provision %}
Provision for financial transaction tax (IOF) on the position
(spec field `financialTransactionTax.amount` / `financialTransactionTaxProvision.amount`).
{% enddocs %}

{% docs ofb_remuneration_rate %}
Remuneration rate of the movement, as a decimal fraction (0.150000 = 15%).
Spec rule: required on `ENTRADA` movements of pre-fixed or hybrid products.
{% enddocs %}

{% docs ofb_indexer_percentage %}
Maximum indexer percentage agreed at contracting, as a decimal fraction (spec field `indexerPercentage`).
Spec rule: required on `ENTRADA` movements of post-fixed or hybrid products.
{% enddocs %}

{% docs ofb_currency %}
Currency of the monetary amounts in the row, ISO-4217 (e.g. `BRL`).
{% enddocs %}

{% docs ofb_isin_code %}
ISIN code: universal identifier of the security per ISO 6166 (spec field `isinCode`).
Spec rule (credit fixed incomes): must be filled when `clearing_code` is not.
{% enddocs %}

{% docs ofb_clearing_code %}
Registration code of the asset at the clearing house (spec field `clearingCode`).
Spec rule (credit fixed incomes): must be filled when `isin_code` is not.
{% enddocs %}

{% docs ofb_issuer_cnpj %}
CNPJ of the issuing institution (spec field `issuerInstitutionCnpjNumber`).
{% enddocs %}

{% docs ofb_pre_fixed_rate %}
Pre-fixed remuneration rate, as a decimal fraction with 6 decimal places
(0.150000 = 15%, 1 = 100%) (spec field `remuneration.preFixedRate`).
Spec rule: required when `indexer = 'PRE_FIXADO'` or the remuneration is hybrid.
{% enddocs %}

{% docs ofb_post_fixed_indexer_percentage %}
Percentage of the post-fixed indexer, as a decimal fraction with 6 decimal places
(0.150000 = 15%) (spec field `remuneration.postFixedIndexerPercentage`). A negative
value indicates a discount over the indexer.
Spec rule: required when `indexer != 'PRE_FIXADO'` or the remuneration is hybrid.
{% enddocs %}

{% docs ofb_issue_unit_price %}
Unit price at issuance (spec field `issueUnitPrice.amount`).
{% enddocs %}

{% docs ofb_issue_date %}
Issue date of the security (spec field `issueDate`).
{% enddocs %}

{% docs ofb_due_date %}
Maturity date of the security (spec field `dueDate`).
{% enddocs %}

{% docs ofb_purchase_date %}
Date the customer acquired the security (spec field `purchaseDate`).
{% enddocs %}

{% docs ofb_reference_date %}
Date (and time, where the family provides it) of the last consolidated position
the data refers to (spec field `referenceDate` / `referenceDateTime`).
{% enddocs %}

{% docs ofb_updated_unit_price %}
Current marked-to-market unit price of the security (spec field `updatedUnitPrice.amount`).
{% enddocs %}

{% docs ofb_purchase_unit_price %}
Unit price paid at acquisition (spec field `purchaseUnitPrice.amount`).
{% enddocs %}

{% docs ofb_gross_amount %}
Gross value of the position: quantity x current unit price (spec field `grossAmount.amount`).
{% enddocs %}

{% docs ofb_net_amount %}
Net value of the position, after tax provisions (spec field `netAmount.amount`).
{% enddocs %}

{% docs ofb_blocked_amount %}
Portion of the position that is blocked/unavailable, e.g. pledged as collateral
(spec field `blockedBalance.amount` / `blockedAmount.amount`).
{% enddocs %}

{% docs ofb_position_quantity %}
Quantity of securities held at the position date (spec field `quantity`).
{% enddocs %}

{% docs ofb_price_factor %}
Number of shares used to form the price; always greater than zero (spec field `priceFactor`).
{% enddocs %}
