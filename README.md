# Zig Lab ⚡

Zig Lab is a research-engineering repository for experiments around interactive Zig, developer tooling, WebAssembly, caching, compile-time specialization, incremental compilation, and systems-oriented notebook ideas.

## Research direction

The starting point is an earlier Zig notebook prototype that demonstrated:

- persistent typed state
- a fast evaluator for simple expressions
- fallback to the real Zig compiler
- synchronization of supported mutable values back into fast state

Next research areas:

- `comptime` specialization
- incremental compilation
- compiled-artifact caching
- browser/WebAssembly execution
- browser-side persistent caching
- a Zig-native notebook experience

## Repository layout

```text
zig-lab/
├── README.md
├── docs/
│   ├── vision.md
│   ├── architecture.md
│   ├── research-method.md
│   ├── roadmap.md
│   ├── decisions/
│   └── history/
├── experiments/
│   └── README.md
├── benchmarks/
│   └── README.md
└── .gitignore
```

## Experiment IDs

Use permanent IDs:

```text
EXP-001
EXP-002
EXP-003
```

Example:

```text
experiments/EXP-001-hybrid-execution-cache/
```

## Every experiment records

1. Question
2. Hypothesis
3. Baseline
4. Environment
5. Implementation
6. Procedure
7. Raw results
8. Interpretation
9. Result
10. Limitations
11. Next step

## Research rules

- Measure before claiming performance improvements.
- Preserve failed experiments.
- One main question per experiment.
- Prefer reproducible commands over screenshots alone.
- Keep raw benchmark data.
- Record Zig version and build mode.
- Separate observations from interpretation.

## Status

🧪 Early research phase.
