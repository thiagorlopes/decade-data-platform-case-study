---
description: Contracted column changes require versioning, not in-place edits
paths:
  - models/consumption/**
  - contracts/**
---

# Contract changes

Renaming, removing, or retyping a column in a consumption model is a breaking change for its consumers. Do not edit it in place. Add a new versioned model (or new column alongside the old one), give consumers a migration window, then retire the old shape. Additive changes (new columns) are fine in place, but land with their contract change in the same commit.
