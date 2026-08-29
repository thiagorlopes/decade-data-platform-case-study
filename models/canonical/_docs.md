# Column doc blocks shared across staging, intermediate and consumption.
# Descriptions and enum values come from the Open Finance Brasil investment API specs
# (see the header of each staging model for the exact spec file and line anchors).
# Blocks prefixed `ofb_` describe provider payload fields; blocks prefixed
# `stg_` describe our envelope columns and staging conventions. Blocks prefixed
# `dq_` describe the data-quality contract carried on every intermediate and
# consumption row (see README §Data quality for the narrative).

{% docs dq_admission %}
What downstream may do with each lot. The intermediate layer classifies but
never deletes: rejected and quarantined rows stay in the int_*_positions
tables for audit.

- `admit`: aggregate into holdings. This is what the consumption layer
  filters on.
- `reject_duplicate`: redundant copy of a hard duplicate (all measures
  agree under one natural key). One row per group is kept as `admit`; the
  rest carry this label so consumers ignore them without losing the audit
  trail.
- `reject_zero_duplicate`: same-sync conflict where exactly one side is a frozen
  zero-valued row. The zero side gets this label; the live side is
  admitted and flagged `lot:zero_copy_dropped`.
- `quarantine`: same-sync conflict with no single live row to pick.
  Neither side is safe to aggregate automatically. Rows stay in
  `int_*_positions` for audit; the holdings views drop them so consumers
  under-count rather than fabricate a number. See README §Quarantine runbook.
{% enddocs %}

{% docs data_quality_flags %}
Row-level warnings the lot or holding was admitted with. Empty list means
clean. Each flag names a specific defect or resolution applied, so a
consumer can filter on the presence or absence of a class of issue without
needing to know the SQL that produced it.

Lot-grain, added in int_*_positions:

- `<column>:missing` (e.g. `indexer:missing`, `gross_amount:missing`):
  non-repairable NULL in a column the OFB spec marks required. The
  per-family list is the `extra_flags` argument of each int_*_positions
  model.
- `natural_key:missing`: the record carries no identity to merge on (no ISIN,
  ticker, or equivalent). It becomes its own holding, keyed by its
  investment_id, and never merges with other records of the same security.
  The identity columns it covers are not flagged again individually.
- `lot:zero_copy_dropped`: the provider sent two copies of this lot in
  the same sync, one live and one zero-valued. The live row was kept and
  carries this flag; the zero copy was dropped (see `reject_zero_duplicate` in
  admission). The holding's number is stable even though the raw feed
  disagreed.
- `net:above_gross`: the payload's net_amount exceeds its gross_amount.
  Net of taxes and fees can never exceed gross, so one of the two is
  wrong and there is no way to tell which. Both are kept as delivered;
  do not trust net on this row.
- `gross:not_quantity_times_price`: the payload's gross_amount disagrees with its
  own quantity times unit price beyond a 0.5% tolerance. One of the
  three fields is wrong and there is no way to tell which. All are kept
  as delivered.
- `financial_transaction_tax:placeholder`: the payload reports a
  financial transaction tax that does not exist for this row. Its net
  equals gross minus income tax to the cent, so no such tax was ever
  charged; the reported amount is a placeholder, not a tax. Amounts
  are kept as delivered; ignore financial_transaction_tax_amount on
  this row.

Holding-grain, added in int_*_holdings (cross-sync signals that only
make sense once lots are aggregated by natural key):

- `investment_id:multiple`: the provider keeps two or more position
  records for this security at the same time. The holding sums them into
  one line; n_investment_ids counts them and investment_ids lists them.
- `lot:zero_kept`: one of the lots merged into this holding is worth zero
  (gross_amount = 0) while its siblings are live. The empty lot was kept,
  so n_investment_ids and investment_ids include it.
- `gross:zero_transient`: the holding's gross went to zero for a sync, then
  came back, with quantity unchanged. A brief false zero from the
  provider, not a real trade or valuation change.
