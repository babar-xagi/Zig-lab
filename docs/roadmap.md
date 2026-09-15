# Zig Lab Research Roadmap

## Foundation

- [x] Define repository purpose
- [x] Define experiment format
- [x] Define benchmark discipline
- [x] Preserve notebook history
- [ ] Migrate historical prototype source

## EXP-001 — Hybrid Execution Cache

Question:

> Which execution strategy gives the best repeated-cell latency while preserving correct Zig behavior?

Compare:

1. current fast evaluator
2. normal compiler fallback
3. incremental compilation
4. compiled-artifact cache

Measure:

- cold latency
- warm latency
- compilation time
- execution time
- cache lookup overhead
- output correctness
- state correctness

## EXP-002 — `comptime`-specialized fast engine

Targets:
- type operations
- coercion
- formatting
- serialization
- command dispatch

## EXP-003 — Browser WASM runtime

Measure:
- startup cost
- module size
- execution latency
- state persistence

## EXP-004 — Browser artifact cache

Measure:
- lookup latency
- persistence across reloads
- invalidation
- offline behavior
