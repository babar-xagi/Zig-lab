# ZNotebook: High-Performance Zig Notebook IDE

ZNotebook is a web-based, cell-based interactive development environment (IDE) for **Zig 0.16**, designed for data science, ML/AI, and rapid prototyping.

The project is implemented in **pure Zig** (no Rust/Python runtime). A single `znotebook` binary serves the UI, manages `.zignb` notebooks, and executes cells via the Zig compiler.

## Features

- **Interactive Cell Execution**: Write Zig code, run it, see results instantly.
- **Declarative Isolation**: Separates global declarations from runtime statements.
- **Rich Visual Outputs** via `lib/notebook.zig`:
  - Console stdout/stderr
  - HTML tables and layout containers
  - SVG plots generated in Zig
  - Markdown rendering
- **Modern Developer UI**: Glassmorphic dark UI with Monaco Editor (Zig syntax highlighting).
- **Native Zig Server**: Fast startup, zero extra runtimes, `.zignb` notebook format.

## Directory Structure

```text
zig-lab/
├── build.zig                 # Build & run: zig build run
├── build.zig.zon             # Package manifest (Zig 0.16+)
├── src/
│   ├── main.zig              # Server entry point
│   ├── config.zig            # Port, paths, .zignb constants
│   ├── assets.zig            # Frontend asset loader
│   ├── http/                 # HTTP parser + TCP server
│   ├── api/                  # REST route handlers
│   ├── format/               # .zignb load/save/list
│   └── engine/               # Cell parser, codegen, executor
├── lib/
│   └── notebook.zig          # User-facing rich output helpers (Zig 0.16)
├── frontend/
│   ├── index.html
│   ├── style.css
│   └── app.js
├── notebooks/
│   └── hello.zignb           # Example notebook
├── doc/
│   ├── getting_started.md    # User guide
│   ├── architecture.md
│   ├── roadmap.md
│   └── zig_native_backend.md
└── temp/                     # Generated Zig scratch + notebook.zig copy
```

## Quick Start

Requires **Zig 0.16.0** or newer.

```powershell
cd d:\zig-lab
zig build run
```

Open **http://localhost:8000** in your browser. The default notebook is `hello.zignb`.

### Build & test

```powershell
zig build          # compile to zig-out/bin/znotebook
zig build run      # start server
zig build test     # run unit tests
```

## Notebook Format (`.zignb`)

Notebooks are JSON files with this header:

```json
{
  "format": "zignb",
  "format_version": 1,
  "name": "hello",
  "cells": [ ... ]
}
```

Legacy `.znb` files are still loaded for migration; new saves use `.zignb` only.

## Development Phases

| Phase | Status | Deliverable |
|-------|--------|-------------|
| 0 | Done | `lib/notebook.zig` updated for Zig 0.16 `std.Io` |
| 1 | Done | `znotebook` HTTP server, UI, `.zignb` I/O |
| 2 | Done | Cell parser, codegen, `/api/run`, error mapping |
| 3 | Next | Cache tuning, CLI, packaging |
| 4 | Done | Legacy Rust backend removed |

See `doc/roadmap.md` for details.
