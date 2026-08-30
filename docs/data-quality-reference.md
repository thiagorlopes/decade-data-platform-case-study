# Data quality reference

Lookup material for the [detect, resolve, guarantee pipeline](../README.md#data-quality-detect-resolve-guarantee): what each [admission verdict](#admission-at-a-glance) and [quality flag](#flags-at-a-glance) means, [how to work a quarantined lot](#quarantine-runbook), [which fields the platform recalculates and which it only quotes](#field-trust-at-a-glance), and [what two audits found](#beyond-the-listed-defects) beyond the brief's defect list. The same vocabulary renders per column on the dbt docs site (`make docs`).

## The three stages in detail

```
dbt build (every run)

raw parquet ─→ STAGING (views, 1:1 flatten) ─→ INTERMEDIATE (incremental) ─→ CANONICAL fct ─→ consumers/

  ┌─ DETECT (staging) ─────────┐   ┌─ RESOLVE (intermediate) ───┐   ┌─ GUARANTEE (canonical) ────┐
  │ envelope (ours) → ERROR    │   │ no payload tests here      │   │ output contract → ERROR    │
  │   not_null snapshot_id     │   │ logic instead:             │   │   not_null natural key     │
  │   not_null investment_id   │   │   normalize forms          │   │   not_null reference_dt    │
  │   not_null ingested_at     │   │     (strip CNPJ tail,      │   │   grain uniqueness         │
  │   unique grain             │   │      map IPC-A → IPCA)     │   │   enums clean post-map     │
  │   build DIES: bug is ours  │   │ build data_quality_flags   │   │   build DIES: our          │
  ├────────────────────────────┤   │     for what cannot be     │   │     resolution failed      │
  │ payload (theirs) → WARN    │   │     repaired               │   ├────────────────────────────┤
  │   not_null required        │   │   dedupe across records    │   │ data_quality_flags → WARN  │
  │   format regex             │   └────────────────────────────┘   │   count stays visible      │
  │   accepted_values          │                                    └────────────────────────────┘
  │   cross-field rules        │
  │   store_failures: true     │
  └────────────────────────────┘
                │
                ▼
   main_dbt_test__audit.*  ◀── provider defect ledger (row-level, queryable)
```

**DETECT** lives in `models/staging/`. Rules sit in `_staging_quality.yml`. After `make build`, the audit ledger lands in `main_dbt_test__audit.*`. Every warn count is reproduced cell-by-cell in [`notebooks/02_within_record_defects.ipynb`](../notebooks/02_within_record_defects.ipynb).

**RESOLVE** lives in `models/canonical/intermediate/`. No payload tests here; repair logic instead:

- **Re-deliveries.** A record re-delivered with a different value survives in both feeds: the latest arrival wins. Positions apply the rule through the `latest_lot_delivery` macro; transactions apply it inline. Superseded copies stay countable in the `lot_redelivery` warn ledger.
- **Duplicate investment_ids.** The `resolve_duplicate_investments` macro dedupes positions across investment_ids.
- **Re-issued movements.** The `cross_id_movements` macro collapses movements re-issued under another investment_id of the same holding to one copy, flagged `transaction_id:reissued`. The same deduplicated stream feeds the holding-grain quantity replay.
- **Cross-sync flags.** `gross:zero_transient`, `investment_id:replaced`, `investment_id:multiple`, and `lot:zero_kept` are columns on the `int_*_holdings` views in the same folder. The admission enum is contract-tested at error severity.
- **Views, not tables.** The `int_*_holdings` views carry unique-grain tests and stay views so that downstream `lag`/`lead` over the full sync history stays cheap.

**GUARANTEE** lives in `models/consumption/`. `fct_holdings` and `fct_movements` each union the five families into one conformed shape. dbt contracts are enforced, so the build fails on column or type drift. Grain tests run at error severity. Consumers under `consumers/` read those two models and nothing below them.

## Admission at a glance

| Value | Meaning | Downstream effect |
|---|---|---|
| `admit` | Lot is clean or a resolved conflict winner. | Aggregated into holdings. |
| `reject_duplicate` | Redundant copy of a hard duplicate (all measures agree under one natural key). | Ignored; kept in `int_*` for audit. |
| `reject_zero_duplicate` | Frozen zero-valued side of a same-sync conflict (its live sibling is admitted with `lot:zero_copy_dropped`). | Ignored; kept in `int_*` for audit. |
| `quarantine` | Same-sync conflict with no single live row to pick. | Excluded from holdings; kept in `int_*_positions` (query `WHERE admission = 'quarantine'`) for audit. |

## Flags at a glance

Every flag follows the shape `subject:verdict`: the prefix names the column or entity to doubt, the suffix names the verdict on it. A consumer selects a whole class with one suffix filter (`WHERE flag LIKE '%:missing'`). Lot flags are added in `int_*_positions`, holding flags in `int_*_holdings`, movement flags in `fct_movements`.

| Grain | Flag | Meaning |
|---|---|---|
| Lot | `<column>:missing` | A spec-required column arrived empty and could not be repaired (`indexer:missing`, `isin_code:missing`, ...). |
| Lot | `natural_key:missing` | The record has no identity to merge on. It becomes its own holding, keyed by its investment_id. |
| Lot | `lot:zero_copy_dropped` | The sync delivered two copies of the lot, one live and one zero. The live copy was kept; the zero copy was dropped. |
| Lot | `net:above_gross` | The payload's net exceeds its gross. One of the two is wrong; both are kept as delivered. Do not trust net on this row. |
| Lot | `gross:not_quantity_times_price` | The payload's gross disagrees with its own quantity times unit price. All three fields are kept as delivered. |
| Lot | `financial_transaction_tax:placeholder` | The payload reports a transaction tax that does not exist for the row: net equals gross minus income tax to the cent. The amount is a placeholder, not a tax. |
| Holding | `investment_id:multiple` | The provider keeps two or more live position records for the security at once. The holding sums them. |
| Holding | `investment_id:replaced` | The provider retired one id and issued a new one for the same security. Both ids resolve to the same holding, so its movements and replay follow it across the replacement. |
| Holding | `lot:zero_kept` | One of the summed lots is worth zero while its siblings are live. It was kept, not dropped like a `lot:zero_copy_dropped`. |
| Holding | `gross:zero_transient` | Gross went to zero for one sync and came back, with quantity unchanged. |
| Holding | `quantity_reported:stale` | The balance quantity disagrees with the quantity replayed from movements. The plain quantity column already prefers the replay; the provider's number stays in `quantity_reported`. |
| Holding | `movements:incomplete` | The replay is infeasible even under the most favorable ordering, so movements must be missing. Keep the provider's figures and caveat them; when their own row also fails gross = quantity times price, the quantity their gross and price imply replaces the placeholder. The feed serves only recent history, so gaps are expected ([why](#the-feed-serves-only-recent-history)). |
| Holding | `holding:matured` | The due date has passed and the institution still reports a balance. This flag discloses a fact. It changes no number. Only the three families that carry a due date raise it. |
| Movement | `transaction_date:missing` | No usable movement date. The movement counts in totals but has no place on a timeline. |
| Movement | `transaction_id:reissued` | The provider re-delivered this movement under another investment_id of the same holding, with a fresh transaction_id. This copy stands for the copies; its twins were dropped. |

The long-form version of each entry lives in the [`data_quality_flags` doc block](../models/canonical/_docs.md) and renders on every column that carries it via `make docs`.

## The feed serves only recent history

The transactions endpoint returns a bounded slice of history. That limit
is how a replay can go negative with nobody at fault, so
`movements:incomplete` is usually a gap in the feed rather than an error
by the provider.

Three facts measured on this sample:

- Every holding carries its opening acquisition at its true date, back to 2019.
- 99.6% of third-and-later movements land on or after 2025-08-19.
- The syncs run from 2026-07-28 to 2026-08-21, so that start date is a trailing twelve months.

The feed never serves trades struck between the purchase and the start of
that window. A ledger can therefore show a sell whose matching buy is
missing, and the replay runs negative through no fault of the data. All
1,094 occurrences are that case. None is a holding with no receipts at all.

The platform refuses rather than guesses. A holding whose replay is
infeasible keeps the provider's figures, carries `movements:incomplete`,
and tells the consumer so. It does not publish a replay it cannot
support. One case inside that fallback: when the provider's own row also
fails gross = quantity times price, their gross and price corroborate
each other and the quantity is the odd field out, so the published
quantity is gross / price rather than the placeholder. Repeating the
placeholder would let the recomputed gross inflate the holding by
orders of magnitude.

Breakage tracks how many movements are visible, not how old the purchase
is. The flag never fires on holdings with one or two movements, and it
reaches 49% at six or more.

## Field trust at a glance

The rule in one line: recalculate what an independent source can prove, quote and disclose what only the provider knows, and contradiction-check everything inside the record.

- **`quantity` is recalculated.** Quantity is a write-once field in this feed (zero of ten thousand raw position records ever update it), so the platform recalculates it from the movements ledger and publishes the resolved number as the plain `quantity` column.
- **`unit_price` is maintained.** Prices update every sync and drive gross, so `unit_price` is the maintained half of the provider's valuation.
- **Gross and net are quoted and cross-checked.** They stay as the provider's marks, on the provider's own basis, with that basis disclosed in the contract. They cannot be recomputed without inventing data, but they can be checked against the record itself; the `net:above_gross` and `gross:not_quantity_times_price` flags carry the verdicts.
- **The naming carries the rule.** A plain column (`quantity`, `gross_amount`) is a number the platform stands behind, and the plain columns of a row agree with each other. A `_reported` column is the provider's original claim, kept for reconciliation. Net exists only as `net_amount_reported` because nothing can vouch for it.

## Quarantine runbook

Quarantined lots live in `int_*_positions` with `admission = 'quarantine'`: the classifier refused to guess. Every occurrence is actionable:

1. **Triage.** Query the family's `int_*_positions` filtered on `admission = 'quarantine'` for the natural key, both investment_ids, quantity and the conflicting gross amounts. Cross-check the transactions feed for the same account and holding (did a redemption explain the drop?), then look at the next sync (did one copy stop updating while the other moved?).
2. **Resolve.** One of three paths:
   - **Transient**: the next sync disambiguates on its own. No code change; the holding re-admits itself.
   - **Systematic**: a pattern emerges (e.g. the row with the newer `reference_datetime` is always the live one). Encode it as a new classification branch in `resolve_duplicate_investments`, then replay history with `make clean && make build` (the incremental-idempotency deliverable pays for exactly this).
   - **Provider defect**: neither feed explains it. Escalate to the institution with the staging warn tests as corroborating evidence.
3. **Meanwhile, the consumer is protected by construction.** Quarantined lots never reach `int_*_holdings`, so the wealth page under-counts one holding rather than fabricating a number. This is a deliberate product stance: when valuations conflict irreconcilably, a conservative omission beats a made-up value, and the omission is discoverable in the positions table.

## Beyond the listed defects

The brief warns that "an institution respecting [the spec] is a hope, not a guarantee." So the §2.2 list is illustrative, not exhaustive. Two audits ran against the built warehouse.

**Listed classes in new forms.** The case authors seeded the announced defect classes in forms the brief does not name. The intermediate layer's repair macros handle them. Raw counts stay visible in the staging warn tests. When the repair cannot recover the value, the row carries a flag in `data_quality_flags`; a fully repaired value carries no flag.

| Form | Class it belongs to | Where handled | Flag on the row | Raw count |
|---|---|---|---|---|
| `0001-01-01` placeholder dates (.NET `DateTime.MinValue`) | Required field arriving empty | `clean_missing_date` | `<column>:missing` for the nulled date, e.g. `purchase_date:missing` | 1 951 |
| Blank strings on natural-key fields | Required field arriving empty | `blank_to_null` | `natural_key:missing` when no identity survives | see warn tests |
| `'IPC-A'` for `'IPCA'` (plausible market spelling) | Legal value outside the enumeration | `clean_indexer` | none, fully repaired | 2 |
| `1970-01-01` placeholder dates (Unix epoch zero) on transaction dates | Required field arriving empty | `clean_missing_date` | `transaction_date:missing` on `fct_movements` | 3 001 |
| CNPJ with decimal tail (`92894922000108.00`) | Right concept, wrong form (named) | `clean_cnpj` | none, fully repaired | 1 370 |
| `9900` placeholder quantity on duplicated position records | Required field arriving empty | co-admission rule in `cross_id_movements` | `gross:not_quantity_times_price` | 1 722 |
| `88.90` placeholder transaction tax, constant across position sizes and never subtracted from net | Required field arriving empty | flag only, amounts kept as delivered | `financial_transaction_tax:placeholder` | 1 877 |

**Unlisted classes, all zero hits.** Nine defect classes the brief does not name and the sample does not contain. Zero hits shows the seeding stuck to the announced classes. It does not prove these defects are absent in production. In production, each would become a warn test in `_staging_quality.yml`. The sample does not justify permanent tests for data that is not there.

| Probe | Rationale |
|---|---|
| Same `transaction_id`, conflicting `transaction_amount` | Transactions-side analogue of the redundant-copies defect |
| Negative `transaction_amount` or `gross_amount` | Sign errors on values the domain treats as positive |
| Transaction dated after its own snapshot | Envelope violation: the payload references a future the snapshot can't see |
| Holding switching currency between syncs | Cross-sync contradiction not covered by `gross:zero_transient` |
| Holding dropout (present, absent one sync, present again) | Missing-row cousin of `gross:zero_transient`; the provider drops the row instead of zeroing it |
| Zero quantity with positive gross_amount | Mirror of the `gross:zero_transient` defect at a single row |
| Quantity change with no transaction behind it | Cross-feed reconciliation: positions and transactions disagreeing on a movement |

The last probe is also a modeling finding. Quantities never move in the sample. Every seeded across-record defect keys on "quantity unchanged" because quantity is the only invariant the sample offers.

**Unlisted classes found and left unhandled.** A third audit ran over the descriptive attributes of `dim_holding` and found three defects there. The platform ships all three as they arrive. They are measured and written up under [Three descriptive-field defects](../README.md#three-descriptive-field-defects).
