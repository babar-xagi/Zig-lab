# Architecture Notes

Architecture is provisional and should change only when experiments provide evidence.

## Historical hybrid model

```text
User Input
    │
Persistent Kernel
    │
  Router
 ┌──┴──┐
 ▼     ▼
FAST  COMPILER
 │      │
 └──┬───┘
    ▼
Typed Persistent State
```

## Candidate future execution hierarchy

```text
Cell
 │
 ▼
Artifact Cache
 │
 ├─ hit ─────────► Execute cached artifact
 │
 └─ miss
      ▼
Comptime-specialized Fast Engine
      │
      ├─ supported ─► Execute directly
      │
      └─ unsupported
           ▼
Incremental / Real Zig Compiler
           │
           ▼
Store reusable artifact
```

## Candidate browser architecture

```text
Browser UI
├── persistent notebook state
├── cached runtime assets
├── cached compiled WASM artifacts
└── execution runtime
     ├── local fast engine
     └── compiler bridge when required
```
