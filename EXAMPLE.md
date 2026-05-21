# Zig-lab Example Preview

This file shows how Zig-lab could look and feel after the first real builds. It is not implemented yet. It is a target experience for design, architecture, and MVP planning.

## Simple Cell Experience

Zig-lab should feel easy like a Python notebook:

- Add a code cell.
- Type a few lines of Zig.
- Run only that cell.
- See output directly under the cell.
- Keep working without creating a full `main.zig` file every time.

Common controls:

```text
Ctrl+Enter    run current cell only
Shift+Enter   run current cell, then move to next cell
Alt+Enter     run current cell, then create a new cell below
Run All       run the whole notebook from top to bottom
Stop          cancel the running cell
Clear         clear this cell's output
```

Zig-lab can generate the temporary Zig wrapper behind the scenes. The user should be able to write simple cells first, then export to normal Zig files later.

## Desktop App Preview

```text
+--------------------------------------------------------------------------------+
| Zig-lab                                      notebook: examples/hello.ziglab    |
+----------------------+---------------------------------------------------------+
| Project              | Cell 1: Markdown                                         |
|                      | # Hello Zig-lab                                         |
| examples/            | Run Zig code one cell at a time.                        |
|   hello.ziglab       +---------------------------------------------------------+
|   memory.ziglab      | Cell 2: Zig                         [Run Cell] [Clear] |
| src/                 | const std = @import("std");                            |
|                      | const name = "Zig-lab";                                |
| Commands             | std.debug.print("hello from {s}\n", .{name});          |
| Run Cell             |                                                         |
| Run All              +---------------------------------------------------------+
| Clear Outputs        | Output                                                  |
| Export to Zig        | hello from Zig-lab                                      |
|                      +---------------------------------------------------------+
|                      | Diagnostics                                             |
|                      | No errors                                               |
+----------------------+---------------------------------------------------------+
```

The first version should feel simple: open a notebook, edit one Zig cell, run only that cell, and see output below it.

## Single Cell Preview

This is the main interaction Zig-lab should optimize:

```text
Cell 3: Zig                                      [Run Cell]
------------------------------------------------------------
const name = "Zig-lab";
std.debug.print("hello from {s}\n", .{name});
------------------------------------------------------------
Output
hello from Zig-lab
```

The user should not need to think about generated files, wrappers, or build folders for simple experiments.

## Easy Notebook Flow

### 1. Markdown Cell

```md
# Hello Zig-lab

This notebook runs small Zig cells one at a time.
```

### 2. Import Cell

```zig
const std = @import("std");
```

Run only this cell:

```text
Ready.
```

### 3. Print Cell

```zig
const name = "Zig-lab";
std.debug.print("hello from {s}\n", .{name});
```

Expected output:

```text
hello from Zig-lab
```

### 4. Function Cell

```zig
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Expected output:

```text
Ready.
Function available to later cells:
  fn add(a: i32, b: i32) i32
```

### 5. Run Only This Cell

```zig
const answer = add(20, 22);
std.debug.print("answer = {}\n", .{answer});
```

Expected output:

```text
answer = 42
```

This is the most important workflow: a user should be able to change only this cell and run only this cell without rerunning the whole notebook.

## Slightly Bigger Example

### 1. Setup Cell

```zig
const std = @import("std");

fn sum(values: []const i64) i64 {
    var total: i64 = 0;
    for (values) |value| {
        total += value;
    }
    return total;
}
```

Expected output:

```text
Ready.
Symbols:
  fn sum(values: []const i64) i64
```

### 2. Run Cell

```zig
const values = [_]i64{ 10, 20, 30, 40 };
std.debug.print("sum = {}\n", .{sum(&values)});
```

Expected output:

```text
sum = 100
```

### 3. Test Cell

```zig
test "sum adds values" {
    const values = [_]i64{ 1, 2, 3 };
    try std.testing.expectEqual(@as(i64, 6), sum(&values));
}
```

Expected output:

```text
1/1 sum adds values... OK
All tests passed.
```

## Rich Output Example

A future memory inspector output could look like this:

```text
Memory Inspector

Cell: allocator experiment
Allocator: std.heap.GeneralPurposeAllocator

Allocated:     128.0 KiB
Freed:         128.0 KiB
Peak:          192.0 KiB
Leaks:         0
Allocations:   42

Status: clean
```

A future benchmark output could look like this:

```text
Benchmark: sum 1,000,000 integers

Runs:       100
Mean:       0.82 ms
Min:        0.78 ms
Max:        0.95 ms
Regression: none
```

## Command-Line Preview

The core runner should work before the full native UI exists.

```powershell
zig-lab run examples/hello.ziglab
```

Expected terminal output:

```text
Zig-lab notebook runner

Notebook: examples/hello.ziglab
Cells:    5

[1/5] markdown: skipped
[2/5] zig: ready
[3/5] zig: ran
[4/5] zig: ready
[5/5] zig: ran

Done in 420 ms.
```

Run only one cell from the command line:

```powershell
zig-lab run examples/hello.ziglab --cell answer
```

Expected output:

```text
[5/5] answer: ran
answer = 42
```

Save outputs for later inspection:

```powershell
zig-lab run examples/hello.ziglab --cell answer --save-outputs
```

Expected files:

```text
examples/hello.ziglab.outputs/
  answer.stdout.txt
  answer.stderr.txt
  answer.output.txt
  answer.meta.json
```

Check a notebook without running side effects:

```powershell
zig-lab check examples/hello.ziglab
```

Export notebook code into a normal Zig file:

```powershell
zig-lab export examples/hello.ziglab --out generated/hello.zig
```

## Notebook File Preview

The exact file format is still undecided, but it should be text-friendly and easy to diff.

Possible `.ziglab` shape:

````text
---
schema: 1
title: Hello Zig-lab
zig_version: project-default
---

```markdown cell-id=intro
# Hello Zig-lab

Small notebook that runs Zig code one cell at a time.
```

```zig cell-id=imports mode=decl
const std = @import("std");
```

```zig cell-id=hello mode=run depends-on=imports
const name = "Zig-lab";
std.debug.print("hello from {s}\n", .{name});
```

```zig cell-id=add-fn mode=decl
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```zig cell-id=answer mode=run depends-on=imports,add-fn
const answer = add(20, 22);
std.debug.print("answer = {}\n", .{answer});
```
````

Outputs may eventually be stored in a companion folder so the main notebook remains clean:

```text
examples/
  hello.ziglab
  hello.ziglab.outputs/
    hello.stdout.txt
    answer.stdout.txt
    diagnostics.json
```

## Future AI Assistant Preview

AI should be optional and reviewable. It should help the developer without hiding changes.

Example actions:

- Explain compiler error.
- Suggest test cases.
- Convert selected cells into `src/lib.zig`.
- Find unused imports.
- Generate benchmark cell.
- Summarize memory behavior.

Example assistant response inside Zig-lab:

```text
The error happens because `sum` expects []const i64, but the cell passed *const [4]i32.

Suggested fix:
  const values = [_]i64{ 10, 20, 30, 40 };
  sum(&values)

Apply as diff? [Review] [Apply]
```

## MVP Success Example

The first successful build of Zig-lab should be able to do this:

1. Open `examples/hello.ziglab`.
2. Show markdown and Zig cells.
3. Run only the selected cell.
4. Show output directly below that cell.
5. Run all cells when needed.
6. Show stdout and compiler diagnostics.
7. Save notebook state.
8. Export working Zig code.

That is enough to prove the foundation before adding the richer features.
