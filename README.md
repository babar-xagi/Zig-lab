# Zig-lab

Zig-lab is a planned native, cell-based development environment for Zig: part notebook, part code editor, part interactive systems lab.

The goal is to bring the exploratory workflow of tools like Jupyter notebooks to Zig while staying fast, local-first, strongly typed, and suitable for serious systems, data, AI, robotics, simulation, and performance work.

This repository is currently in the first implementation stage. The initial target is a command-line runner core that can parse `.ziglab` notebooks, run Zig cells, and later power both a native editor and a Jupyter/Anaconda kernel.

## Vision

Zig-lab should let developers write Zig in executable cells, inspect results immediately, visualize memory and data, run experiments safely, and grow notebooks into real Zig packages without leaving the editor.

The project should feel:

- **Native and fast**: quick startup, low memory overhead, responsive editor interactions.
- **Cell-based**: Zig code is organized into executable cells with outputs, diagnostics, and artifacts.
- **Real Zig, not a toy dialect**: cells should compile through Zig tooling and preserve Zig semantics.
- **Local-first**: notebooks, outputs, caches, and metadata live in ordinary project files.
- **Reproducible**: notebooks can be rerun from clean state and exported into scripts, packages, docs, or reports.
- **Inspectable**: memory, types, allocations, errors, generated artifacts, and performance data are visible.
- **Extensible**: plugins can add renderers, data viewers, AI assistants, kernels, and project integrations.

## Why Zig-lab?

Zig is excellent for building fast, predictable software, but experimentation often still happens through separate scripts, logs, terminals, and ad hoc tools. Zig-lab aims to make experimentation first-class without sacrificing native performance or correctness.

Unique directions for Zig-lab:

- **Typed notebook cells** with Zig-aware dependency tracking.
- **Memory and allocator inspection** after each cell run.
- **Compile-time reflection panels** for `comptime` exploration.
- **Build artifact browser** for binaries, libraries, generated files, and test outputs.
- **Benchmark cells** with repeatable timing and regression comparison.
- **Data and tensor viewers** for AI, ML, numerical, and binary data workflows.
- **C interop lab** for headers, ABI checks, linked libraries, and generated bindings.
- **Notebook-to-package promotion** so prototypes can become normal Zig modules.
- **AI-assisted Zig editing** with explicit diffs, test-aware suggestions, and local project context.

## Product Shape

Zig-lab will likely have four main layers:

1. **Notebook model**
   - File format for cells, metadata, outputs, execution order, and dependencies.
   - Text-friendly representation for Git diffs.

2. **Execution engine**
   - Runs cells using Zig build/run/test commands.
   - Manages temporary workspaces, caches, diagnostics, outputs, and artifacts.

3. **Native editor UI**
   - Cell editor, output panes, diagnostics, command palette, project explorer, and visual inspectors.
   - Designed for keyboard-heavy workflows and fast feedback.

4. **Extension system**
   - Renderers, tools, data viewers, AI workflows, custom commands, and language integrations.

## First Milestones

The project should start with documentation and architecture, then move into a narrow MVP:

- Define the notebook file format.
- Build a minimal command-line cell runner.
- Execute Zig cells and capture stdout, stderr, diagnostics, and artifacts.
- Add a simple native UI around the runner.
- Add richer editor features only after the execution model is reliable.

See [docs/ROADMAP.md](docs/ROADMAP.md) for the phased plan.

## Current CLI Prototype

The first runner core is now available as a Zig CLI.

Build:

```powershell
zig build
```

Run tests:

```powershell
zig build test
```

Check an example notebook:

```powershell
zig build run -- check examples/hello.ziglab
```

List cells:

```powershell
zig build run -- list examples/hello.ziglab
```

Run all cells:

```powershell
zig build run -- run examples/hello.ziglab
```

Run only one cell:

```powershell
zig build run -- run examples/hello.ziglab --cell answer
```

Save cell outputs:

```powershell
zig build run -- run examples/hello.ziglab --cell answer --save-outputs
```

This writes files under:

```text
examples/hello.ziglab.outputs/
  answer.stdout.txt
  answer.stderr.txt
  answer.output.txt
  answer.meta.json
```

Cells can declare explicit dependencies:

````text
```zig cell-id=answer mode=run depends-on=imports,add-fn
```
````

Zig cells can use `mode=decl`, `mode=run`, or `mode=test`. If `mode=` is missing, Zig-lab falls back to auto-detection for now. When a selected cell has `depends-on=...`, Zig-lab prepares only those declaration cells before running it.

Export Zig cells:

```powershell
zig build run -- export examples/hello.ziglab
```

Check diagnostic mapping with the intentional error example:

```powershell
zig build run -- run examples/error.ziglab --cell broken
```

Compiler errors should point back to the notebook path, cell id, and original cell line.

For intentional failures, `zig build run` will also print Zig's build-run failure footer because the app exits with code `1`. To see only Zig-lab's output, build once and run the executable directly:

```powershell
zig build
.\zig-out\bin\zig-lab.exe run examples/error.ziglab --cell broken
```

## Documentation

- [EXAMPLE.md](EXAMPLE.md): preview examples showing how Zig-lab could look after early builds.
- [docs/README.md](docs/README.md): documentation index.
- [docs/ROADMAP.md](docs/ROADMAP.md): phases, milestones, and acceptance criteria.
- [docs/FEATURES.md](docs/FEATURES.md): core and unique feature ideas.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): proposed system architecture.
- [docs/JUPYTER_KERNEL_STRATEGY.md](docs/JUPYTER_KERNEL_STRATEGY.md): Jupyter/Anaconda kernel strategy and comparison with a native editor.

## Early Non-Goals

To keep the first version realistic, Zig-lab should not begin as a huge full IDE clone.

Early non-goals:

- Replacing every feature of VS Code, JetBrains IDEs, or Vim.
- Supporting every language from day one.
- Building cloud collaboration before local execution is stable.
- Hiding Zig's build model behind too much magic.
- Creating a custom Zig syntax or incompatible notebook dialect.

## Suggested Tech Direction

The final stack is still open, but the project should prefer:

- Zig for core execution, notebook model, process management, and performance-sensitive systems.
- A native UI layer that can remain responsive under heavy outputs.
- Language Server Protocol integration for Zig editor intelligence.
- Structured files for notebook metadata and outputs.
- Plain project folders that remain usable outside Zig-lab.

## Repository Status

Status: **runner core MVP started**

Application code now exists for a small CLI runner. The next step is to improve cell dependency handling, diagnostics mapping, and the notebook file model.
