# Zig-lab Feature Plan

Zig-lab should start small, but the long-term design should leave room for a rich native notebook environment.

## Core Notebook Features

- Code cells for Zig.
- Markdown cells for explanation.
- Output cells for text, diagnostics, files, plots, tables, and custom renderers.
- Run current cell.
- Run selected cells.
- Run all cells.
- Restart execution context.
- Clear outputs.
- Reorder cells.
- Collapse cells and outputs.
- Cell-level metadata.
- Notebook-level settings.

## Zig-Specific Features

- Real Zig compile/run/test integration.
- Cell diagnostics mapped back to notebook locations.
- `comptime` exploration output.
- Type inspection.
- Symbol outline.
- Build artifact browser.
- Test cells.
- Benchmark cells.
- Allocator and memory views.
- Error union and error trace visualization.
- C ABI and FFI inspection.
- Generated binding preview.

## Data Science and AI Features

- Table viewer.
- CSV, JSON, JSONL, binary, and custom data preview.
- Tensor and matrix inspector.
- Plot output renderer.
- Image output renderer.
- Audio output renderer.
- Experiment run history.
- Parameter sweep cells.
- Benchmark regression comparison.
- Model output comparison panels.

## Native Editor Features

- Fast startup.
- Keyboard-first command palette.
- Multi-file project explorer.
- Split editor/output views.
- Search across notebook and project.
- Inline diagnostics.
- Themes.
- Keybindings.
- Large-output handling.
- Background execution queue.
- Cancellation and timeout controls.

## Unique Feature Ideas

### Memory Timeline

Show allocator activity per cell:

- bytes allocated
- peak memory
- leaks
- allocation hotspots
- freed versus retained memory

This would make Zig-lab especially useful for systems programming and performance work.

### Comptime Playground

Expose compile-time values, generated types, and evaluated branches in a dedicated view. Zig's `comptime` is powerful, and a notebook can make it easier to understand.

### Notebook to Package

Promote selected cells into:

- `src/main.zig`
- `src/lib.zig`
- `test` blocks
- examples
- documentation snippets

This keeps experiments from getting trapped in notebook form.

### Artifact Shelf

Each cell can produce artifacts:

- binaries
- libraries
- generated files
- plots
- datasets
- logs

The artifact shelf lets users inspect, compare, pin, export, or delete them.

### Reproducibility Panel

Show everything needed to rerun a notebook:

- Zig version
- build options
- environment variables
- package dependencies
- input files
- execution order
- cached artifacts

### Systems Debug Cells

Special cells for:

- running tests
- fuzzing
- benchmarking
- disassembly
- binary size analysis
- sanitizer-style checks where available

### AI Assistant With Guardrails

AI features should be optional and reviewable:

- explain a cell
- suggest tests
- propose refactors
- summarize compiler errors
- generate documentation from selected cells
- never modify notebook code without showing a diff

## MVP Feature Set

The first useful version should include:

- `.ziglab` notebook file.
- Zig code cells.
- Markdown cells.
- Run cell.
- Run all.
- stdout and stderr output.
- Compiler diagnostics.
- Save and load.
- Export to `.zig`.

Everything else should wait until this vertical slice is stable.

