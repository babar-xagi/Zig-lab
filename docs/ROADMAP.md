# Zig-lab Roadmap

This roadmap keeps the project practical: first prove cell execution, then build a polished native editor, then add advanced data, AI, and systems tooling.

## Phase 0: Product Planning

Goal: define the project before writing code.

Deliverables:

- Root project README.
- Documentation index.
- Roadmap and feature plan.
- Initial architecture.
- MVP scope.

Acceptance criteria:

- A new contributor can understand what Zig-lab is.
- The first build target is clear.
- The project has explicit non-goals.

Status: in progress.

## Phase 1: Notebook File Format

Goal: create the first `.ziglab` notebook format.

Deliverables:

- Cell model: code, markdown, output, metadata, execution state.
- Stable notebook schema.
- Example notebook fixtures.
- Parser and serializer.
- Git-friendly formatting rules.

Acceptance criteria:

- A notebook can be loaded, edited structurally, saved, and diffed.
- Outputs can be stored separately or embedded according to a clear policy.
- Notebook files remain readable without Zig-lab.

## Phase 2: Cell Execution Engine

Goal: run Zig cells safely and reproducibly.

Deliverables:

- Temporary workspace manager.
- Zig command runner.
- stdout, stderr, diagnostics, exit code, and artifact capture.
- Dependency ordering between cells.
- Cell cache invalidation.
- Basic timeout and cancellation support.

Acceptance criteria:

- A single code cell can compile and run.
- Multiple dependent cells can run in order.
- Failures produce useful diagnostics.
- Re-running from clean state gives predictable results.

## Phase 3: Command-Line Prototype

Goal: prove the notebook system without a full UI.

Deliverables:

- `zig-lab run <notebook>` command.
- `zig-lab check <notebook>` command.
- `zig-lab export <notebook>` command.
- Simple text output report.

Acceptance criteria:

- Developers can run notebook files from a terminal.
- CI can validate notebook examples.
- The execution engine is usable before the editor exists.

## Phase 4: Native Editor MVP

Goal: build the first interactive cell editor.

Deliverables:

- Notebook document view.
- Code cells with syntax highlighting.
- Run cell, run above, run all.
- Output area per cell.
- Diagnostics panel.
- File open/save.
- Command palette.

Acceptance criteria:

- A user can create, edit, run, and save a Zig notebook.
- Editor stays responsive while cells execute.
- Errors are shown beside the cell that caused them.

## Phase 5: Zig-Aware Developer Experience

Goal: make Zig-lab feel like a serious Zig tool, not just a text box.

Deliverables:

- Zig LSP integration.
- Go to definition, hover, completion, rename basics.
- Test cell support.
- Build artifact browser.
- Type and symbol outline.
- Formatter integration.

Acceptance criteria:

- Editing Zig inside a cell feels close to editing a normal Zig file.
- Diagnostics point to useful cell locations.
- Notebook code can be exported to normal Zig modules.

## Phase 6: Rich Inspectors

Goal: add the features that make Zig-lab special.

Deliverables:

- Memory and allocator inspector.
- Binary and hex viewer.
- Table/dataframe viewer.
- Plot renderer.
- Benchmark result viewer.
- Comptime exploration panel.
- Error trace visualization.

Acceptance criteria:

- Outputs are interactive, not just text logs.
- Common systems/data experiments are easier inside Zig-lab than in a terminal-only workflow.

## Phase 7: AI and Data Science Workflow

Goal: support AI, ML, numerical, and data experimentation in Zig.

Deliverables:

- Tensor and matrix viewers.
- Dataset preview tools.
- Long-running job status.
- Experiment metadata.
- Reproducible benchmark and training logs.
- Optional AI assistant integration for explanations, refactors, and test suggestions.

Acceptance criteria:

- Users can inspect numerical data and model outputs directly inside notebooks.
- AI assistance is transparent and reviewable.
- Notebook runs remain reproducible without AI services.

## Phase 8: Plugin System

Goal: let the community extend Zig-lab.

Deliverables:

- Renderer plugin API.
- Tool command API.
- Data viewer API.
- Theme and keybinding support.
- Extension manifest.

Acceptance criteria:

- A third-party developer can add a custom output renderer without modifying core code.
- Plugins have a stable boundary and clear permissions.

## Phase 9: Packaging and Distribution

Goal: ship Zig-lab as a real application.

Deliverables:

- Installers or portable builds.
- Example notebooks.
- User documentation.
- Crash reporting strategy.
- Update strategy.
- Release checklist.

Acceptance criteria:

- A new user can install Zig-lab and run an example notebook in minutes.
- Releases are repeatable.

