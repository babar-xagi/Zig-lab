# Jupyter and Anaconda Kernel Strategy

This document explains what it would mean to build a Zig kernel for Jupyter or Anaconda, how it compares with building a full Zig-lab native editor, and which path is best for the project.

## Short Answer

The best strategy is **hybrid**:

1. Build the **Zig-lab runner core** first.
2. Use that runner core to create a **Jupyter kernel for Zig**.
3. Later build the **native Zig-lab editor** on top of the same runner core.

This gives the project a useful early product inside Jupyter/Anaconda while still preserving the long-term goal of a fast, rich, native Zig editor.

## What Is a Jupyter Kernel?

Jupyter has two main parts:

- **Frontend**: Jupyter Notebook, JupyterLab, VS Code notebooks, or another notebook UI.
- **Kernel**: the backend process that receives code cells, runs them, and sends results back.

Python notebooks use a Python kernel. For Zig-lab, we could build a **Zig kernel** so users can write Zig cells inside Jupyter or Anaconda.

Anaconda is not the kernel itself. Anaconda is a Python/data-science distribution that makes Jupyter easy to install and manage. A Zig kernel would be installed into Jupyter so Anaconda users can select it like:

```text
Kernel -> Change Kernel -> Zig
```

## How a Zig Kernel Could Work

Zig is compiled, not interpreted like Python. That means a Zig kernel cannot work exactly like Python internally, but it can feel similar to the user.

User experience:

```zig
const std = @import("std");
```

Output:

```text
Ready.
```

Next cell:

```zig
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Output:

```text
Ready.
```

Next cell:

```zig
std.debug.print("answer = {}\n", .{add(20, 22)});
```

Output:

```text
answer = 42
```

Behind the scenes, the kernel can generate temporary Zig files, compile them, run them, capture output, and send results back to Jupyter.

## Important Design Challenge

Python keeps live variables in memory between cells:

```python
x = 10
```

Then:

```python
x + 5
```

Zig does not naturally work this way because normal Zig code is compiled into a program. For Zig-lab, we need notebook semantics that feel easy but still respect Zig.

Possible execution models:

## Option 1: Independent Cell Mode

Every cell runs alone.

Pros:

- Easiest to implement.
- Very predictable.
- Fast to reason about.

Cons:

- Poor notebook experience.
- Later cells cannot use functions or constants from earlier cells.
- Does not feel like Python/Jupyter.

Verdict: useful only for a very early prototype.

## Option 2: Accumulated Source Mode

Each run builds a temporary Zig source file from previous cells plus the selected cell.

Example:

```text
cell 1: imports
cell 2: functions
cell 3: selected run cell
```

When cell 3 runs, Zig-lab generates a temporary program containing cells 1, 2, and 3.

Pros:

- Feels close to notebook workflow.
- Simple enough for MVP.
- Works well for functions, constants, types, tests, and imports.
- Easy to reproduce from clean state.

Cons:

- It is not a true live REPL.
- Re-running a cell may require recompiling generated code.
- Mutable runtime state from earlier cells is not naturally preserved unless designed carefully.

Verdict: best MVP model.

## Option 3: Persistent Session Mode

The kernel keeps a long-running Zig-powered process alive and tries to preserve state between cells.

Pros:

- Most Python-like experience.
- Better for interactive experiments.

Cons:

- Much harder to implement.
- Harder to make portable.
- Harder to debug.
- Could fight Zig's normal compile-time model.

Verdict: interesting later, not first.

## Option 4: Hybrid Mode

Use accumulated source mode for declarations and simple run cells, then add special persistent features later.

Pros:

- Good notebook experience.
- Practical implementation.
- Clean path from notebook to real Zig package.
- Fits both Jupyter kernel and native editor.

Cons:

- Needs clear rules for what persists between cells.

Verdict: best overall direction.

## Jupyter Kernel Architecture

The kernel could have these parts:

```text
Jupyter Notebook / JupyterLab / Anaconda
        |
        v
Zig-lab Jupyter Kernel
        |
        v
Zig-lab Runner Core
        |
        v
Generated Zig workspace
        |
        v
