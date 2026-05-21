# Zig-lab Architecture

This document describes a proposed architecture for Zig-lab. It is intentionally early and should evolve as prototypes reveal what is simple, fast, and reliable.

## High-Level Components

Zig-lab can be split into these components:

- **Notebook Core**: data structures, schema, parsing, serialization, validation.
- **Execution Engine**: cell runner, build workspace, process control, diagnostics, output capture.
- **Editor App**: native UI, document editing, panels, commands, settings.
- **Language Tools**: Zig LSP integration, formatting, symbol and type features.
- **Renderer System**: text, markdown, diagnostics, tables, plots, images, binary data, custom outputs.
- **Project Tools**: export, package generation, build artifact management.
- **Plugin Host**: optional extension boundary for third-party renderers and commands.

## Proposed Repository Layout

Initial layout once code starts:

```text
Zig-lab/
  README.md
  build.zig
  build.zig.zon
  docs/
  examples/
  src/
    main.zig
    notebook/
    runner/
    diagnostics/
    render/
    app/
  tests/
    fixtures/
```

## Notebook Model

A notebook should contain:

- notebook schema version
- notebook metadata
- ordered cells
- cell ids
- cell type
- source text
- execution metadata
- outputs
- dependencies or inferred ordering

Cell types:

- `zig`: executable Zig code
- `markdown`: prose documentation
- `config`: notebook or build settings
- future: shell, data, SQL, AI prompt, benchmark

## Execution Model

The execution engine should avoid pretending that cells are magic. A cell run should translate notebook state into ordinary Zig source and build commands.

Possible flow:

1. Read notebook.
2. Select cells to run.
3. Build an execution workspace.
4. Generate temporary Zig files.
5. Invoke Zig tooling.
6. Capture stdout, stderr, diagnostics, exit code, and artifacts.
7. Map diagnostics back to notebook cells.
8. Update notebook outputs or external output cache.

## State Strategy

Notebook execution can support more than one mode:

- **Clean run**: regenerate and rerun from the beginning.
- **Incremental run**: reuse cached build artifacts where safe.
- **Scratch run**: execute a single cell in isolation.
- **Session run**: keep a temporary context for faster iteration.

The MVP should prefer correctness over clever caching.

## Diagnostics

Diagnostics need a source mapping layer because generated Zig files will not match notebook files exactly.

The mapping should track:

- notebook path
- cell id
- source line
- generated file path
- generated line
- compiler diagnostic span

## Output Model

Outputs should be structured, not just strings.

Output kinds:

- text
- error
- diagnostic
- artifact
- table
- plot
- image
- binary
- benchmark
- custom renderer payload

Large outputs should be stored outside the main notebook file when needed.

## UI Architecture

The editor should be built around a document model and commands:

- notebook document state
- selected cell state
- execution queue state
- output state
- diagnostics state
- project state

Important UI views:

- notebook editor
- output panels
- diagnostics panel
- project explorer
- artifact browser
- command palette
- settings

## Risks

- Mapping Zig compiler diagnostics back to notebook cells may be tricky.
- Long-running cells need strong cancellation and process cleanup.
- Rich outputs can make notebook files too large.
- Building a full IDE too early could slow down the core notebook work.
- Incremental cell execution may conflict with Zig's normal compilation model.

## Architecture Principle

The core runner should work without the GUI.

That one rule keeps the project testable, scriptable, and useful even before the native editor becomes polished.

