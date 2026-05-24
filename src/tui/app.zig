// Zig-lab TUI application — Phase 4 interactive notebook viewer and runner.
// Layout (top to bottom):
//   header bar | cell list | divider | source preview | divider | output panel | status bar

const std = @import("std");
const Io = std.Io;

const notebook = @import("../notebook.zig");
const win = @import("win.zig");

// ─── Frame writer ───────────────────────────────────────────────────────────
//
// A thin writer-like wrapper over ArrayList(u8) that is compatible with the
// Zig 0.16 ArrayList API (allocator passed per-operation, no stored writer).

const FrameWriter = struct {
    buf: *std.ArrayList(u8),
    gpa: std.mem.Allocator,

    pub fn writeAll(self: FrameWriter, bytes: []const u8) !void {
        try self.buf.appendSlice(self.gpa, bytes);
    }

    pub fn writeByte(self: FrameWriter, byte: u8) !void {
        try self.buf.append(self.gpa, byte);
    }

    pub fn print(self: FrameWriter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.gpa, fmt, args);
        defer self.gpa.free(s);
        try self.buf.appendSlice(self.gpa, s);
    }
};

// ─── ANSI escape helpers ─────────────────────────────────────────────────────

fn moveTo(w: anytype, row: u16, col: u16) !void {
    try w.print("\x1b[{d};{d}H", .{ row, col });
}

fn clearLine(w: anytype) !void {
    try w.writeAll("\x1b[K");
}

fn hideCursor(w: anytype) !void {
    try w.writeAll("\x1b[?25l");
}

fn showCursor(w: anytype) !void {
    try w.writeAll("\x1b[?25h");
}

fn reset(w: anytype) !void {
    try w.writeAll("\x1b[0m");
}

fn styleHeader(w: anytype) !void {
    try w.writeAll("\x1b[44;1;37m"); // bold white on blue
}

fn styleSelected(w: anytype) !void {
    try w.writeAll("\x1b[1;96m"); // bold bright-cyan
}

fn styleDivider(w: anytype) !void {
    try w.writeAll("\x1b[2;34m"); // dim blue
}

fn styleStatus(w: anytype) !void {
    try w.writeAll("\x1b[7m"); // reverse video
}

fn styleError(w: anytype) !void {
    try w.writeAll("\x1b[31m"); // red
}

// ─── Keyboard input ──────────────────────────────────────────────────────────

const Key = union(enum) {
    up,
    down,
    page_up,
    page_down,
    home,
    end,
    enter,
    escape,
    char: u8,
    unknown,
};

fn readKey(console: win.Console) !Key {
    var buf: [8]u8 = undefined;
    const n = try console.readInput(&buf);
    if (n == 0) return .unknown;

    if (buf[0] == '\x1b') {
        if (n >= 3 and buf[1] == '[') {
            return switch (buf[2]) {
                'A' => .up,
                'B' => .down,
                'H' => .home,
                'F' => .end,
                '5' => if (n >= 4 and buf[3] == '~') Key.page_up else .unknown,
                '6' => if (n >= 4 and buf[3] == '~') Key.page_down else .unknown,
                else => .unknown,
            };
        }
        return .escape;
    }

    return switch (buf[0]) {
        '\r', '\n' => .enter,
        else => Key{ .char = buf[0] },
    };
}

// ─── Per-cell output capture ─────────────────────────────────────────────────

const CellResult = struct {
    cell_label: []u8, // cell id or "(all)" etc.
    output: []u8, // text to show in the output panel
    succeeded: bool,

    fn deinit(self: *CellResult, gpa: std.mem.Allocator) void {
        gpa.free(self.cell_label);
        gpa.free(self.output);
        self.* = undefined;
    }
};

// ─── App ─────────────────────────────────────────────────────────────────────