- `investment_id:replaced`: between two syncs, the provider retired one
  of the holding's investment_ids and issued a new one for the same
  security. Both ids resolve to the same holding_key, so the old id's
  movements stay attached to the holding; history the provider re-issued
  under the new id collapses to one copy (see `transaction_id:reissued`).
- `quantity_reported:stale`: the provider's balance quantity disagrees with the
  quantity replayed from the holding's movements. The balance feed writes
  quantity at the first buy and does not maintain it, so the movements are
  the reliable record. Prefer `quantity_derived`.
- `movements:incomplete`: the holding's movement replay dips below zero
  even with lost-date sells placed last, so movements must be missing and
  `quantity_derived` cannot be trusted for this holding. Keep the
  provider's `quantity` and caveat it.

Movement-grain, added in fct_movements:

- `transaction_date:missing`: the provider sent no usable movement date
  (NULL, or a placeholder: `0001-01-01` .NET MinValue, `1970-01-01` Unix
  epoch zero). The date is NULL; the movement still counts toward totals
  but cannot be placed on a timeline.
- `transaction_id:reissued`: the provider delivered this movement again under
  another investment_id of the same holding, with a fresh transaction_id.
  The first-delivered copy survives with this flag; the twin's
  transaction_id stays in int_*_transactions. Movements that look
  identical across ids are kept apart only when the ids were both
  admitted in one sync with different gross amounts: differing gross
  proves two real lots of the holding, so the repeats are real. A
  co-admitted pair with identical gross is a duplicated record, and its
  movements collapse like any other twin.
{% enddocs %}

{% docs dq_quantity %}
The resolved quantity, one rule for every consumer: the movement replay
unless it is untrustworthy (`movements:incomplete`), then the provider's
number. A plain column name is a promise the row stands behind; the
provider's original claim is kept in `quantity_reported`.
{% enddocs %}

{% docs dq_gross_amount %}
The row-consistent value: `quantity * unit_price`, using the resolved
quantity. NULL when the provider sent no price.

To reconcile with the institution's displayed balance, read
`gross_amount_reported` instead: that column is the provider's own
valuation, which prices its frozen quantity.
{% enddocs %}

{% docs dq_unit_price %}
The provider's price per unit at the sync, quantity-weighted across the
holding's admitted lots.

Conformed per family:
- bank, credit, treasury: `updatedUnitPrice`.
- funds: the quota gross price.
- variable incomes: `closingPrice` divided by the price factor.

Prices update every sync (unlike the frozen quantity) and drive
gross_amount, so unit_price is the maintained half of the provider's
valuation and the price the plain `gross_amount` column uses.
{% enddocs %}

{% docs dq_quantity_derived %}
Quantity replayed from the holding's movements: buys add, sells subtract,
movements with no quantity count zero. Lost-date buys sort first,
lost-date sells last.

Replayed at holding grain over the deduplicated movement stream, so
history follows the holding across an id replacement and a movement
re-issued under another id counts once.

Every snapshot row of a holding carries the same current-knowledge value.
It is exact for the latest snapshot.

Trust:
- Disagrees with the provider's `quantity`: holding carries `quantity_reported:stale`.
  Prefer this column.
- Replay infeasible: holding carries `movements:incomplete`. Do not use
  this column.

See the `replay_quantity` macro header for the defect narrative.
{% enddocs %}

{% docs stg_contract %}
Staging is a 1:1 flatten of the verbatim provider payload into typed columns
(TRY_CAST, so parse failures become NULL). Nothing is repaired, deduplicated
or dropped here: defective rows are recorded in the audit schema
(store_failures) and resolved in the intermediate layer.
{% enddocs %}

{% docs stg_snapshot_id %}
Identifier of the ingestion snapshot that delivered this row. Each snapshot is
a full re-delivery of the party's investments, so the same investment
reappears once per snapshot; use the latest snapshot for current state.
{% enddocs %}