zig build / zig run / zig test
```

The kernel is only an adapter. The important part is the shared runner core.

## Kernel Responsibilities

A Zig Jupyter kernel should handle:

- Kernel startup.
- Cell execution requests.
- stdout and stderr capture.
- Compiler diagnostics.
- Cell completion status.
- Interrupt and cancellation.
- Kernel info.
- Basic code completion where possible.
- Rich output messages such as text, HTML, JSON, images, and tables.

## Runner Core Responsibilities

The runner core should handle:

- Notebook cell ordering.
- Temporary workspace creation.
- Source generation.
- Zig command execution.
- Diagnostics mapping.
- Output capture.
- Artifact capture.
- Cache invalidation.
- Export to normal Zig files.

This runner core should not depend on Jupyter. The native editor should use the same core later.

## Anaconda Installation Preview

A future Anaconda/Jupyter install could look like this:

```powershell
conda install zig-lab-kernel
```

Or:

```powershell
pip install zig-lab-kernel
python -m zig_lab_kernel install
```

Jupyter kernels are registered with a small kernel spec file. A future kernel spec could look like:

```json
{
  "argv": ["zig-lab-kernel", "-f", "{connection_file}"],
  "display_name": "Zig",
  "language": "zig"
}
```

After installation, the user could open JupyterLab and select the Zig kernel.

## Jupyter Kernel vs Native Editor

| Area | Jupyter/Anaconda Kernel | Native Zig-lab Editor |
| --- | --- | --- |
| Speed to first usable product | Faster | Slower |
| Existing notebook UI | Already available | Must build it |
| Data science adoption | Strong | Needs adoption from zero |
| Install path for Anaconda users | Familiar | Separate app install |
| Custom Zig UX | Limited by Jupyter | Full control |
| Native performance feel | Good backend, web frontend | Best possible |
| Memory inspector | Possible, but UI-limited | First-class feature |
| Artifact browser | Possible, but awkward | First-class feature |
| Debug panels | Limited | Full control |
| Cell execution | Good enough | Can be designed perfectly for Zig |
| Rich Zig project integration | Medium | Strong |
| Long-term uniqueness | Medium | High |
| Development effort | Lower | Higher |

## Which Is Best?

For an early product, **Jupyter/Anaconda kernel is best**.

Reasons:

- Users already understand notebooks.
- We can test Zig cell execution quickly.
- We do not need to build a full editor first.
- Anaconda and Jupyter already provide UI, file browsing, notebook saving, markdown cells, and outputs.
- It proves whether people want notebook-style Zig.

For the final vision, **native Zig-lab editor is best**.

Reasons:

- Zig-lab wants features Jupyter does not naturally provide.
- Memory inspection, artifact shelves, allocator timelines, build panels, and package export need deeper UI control.
- A native editor can be faster and more focused.
- The experience can be designed around Zig instead of forcing Zig into Python-shaped workflows.

## Recommended Build Order

### Phase K0: Shared Runner Core

Build a command-line runner first:

```powershell
zig-lab run examples/hello.ziglab
zig-lab run examples/hello.ziglab --cell answer
zig-lab check examples/hello.ziglab
```

This proves execution without any UI.

### Phase K1: Jupyter Kernel MVP

Build a small Jupyter kernel that calls the runner core.

MVP features:

- Run current Zig cell.
- Accumulate previous declaration cells.
- Show stdout.
- Show stderr.
- Show compiler errors.
- Stop running cell.

### Phase K2: Anaconda-Friendly Packaging

Package the kernel so data science users can install it.

Goals:

- Simple install.
- Kernel appears as `Zig`.
- Example notebooks included.
- Works with JupyterLab and classic notebooks.

### Phase K3: Rich Jupyter Outputs

Add output renderers:

- tables
- JSON
- images
- benchmark summaries
- memory summaries
- artifacts as downloadable files

### Phase N1: Native Editor Prototype

Build the first native Zig-lab editor after the runner is proven.

The native editor should reuse:

- same cell model
- same runner core
- same diagnostics mapper
- same export system

### Phase N2: Native-Only Advanced Features

Add features that are hard to do well in Jupyter:

- memory timeline
- allocator inspector
- build artifact shelf
- package promotion flow
- native project explorer
- deep Zig LSP integration
- custom debugging and benchmark panels

## Best Product Positioning

Zig-lab should not choose only one path too early.

Best positioning:

```text
Zig-lab Core
  shared execution engine for Zig cells

Zig-lab Kernel
  Jupyter/Anaconda kernel for early users and data science workflows

Zig-lab Native
  full native editor for the complete long-term experience
```

This makes the project stronger:

- Jupyter users get value early.
- Native editor work does not start from zero.
- The runner core becomes tested by both products.
- Example notebooks can work in multiple environments.

## Risks

Jupyter kernel risks:

- It may feel less native.
- Zig's compiled model may surprise Python users.
- Frontend customization is limited.
- Diagnostics mapping must be excellent.
- Packaging must handle Zig compiler discovery.

Native editor risks:

- Much larger development effort.
- Slower path to first users.
- Need to build many things Jupyter already gives for free.
- UI quality matters a lot.

Shared risk:

- The execution model must be clear. If users do not understand what persists between cells, the product will feel confusing.

## Final Recommendation

Build the **runner core first**, then the **Jupyter/Anaconda kernel**, then the **native editor**.

That path is fastest, safest, and still ambitious. It gives Zig-lab an early usable notebook experience while preserving the bigger vision: a rich, fast, native Zig notebook editor.

