# Research Method

## Core principle

**One experiment = one primary question.**

## Required record

Each experiment should include:

- Question
- Hypothesis
- Baseline
- Environment
- Procedure
- Raw results
- Interpretation
- Result
- Limitations
- Next experiment

## Result labels

Use one of:

- `SUPPORTED`
- `REJECTED`
- `MIXED`
- `INCONCLUSIVE`

## Benchmark discipline

- Separate warm and cold results.
- Separate compile and execution time where possible.
- Report cache hits and misses separately.
- Do not mix Debug and optimized builds.
- Use the same machine/workload for comparisons.
- Store multiple runs, not only the best result.
- Preserve raw data before summaries.

## Commit prefixes

```text
docs:
exp:
bench:
fix:
refactor:
chore:
```