{% docs stg_snapshot_created_at %}
Timestamp at which the snapshot was assembled upstream.
{% enddocs %}

{% docs stg_institution_id %}
Identifier of the transmitting institution (brand).
{% enddocs %}

{% docs stg_institution_name %}
Display name of the transmitting institution.
{% enddocs %}

{% docs stg_party_id %}
Identifier of the customer (party) the consent belongs to.
{% enddocs %}

{% docs stg_account_id %}
Identifier of the customer's investment account at the institution.
{% enddocs %}

{% docs stg_connection_id %}
Identifier of the Open Finance consent connection that produced the snapshot.
{% enddocs %}

{% docs stg_ingested_at %}
Timestamp at which our pipeline ingested the raw record. Also the incremental
watermark downstream.
{% enddocs %}

{% docs stg_payload_source %}
Which endpoint delivered the transaction row: `transactions` (historical
window) or `transactions-current` (recent movements). The same movement can
legitimately arrive from both endpoints, so this column is part of the
staging grain and duplicates across sources are expected here; deduplication
happens downstream.
{% enddocs %}

{% docs stg_cnpj_format %}
CNPJ format policy: the OFB spec mandates exactly 14 digits with no
punctuation, but providers are known to append decimal tails (e.g.
`12345678000199.0`). Staging keeps the value verbatim and flags bad forms
via the `*_cnpj_form` warn test; the intermediate layer normalizes it.
Do not join on this column raw.
{% enddocs %}

{% docs stg_purchase_date_placeholder %}
Some providers send `0001-01-01` when they do not know the real purchase
date — a fake date that means "missing". It looks like a valid date, so
downstream code that treats it as one silently corrupts date ranges and
sort orders. Staging leaves it as-is and flags it via the
`*_purchase_date_not_placeholder` warn test; the intermediate layer nulls it
out (`clean_missing_date`). Treat as NULL, never as a real date. Real
values must fall between `issue_date` and `due_date` (warn tests).
{% enddocs %}

{% docs stg_isin_format %}
ISIN follows ISO 6166: 2-letter country prefix, 9 alphanumerics, 1 check
digit. Enforced by the `*_isin_form` warn test where applicable.
{% enddocs %}

{% docs ofb_indexer_additional_info %}
Free-text qualifier the provider sends when `indexer = 'OUTROS'`
(spec field `remuneration.indexerAdditionalInfo`).
{% enddocs %}

{% docs ofb_rate_type %}
Compounding regime of the rate (spec field `remuneration.rateType`).
Enum: `EXPONENCIAL`, `LINEAR`.
{% enddocs %}

{% docs ofb_rate_periodicity %}
Period the rate refers to (spec field `remuneration.ratePeriodicity`).
Enum: `DIARIO`, `MENSAL`, `SEMESTRAL`, `ANUAL`.
{% enddocs %}

{% docs ofb_calculation %}
Day-count basis of the rate (spec field `remuneration.calculation`).
Enum: `DIAS_UTEIS` (business days, Brazilian 252 convention),
`DIAS_CORRIDOS` (calendar days).
{% enddocs %}

{% docs ofb_grace_period_date %}
End of the redemption grace period (carencia): the position cannot be
redeemed before this date (spec field `gracePeriodDate`).
{% enddocs %}

{% docs ofb_voucher_payment_indicator %}
`SIM` when the instrument pays periodic interest coupons (cupom), `NAO` when
interest is only paid at maturity or redemption (spec field
`voucherPaymentIndicator`). Enum: `SIM`, `NAO`.
{% enddocs %}

{% docs ofb_voucher_payment_periodicity %}
Coupon frequency when `voucher_payment_indicator = 'SIM'` (spec field
`voucherPaymentPeriodicity`). Deliberately wider than `rate_periodicity`.
Enum: `MENSAL`, `TRIMESTRAL`, `SEMESTRAL`, `ANUAL`, `IRREGULAR`, `OUTROS`.
{% enddocs %}

