# Getting Started with ZNotebook

This guide walks you through running ZNotebook, using `.zignb` notebooks, and running code cells.

---

## 1. Install Zig

Install **Zig 0.16.0** or newer from [ziglang.org](https://ziglang.org/download/).

Verify:

```powershell
zig version
# 0.16.0
```

---

## 2. Start the Server

From the project root:

```powershell
zig build run
```

You should see:

```text
==================================================
   ZNotebook Server (Zig) http://127.0.0.1:8000
   Notebook files: *.zignb
==================================================
```

Open **http://localhost:8000** in your browser.

---

## 3. Open the Example Notebook

The UI loads **`hello.zignb`** by default. You can also pick it from the sidebar under **Saved Notebooks**.

The example covers:

- Markdown introduction cells
- A runnable code cell (`Shift + Enter`)
- A preview of `notebook.zig` rich output APIs

---

## 4. Create & Save a Notebook

1. Click **New Notebook** or edit the title field (e.g. `my_experiment`).
2. Add cells with **Code Cell** / **Markdown Cell** at the bottom.
3. Click **Save** — the file is written to `notebooks/my_experiment.zignb`.

Saved JSON includes:

```json
{
  "format": "zignb",
  "format_version": 1,
  "name": "my_experiment",
  "cells": [ ... ]
}
```

---

## 5. Markdown Cells

- Double-click a rendered markdown cell to edit.
- Press **Shift + Enter** to render.

---

## 6. Code Cells

Click **Run** on a code cell (or press **Shift + Enter**) to execute it. The server:

1. Merges declarations and statements from all cells up to the target.
2. Generates `temp/notebook_<name>.zig`.
3. Runs `zig run` (and `zig test` if the cell contains tests).
4. Returns stdout, stderr, and compiler errors mapped back to cell lines.

`std.debug.print` output appears in the cell stderr stream. Rich helpers from `notebook.zig` use prefixed stdout lines parsed by the UI.

---

## 7. Rich Output with `notebook.zig`

Import the helper library in code cells:

```zig
const nb = @import("notebook");
const std = @import("std");

nb.initOutput(io); // called automatically by generated main in Phase 2
std.debug.print("Plain text\n", .{});
nb.printHtml("<p><strong>Bold</strong> HTML block</p>");
nb.printMarkdown("## Inline markdown");
```

### HTML tables

```zig
const headers = [_][]const u8{ "Epoch", "Loss" };
const rows = [_][]const []const u8{
    [_][]const u8{ "1", "0.85" },
    [_][]const u8{ "2", "0.62" },
};
nb.printTable(&headers, &rows);
```

### SVG plots

```zig
const x = [_]f64{ 1, 2, 3, 4, 5 };
const y = [_]f64{ 2.0, 3.5, 3.1, 4.8, 5.2 };
try nb.plotLine("Training curve", &x, &y);
try nb.plotScatter("Scatter demo", &x, &y);
```

Output prefixes parsed by the UI:

| Prefix | Rendered as |
|--------|-------------|
| `[ZNB_HTML]` | HTML block |
| `[ZNB_MD]` | Markdown |
| `[ZNB_IMAGE]` | SVG or base64 PNG |

---

## 8. API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Web UI |
| GET | `/style.css`, `/app.js` | Frontend assets |
| GET | `/api/notebooks` | List saved notebooks |
| GET | `/api/notebook/{name}` | Load notebook JSON |
| POST | `/api/save` | Save notebook body |
| POST | `/api/run` | Run cells up to target index |

---

## 9. Troubleshooting

### Port already in use

Another process (or the old Rust server) may hold port 8000. Stop it or change `port` in `src/config.zig`.

### Notebook not found

Ensure the file exists as `notebooks/{name}.zignb`. Legacy `notebooks/{name}.znb` files still load.

### Frontend changes not visible

Restart `zig build run` after editing `frontend/*` — assets are loaded from disk at startup.

---

## Next Steps

- Read `doc/architecture.md` for the cell execution model.
- Try editing `notebooks/hello.zignb` directly in your editor.
