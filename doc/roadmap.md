# ZNotebook Development Roadmap

Phase-by-phase plan for ZNotebook — a super-fast, cell-based IDE for Zig.

---

## Phase 0: Zig 0.16 Library & Foundation ✅

Establish Zig-native building blocks.

- [x] Restructure project: `src/`, `lib/`, `build.zig`
- [x] Update `lib/notebook.zig` for Zig 0.16 `std.Io` (replace removed `std.io`)
- [x] Add `nb.initOutput(io)` hook for generated notebooks
- [x] Unit tests for notebook helpers
- [x] Define `.zignb` format constants in `src/config.zig`

---

## Phase 1: Native Zig HTTP Server & UI ✅

Single-binary server with notebook I/O.

- [x] `build.zig` → `znotebook` executable
- [x] TCP HTTP server on port 8000 (`src/http/`)
- [x] Serve frontend (Monaco UI)
- [x] REST API: list / load / save notebooks
- [x] `.zignb` primary extension; `.znb` legacy load
- [x] Example `notebooks/hello.zignb`
- [x] User guide: `doc/getting_started.md`
- [x] `/api/run` stub (returns Phase 2 message)

---

## Phase 2: Cell Execution Engine ✅

Port the execution model to Zig.

- [x] `src/engine/parser.zig` — split cells into decls vs statements
- [x] `src/engine/codegen.zig` — assemble `temp/notebook_*.zig` + source map
- [x] `src/engine/executor.zig` — spawn `zig run` / `zig test`
- [x] `/api/run` — full JSON response with stdout/stderr/errors
- [x] Error line mapping back to Monaco squiggles
- [x] Cell boundary markers via stdout/stderr (`[ZNB_CELL_START:id]`)

---

## Phase 3: Performance & Tooling (Next)

- [ ] Persistent `.zig-cache` in `temp/`
- [ ] Stable declaration ordering for cache hits
- [ ] CLI: `znotebook run hello.zignb --cell 3`
- [ ] ReleaseFast build profile & packaging
- [ ] Embed frontend assets in binary (optional)

---

## Phase 4: Cleanup ✅

- [x] Remove Rust backend (`Cargo.toml`, `src/main.rs`, `target/`)
- [x] Purge `temp/` generated scrap; keep directory via `.gitkeep`
- [x] Consolidate notebooks to `.zignb` (`hello`, `getting_started`)
- [x] Expand `.gitignore` for Zig artifacts

---

## Phase 5: Examples & ML/AI Notebooks

- [ ] Expanded tutorial notebook (tables, plots, state)
- [ ] CSV parsing example in Zig
- [ ] Statistical metrics demo
