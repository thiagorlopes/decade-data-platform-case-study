---
description: dbt CLI conventions, build over run, always select
---

# dbt commands

Use `dbt build`, not `dbt run`. Build runs tests in the same step and catches data issues immediately.

Always pass a selector and quiet flags:

```bash
dbt build --select <model> --quiet --warn-error-options '{"error": ["NoNodesForSelectionCriteria"]}'
```

Never run the whole project without the user asking for it. Preview results with `dbt show --select <model> --limit 10`.