pub const App = struct {
    gpa: std.mem.Allocator,
    io: Io,
    self_exe: []const u8, // argv[0] — used to spawn runner subprocesses
    nb: notebook.Notebook,
    console: win.Console,

    // Selection & scroll state.
    selected: usize = 0,
    cell_scroll: usize = 0,
    src_scroll: usize = 0,
    out_scroll: usize = 0,

    // Execution result.
    result: ?CellResult = null,

    // Status bar text.
    status_msg: []const u8 = "Ready.  ↑↓:Navigate  Enter:Run  A:Run All  E:Export  R:Reload  Q:Quit",
    status_ok: bool = true,

    // Frame buffer (rebuilt each draw).
    frame: std.ArrayList(u8),

    pub fn init(gpa: std.mem.Allocator, io: Io, self_exe: []const u8, nb: notebook.Notebook, console: win.Console) App {
        return .{
            .gpa = gpa,
            .io = io,
            .self_exe = self_exe,
            .nb = nb,
            .console = console,
            .frame = .empty,
        };
    }

    pub fn deinit(self: *App) void {
        if (self.result) |*r| r.deinit(self.gpa);
        self.frame.deinit(self.gpa);
    }

    // ── Main event loop ───────────────────────────────────────────────────────

    pub fn run(self: *App) !void {
        // Hide cursor for clean rendering; restore on exit.
        try self.console.writeOutput("\x1b[?25l");
        defer self.console.writeOutput("\x1b[?25h\x1b[0m") catch {};

        try self.draw();

        while (true) {
            const key = readKey(self.console) catch .unknown;
            const quit = try self.handleKey(key);
            if (quit) break;
            try self.draw();
        }
    }

    // ── Key dispatch ──────────────────────────────────────────────────────────

    fn handleKey(self: *App, key: Key) !bool {
        const size = self.console.getSize();

        switch (key) {
            .char => |c| switch (c) {
                'q', 'Q', '\x03', '\x11' => return true, // q / Q / Ctrl+C / Ctrl+Q
                'a', 'A' => try self.runAll(),
                'e', 'E' => try self.exportNb(),
                'r', 'R' => try self.reloadNb(),
                'k' => if (self.src_scroll > 0) {
                    self.src_scroll -= 1;
                },
                'j' => self.src_scroll += 1,
                'u' => if (self.out_scroll > 0) {
                    self.out_scroll -= 1;
                },
                'n' => self.out_scroll += 1,
                else => {},
            },
            .up => {
                if (self.selected > 0) {
                    self.selected -= 1;
                    self.src_scroll = 0;
                    self.adjustCellScroll(size.rows);
                }
            },
            .down => {
                if (self.selected + 1 < self.nb.cells.len) {
                    self.selected += 1;
                    self.src_scroll = 0;
                    self.adjustCellScroll(size.rows);
                }
            },
            .page_up => {
                const step = self.listRows(size.rows);
                self.selected -|= step;
                self.src_scroll = 0;
                self.adjustCellScroll(size.rows);
            },
            .page_down => {
                const step = self.listRows(size.rows);
                self.selected = @min(self.selected + step, self.nb.cells.len -| 1);
                self.src_scroll = 0;
                self.adjustCellScroll(size.rows);
            },
            .home => {
                self.selected = 0;
                self.cell_scroll = 0;
                self.src_scroll = 0;
            },
            .end => {
                if (self.nb.cells.len > 0) self.selected = self.nb.cells.len - 1;
                self.src_scroll = 0;
                self.adjustCellScroll(size.rows);
            },
            .enter => try self.runSelected(),
            .escape, .unknown => {},
        }
        return false;
    }

    // ── Cell execution ────────────────────────────────────────────────────────

    fn runSelected(self: *App) !void {
        if (self.nb.cells.len == 0) return;
        const cell = self.nb.cells[self.selected];

        if (cell.kind != .zig) {
            self.setStatus("Selected cell is not executable Zig.", false);
            return;
        }
        const cell_id = cell.id orelse {
            self.setStatus("Cell has no ID (add cell-id= to run it).", false);
            return;
        };

        self.setStatus("Running cell…", true);
        try self.draw();

        const extra = &[_][]const u8{ "run", self.nb.path, "--cell", cell_id, "--save-outputs" };
        const res = try self.spawnRunner(extra);
        defer self.gpa.free(res.out);
        defer self.gpa.free(res.err);

        // Prefer the saved clean output file; fall back to runner stdout+stderr.
        const text = (try self.readSavedOutput(cell_id)) orelse
            try self.mergeText(res.out, res.err);

        try self.storeResult(cell_id, text, res.ok);

        if (res.ok) {
            self.setStatus("Ran successfully.", true);
        } else {
            self.setStatus("Cell failed — see output below.", false);
        }
    }

    fn runAll(self: *App) !void {
        self.setStatus("Running all cells…", true);
        try self.draw();

        const extra = &[_][]const u8{ "run", self.nb.path };
        const res = try self.spawnRunner(extra);
        defer self.gpa.free(res.out);
        defer self.gpa.free(res.err);

        const text = try self.mergeText(res.out, res.err);
        try self.storeResult("(all)", text, res.ok);

        if (res.ok) {
            self.setStatus("All cells ran successfully.", true);
        } else {
            self.setStatus("Run failed — see output below.", false);
        }
    }

    fn exportNb(self: *App) !void {
        self.setStatus("Exporting…", true);
        try self.draw();

        const extra = &[_][]const u8{ "export", self.nb.path };
        const res = try self.spawnRunner(extra);
        defer self.gpa.free(res.out);
        defer self.gpa.free(res.err);

        const text = try self.mergeText(res.out, res.err);
        try self.storeResult("(export)", text, res.ok);

        if (res.ok) {
            self.setStatus("Exported successfully.", true);
        } else {
            self.setStatus("Export failed.", false);
        }
    }

    fn reloadNb(self: *App) !void {
        const fresh = notebook.load(self.gpa, self.io, self.nb.path) catch {
            self.setStatus("Reload failed — could not parse notebook.", false);
            return;
        };
        self.nb.deinit();
        self.nb = fresh;
        if (self.nb.cells.len > 0 and self.selected >= self.nb.cells.len) {
            self.selected = self.nb.cells.len - 1;
        }
        self.src_scroll = 0;
        self.setStatus("Notebook reloaded.", true);
    }

    // ── Subprocess helpers ────────────────────────────────────────────────────

    const SpawnResult = struct { out: []u8, err: []u8, ok: bool };

    fn spawnRunner(self: *App, extra_args: []const []const u8) !SpawnResult {
        // Build argv: [self_exe, <extra_args...>]
        var argv = try self.gpa.alloc([]const u8, 1 + extra_args.len);
        defer self.gpa.free(argv);
        argv[0] = self.self_exe;
        @memcpy(argv[1..], extra_args);

        const limit = 4 * 1024 * 1024;
        const result = try std.process.run(self.gpa, self.io, .{
            .argv = argv,
            .stdout_limit = .limited(limit),
            .stderr_limit = .limited(limit),
        });
        const ok = switch (result.term) {
            .exited => |c| c == 0,
            else => false,
        };
        return .{ .out = result.stdout, .err = result.stderr, .ok = ok };
    }

    fn readSavedOutput(self: *App, cell_id: []const u8) !?[]u8 {
        const path = try std.fmt.allocPrint(
            self.gpa,
            "{s}.outputs/{s}.output.txt",
            .{ self.nb.path, cell_id },
        );
        defer self.gpa.free(path);
        return Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(1024 * 1024)) catch null;
    }

    fn mergeText(self: *App, a: []const u8, b: []const u8) ![]u8 {
        if (b.len == 0) return self.gpa.dupe(u8, a);
        if (a.len == 0) return self.gpa.dupe(u8, b);
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(self.gpa, a);
        if (!std.mem.endsWith(u8, a, "\n")) try buf.append(self.gpa, '\n');
        try buf.appendSlice(self.gpa, b);
        return buf.toOwnedSlice(self.gpa);
    }

    fn storeResult(self: *App, label: []const u8, text: []u8, ok: bool) !void {
        if (self.result) |*old| old.deinit(self.gpa);
        self.result = .{
            .cell_label = try self.gpa.dupe(u8, label),
            .output = text,
            .succeeded = ok,
        };
        self.out_scroll = 0;
    }

    fn setStatus(self: *App, msg: []const u8, ok: bool) void {
        self.status_msg = msg;
        self.status_ok = ok;
    }

    // ── Layout math ───────────────────────────────────────────────────────────
    //
    // Row allocation (all 1-based, exclusive end):
    //   Row 1         : header
    //   Row 2..Lr+1   : cell list  (Lr rows)
    //   Row Lr+2      : divider "Source"
    //   Row Lr+3..Sr  : source     (Sr rows)
    //   Row Sr+1      : divider "Output"
    //   Row Sr+2..N-1 : output panel
    //   Row N         : status bar

    fn listRows(self: *App, total: u16) usize {
        _ = self;
        const avail = @as(usize, total) -| 4; // header + status + 2 dividers
        return @max(3, avail / 3);
    }

    fn srcRows(self: *App, total: u16) usize {
        _ = self;
        const avail = @as(usize, total) -| 4;
        return @max(3, avail / 3);
    }

    fn adjustCellScroll(self: *App, total: u16) void {
        const vis = self.listRows(total);
        if (self.selected < self.cell_scroll) {
            self.cell_scroll = self.selected;
        } else if (self.selected >= self.cell_scroll + vis) {
            self.cell_scroll = self.selected - vis + 1;
        }
    }

    // ── Rendering ─────────────────────────────────────────────────────────────

    pub fn draw(self: *App) !void {
        const size = self.console.getSize();
        const cols = size.cols;
        const rows = size.rows;

        const lr = self.listRows(rows);
        const sr = self.srcRows(rows);

        // 1-based row positions.
        const list_r1: u16 = 2;
        const list_r2: u16 = @intCast(list_r1 + lr); // exclusive
        const divA: u16 = list_r2;
        const src_r1: u16 = list_r2 + 1;
        const src_r2: u16 = @intCast(src_r1 + sr);
        const divB: u16 = src_r2;
        const out_r1: u16 = src_r2 + 1;
        const status_r: u16 = rows;
        const out_r2: u16 = if (status_r > out_r1) status_r else out_r1 + 1;

        self.frame.clearRetainingCapacity();
        const w = FrameWriter{ .buf = &self.frame, .gpa = self.gpa };

        try hideCursor(w);
        try w.writeAll("\x1b[H"); // cursor home

        try self.renderHeader(w, cols, 1);
        try self.renderCellList(w, cols, list_r1, list_r2);
        try self.renderDivider(w, cols, divA, "Source");
        try self.renderSource(w, cols, src_r1, src_r2);
        try self.renderDivider(w, cols, divB, "Output");
        try self.renderOutput(w, cols, out_r1, out_r2);
        try self.renderStatusBar(w, cols, status_r);

        // Write the frame buffer directly via the console handle.
        try self.console.writeOutput(self.frame.items);
    }

    fn renderHeader(self: *App, w: anytype, cols: u16, row: u16) !void {
        try moveTo(w, row, 1);
        try styleHeader(w);

        const left = try std.fmt.allocPrint(self.gpa, "  Zig-lab  ·  {s}  ", .{self.nb.path});
        defer self.gpa.free(left);

        const llen = @min(left.len, @as(usize, cols));
        try w.writeAll(left[0..llen]);
        try padTo(w, llen, @as(usize, cols));
        try reset(w);
    }

    fn renderCellList(self: *App, w: anytype, cols: u16, r1: u16, r2: u16) !void {
        var row = r1;
        var idx = self.cell_scroll;
        while (row < r2) : (row += 1) {
            try moveTo(w, row, 1);
            try reset(w);

            if (idx < self.nb.cells.len) {
                const cell = self.nb.cells[idx];
                const sel = (idx == self.selected);

                if (sel) try styleSelected(w);

                var line: std.ArrayList(u8) = .empty;
                defer line.deinit(self.gpa);
                const lw = FrameWriter{ .buf = &line, .gpa = self.gpa };

                const arrow: []const u8 = if (sel) "►" else " ";
                try lw.print(" {s} [{d}] {s:<9} {s}", .{
                    arrow,
                    idx + 1,
                    cellKindLabel(cell),
                    cell.displayName(),
                });
                if (cell.depends_on.len > 0) {
                    try lw.writeAll("  →");
                    for (cell.depends_on, 0..) |dep, i| {
                        if (i > 0) try lw.writeByte(',');
                        try lw.print(" {s}", .{dep});
                    }
                }

                const text = line.items;
                const show = @min(text.len, @as(usize, cols) -| 1);
                try w.writeAll(text[0..show]);
                try padTo(w, show, @as(usize, cols));
                if (sel) try reset(w);
            } else {
                try padTo(w, 0, @as(usize, cols));
            }
            try clearLine(w);
            idx += 1;
        }
    }

    fn renderDivider(self: *App, w: anytype, cols: u16, row: u16, label: []const u8) !void {
        try moveTo(w, row, 1);
        try styleDivider(w);

        // "── Label ──────────"
        const label_part = try std.fmt.allocPrint(self.gpa, "── {s} ", .{label});
        defer self.gpa.free(label_part);

        const used = label_part.len;
        try w.writeAll(label_part);
        const rem = @as(usize, cols) -| used;
        var i: usize = 0;
        while (i < rem) : (i += 1) try w.writeByte('-');

        try reset(w);
        try clearLine(w);
    }

    fn renderSource(self: *App, w: anytype, cols: u16, r1: u16, r2: u16) !void {
        const source: []const u8 = if (self.nb.cells.len > 0)
            self.nb.cells[self.selected].source
        else
            "";

        var lines: std.ArrayList([]const u8) = .empty;
        defer lines.deinit(self.gpa);
        var it = std.mem.splitScalar(u8, source, '\n');
        while (it.next()) |ln| try lines.append(self.gpa, ln);

        var row = r1;
        var li: usize = self.src_scroll;
        while (row < r2) : (row += 1) {
            try moveTo(w, row, 1);
            try reset(w);
            if (li < lines.items.len) {
                const ln = lines.items[li];
                const show = @min(ln.len, @as(usize, cols) -| 2);
                try w.writeAll("  ");
                try w.writeAll(ln[0..show]);
            }
            try clearLine(w);
            li += 1;
        }
    }

    fn renderOutput(self: *App, w: anytype, cols: u16, r1: u16, r2: u16) !void {
        const text: []const u8 = if (self.result) |r| r.output else "(not run yet — press Enter to run selected cell)";
        const ok: bool = if (self.result) |r| r.succeeded else true;

        var lines: std.ArrayList([]const u8) = .empty;
        defer lines.deinit(self.gpa);
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |ln| try lines.append(self.gpa, ln);

        var row = r1;
        var li: usize = self.out_scroll;
        while (row < r2) : (row += 1) {
            try moveTo(w, row, 1);
            try reset(w);
            if (li < lines.items.len) {
                const ln = lines.items[li];
                const show = @min(ln.len, @as(usize, cols) -| 2);
                if (!ok) try styleError(w);
                try w.writeAll("  ");
                try w.writeAll(ln[0..show]);
                if (!ok) try reset(w);
            }
            try clearLine(w);
            li += 1;
        }
    }

    fn renderStatusBar(self: *App, w: anytype, cols: u16, row: u16) !void {
        try moveTo(w, row, 1);
        try styleStatus(w);

        const msg = self.status_msg;
        const show = @min(msg.len, @as(usize, cols));
        try w.writeAll(msg[0..show]);
        try padTo(w, show, @as(usize, cols));

        try reset(w);
    }
};

// ── Rendering utilities ───────────────────────────────────────────────────────

fn padTo(w: anytype, current_len: usize, target: usize) !void {
    if (target <= current_len) return;
    var i: usize = current_len;
    while (i < target) : (i += 1) try w.writeByte(' ');
}

fn cellKindLabel(cell: notebook.Cell) []const u8 {
    return switch (cell.kind) {
        .markdown => "markdown ",
        .zig => switch (cell.mode) {
            .decl => "zig/decl ",
            .run => "zig/run  ",
            .test_ => "zig/test ",
            .auto => "zig      ",
        },
        .other => "other    ",
    };
}
