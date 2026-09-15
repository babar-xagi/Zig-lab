# ADR-0001: Organize Zig Lab as a Research Lab

- Status: Accepted
- Date: 2026-09-15

## Decision

Use stable experiment IDs, preserved benchmark evidence, architecture decision records, and historical notes.

Experiments live under:

```text
experiments/EXP-NNN-name/
```

Architecture decisions live under:

```text
docs/decisions/
```

Historical work lives under:

```text
docs/history/
```

## Why

This keeps successful, failed, and inconclusive experiments traceable instead of overwriting history.
