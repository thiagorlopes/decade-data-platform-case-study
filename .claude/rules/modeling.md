---
description: Extend before adding models, preview data before writing SQL
paths:
  - models/**/*.sql
---

# Modeling discipline

Before adding a new model, ask why an existing one cannot be extended. Prefer adding a column to an existing intermediate model over adding a new model. Legitimate reasons for a new model: different grain, or precalculation for performance.

Before writing SQL against unfamiliar columns, preview the data first (`dbt show` or `make shell`). Check counts, nulls, and ranges so joins and filters match what is actually in the data.