{% docs ofb_voucher_payment_periodicity_additional_info %}
Free-text qualifier when the coupon periodicity is `OUTROS` or `IRREGULAR`.
{% enddocs %}

{% docs ofb_debtor_cnpj %}
CNPJ of the debtor behind the securitized receivables; for `DEBENTURES`, the
issuing company itself (spec field `debtorCnpjNumber`). Part of the
downstream holding-identity key for credit fixed income.
{% enddocs %}

{% docs ofb_debtor_name %}
Legal name of the debtor behind the securitized receivables (spec field
`debtorName`).
{% enddocs %}

{% docs ofb_fund_name %}
Commercial/legal name of the investment fund (spec field `name`).
{% enddocs %}

{% docs ofb_fund_cnpj %}
CNPJ of the investment fund (spec field `cnpjNumber`); Brazilian funds are
CNPJ-registered legal entities and this is the downstream holding-identity
key.
{% enddocs %}

{% docs ofb_anbima_class %}
Second level of the ANBIMA fund classification (spec field `anbimaClass`).
{% enddocs %}

{% docs ofb_anbima_subclass %}
Third level of the ANBIMA fund classification (spec field `anbimaSubclass`).
{% enddocs %}

{% docs ofb_ticker %}
Exchange trading code of the asset (spec field `ticker`, e.g. `PETR4`).
Together with `isin_code` it forms the downstream holding-identity key for
equities.
{% enddocs %}

{% docs ofb_product_name %}
Commercial name of the Tesouro Direto title as listed on
tesourodireto.com.br (spec field `productName`, e.g. "Tesouro Selic 2029").
{% enddocs %}

{% docs ofb_reference_datetime %}
Moment the balance figures refer to: the position is marked as of this
timestamp, as stated by the provider (spec field `referenceDateTime`).
{% enddocs %}

{% docs ofb_updated_unit_price_currency %}
ISO-4217 currency code of `updated_unit_price` (spec field
`updatedUnitPrice.currency`).
{% enddocs %}

{% docs ofb_quota_quantity %}
Number of fund quotas held at the reference date (spec field
`quotaQuantity`).
{% enddocs %}

{% docs ofb_quota_gross_price %}
Gross unit price of one quota at the reference date (spec field
`quotaGrossPriceValue.amount`).
{% enddocs %}

{% docs ofb_closing_price %}
Closing price of the equity instrument on the reference date (spec field
`closingPrice.amount`).
{% enddocs %}

{% docs ofb_fine_amount %}
Contractual fine (multa) accrued against the debtor on payments in arrears
(spec field `fine.amount`).
{% enddocs %}

{% docs ofb_late_payment_amount %}
Arrears interest (mora) accrued against the debtor (spec field
`latePayment.amount`).
{% enddocs %}

{% docs ofb_transaction_conversion_date %}
Date the fund movement converts into quotas (cotizacao), when the quota
price is set; can lag the date the customer requested the operation
(spec field `transactionConversionDate`).
{% enddocs %}

{% docs ofb_transaction_quota_price %}
Quota price applied to this movement (spec field
`transactionQuotaPrice.amount`).
{% enddocs %}

{% docs ofb_transaction_quota_quantity %}
Number of quotas moved (spec field `transactionQuotaQuantity`).
{% enddocs %}

{% docs ofb_transaction_amount %}
Total financial amount of the movement (spec field `transactionValue.amount`).
{% enddocs %}

{% docs ofb_transaction_exit_fee %}
Exit fee (taxa de saida) charged on early redemption (spec field
`transactionExitFee.amount`).
{% enddocs %}

{% docs ofb_broker_note_id %}
Number of the brokerage note (nota de corretagem) documenting the trade;
parameter for `GET /broker-notes/{brokerNoteId}` (spec field `brokerNoteId`).
{% enddocs %}

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
