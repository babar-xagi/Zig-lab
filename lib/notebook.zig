const std = @import("std");
const Io = std.Io;

/// Set by generated notebook `main` before helper calls (Phase 2 execution engine).
pub var io: ?Io = null;

threadlocal var stdout_buffer: [8192]u8 = undefined;
threadlocal var stdout_writer_state: ?Io.File.Writer = null;

/// Initialize stdout helpers. Generated notebooks call this at the start of `main`.
pub fn initOutput(io_instance: Io) void {
    io = io_instance;
    stdout_writer_state = Io.File.stdout().writer(io_instance, &stdout_buffer);
}

fn writer() ?*Io.Writer {
    if (stdout_writer_state) |*w| return &w.interface;
    return null;
}

fn writePrefix(comptime prefix: []const u8, payload: []const u8) void {
    if (writer()) |w| {
        w.print("{s}{s}\n", .{ prefix, payload }) catch {};
        w.flush() catch {};
        return;
    }
    // Fallback for tests without initOutput: emit on stderr so compile checks still run.
    std.debug.print("{s}{s}\n", .{ prefix, payload });
}

/// Print raw HTML to be rendered in the notebook.
pub fn printHtml(html: []const u8) void {
    writePrefix("[ZNB_HTML]", html);
}

/// Print Markdown text to be compiled and rendered in the notebook.
pub fn printMarkdown(md: []const u8) void {
    writePrefix("[ZNB_MD]", md);
}

/// Print base64 image data to be displayed in the notebook.
pub fn printImage(base64: []const u8) void {
    writePrefix("[ZNB_IMAGE]", base64);
}

/// Print an HTML table from headers and rows of strings.
pub fn printTable(headers: []const []const u8, rows: []const []const []const u8) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &list);
    defer aw.deinit();
    const w = &aw.writer;

    w.writeAll("<table><thead><tr>") catch return;
    for (headers) |h| {
        w.print("<th>{s}</th>", .{h}) catch return;
    }
    w.writeAll("</tr></thead><tbody>") catch return;

    for (rows) |row| {
        w.writeAll("<tr>") catch return;
        for (row) |cell| {
            w.print("<td>{s}</td>", .{cell}) catch return;
        }
        w.writeAll("</tr>") catch return;
    }
    w.writeAll("</tbody></table>") catch return;

    printHtml(list.items);
}

/// Generate a line plot from data arrays and output as SVG.
pub fn plotLine(title: []const u8, x: []const f64, y: []const f64) !void {
    try plotSvg(title, x, y, true);
}

/// Generate a scatter plot from data arrays and output as SVG.
pub fn plotScatter(title: []const u8, x: []const f64, y: []const f64) !void {
    try plotSvg(title, x, y, false);
}

fn plotSvg(title: []const u8, x: []const f64, y: []const f64, is_line: bool) !void {
    if (x.len == 0 or y.len == 0 or x.len != y.len) {
        std.debug.print("Error: Empty arrays or mismatched lengths (X: {}, Y: {})\n", .{ x.len, y.len });
        return;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var min_x = x[0];
    var max_x = x[0];
    var min_y = y[0];
    var max_y = y[0];

    for (x) |val| {
        if (val < min_x) min_x = val;
        if (val > max_x) max_x = val;
    }
    for (y) |val| {
        if (val < min_y) min_y = val;
        if (val > max_y) max_y = val;
    }

    if (min_x == max_x) {
        min_x -= 1.0;
        max_x += 1.0;
    }
    if (min_y == max_y) {
        min_y -= 1.0;
        max_y += 1.0;
    }

    const width: f64 = 600.0;
    const height: f64 = 380.0;
    const pad_left: f64 = 60.0;
    const pad_right: f64 = 30.0;
    const pad_top: f64 = 60.0;
    const pad_bottom: f64 = 50.0;

    const plot_w = width - pad_left - pad_right;
    const plot_h = height - pad_top - pad_bottom;

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &list);
    defer aw.deinit();
    const w = &aw.writer;

    try w.print(
        "<svg width=\"{d:.0}\" height=\"{d:.0}\" viewBox=\"0 0 {d:.0} {d:.0}\" style=\"background:#111115; border-radius:12px; border:1px solid rgba(255,255,255,0.06); font-family:inherit;\">\n",
        .{ width, height, width, height },
    );

    const y_ticks = 5;
    var i: usize = 0;
    while (i <= y_ticks) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(y_ticks));
        const val = min_y + t * (max_y - min_y);
        const y_pos = (height - pad_bottom) - t * plot_h;
        try w.print("  <line x1=\"{d:.1}\" y1=\"{d:.1}\" x2=\"{d:.1}\" y2=\"{d:.1}\" stroke=\"rgba(255,255,255,0.04)\" stroke-dasharray=\"3,3\" />\n", .{ pad_left, y_pos, width - pad_right, y_pos });
        try w.print("  <text x=\"{d:.1}\" y=\"{d:.1}\" fill=\"#64748b\" font-size=\"10\" text-anchor=\"end\" alignment-baseline=\"middle\">{d:.2}</text>\n", .{ pad_left - 10, y_pos, val });
    }

    const x_ticks = 5;
    var j: usize = 0;
    while (j <= x_ticks) : (j += 1) {
        const t = @as(f64, @floatFromInt(j)) / @as(f64, @floatFromInt(x_ticks));
        const val = min_x + t * (max_x - min_x);
        const x_pos = pad_left + t * plot_w;
        try w.print("  <line x1=\"{d:.1}\" y1=\"{d:.1}\" x2=\"{d:.1}\" y2=\"{d:.1}\" stroke=\"rgba(255,255,255,0.04)\" stroke-dasharray=\"3,3\" />\n", .{ x_pos, pad_top, x_pos, height - pad_bottom });
        try w.print("  <text x=\"{d:.1}\" y=\"{d:.1}\" fill=\"#64748b\" font-size=\"10\" text-anchor=\"middle\">{d:.2}</text>\n", .{ x_pos, height - pad_bottom + 20, val });
    }

    try w.print("  <text x=\"{d:.1}\" y=\"30\" fill=\"#ffffff\" font-weight=\"600\" font-size=\"15\" text-anchor=\"middle\">{s}</text>\n", .{ width / 2.0, title });

    const scale_x = struct {
        fn scale(v: f64, min: f64, max: f64, pw: f64, pl: f64) f64 {
            return pl + ((v - min) / (max - min)) * pw;
        }
    }.scale;

    const scale_y = struct {
        fn scale(v: f64, min: f64, max: f64, ph: f64, pb: f64, h: f64) f64 {
            return (h - pb) - ((v - min) / (max - min)) * ph;
        }
    }.scale;

    if (is_line) {
        try w.writeAll("  <polyline points=\"");
        for (x, 0..) |vx, idx| {
            const vy = y[idx];
            const px = scale_x(vx, min_x, max_x, plot_w, pad_left);
            const py = scale_y(vy, min_y, max_y, plot_h, pad_bottom, height);
            try w.print("{d:.1},{d:.1} ", .{ px, py });
        }
        try w.writeAll("\" fill=\"none\" stroke=\"#7c3aed\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\" />\n");
    }

    for (x, 0..) |vx, idx| {
        const vy = y[idx];
        const px = scale_x(vx, min_x, max_x, plot_w, pad_left);
        const py = scale_y(vy, min_y, max_y, plot_h, pad_bottom, height);
        const fill_color = if (is_line) "#7c3aed" else "#06b6d4";
        const stroke_color = if (is_line) "#a78bfa" else "#22d3ee";
        try w.print("  <circle cx=\"{d:.1}\" cy=\"{d:.1}\" r=\"4\" fill=\"{s}\" stroke=\"{s}\" stroke-width=\"1\" />\n", .{ px, py, fill_color, stroke_color });
    }

    try w.writeAll("</svg>");
    printImage(list.items);
}

test "notebook helpers compile" {
    printHtml("<p>ok</p>");
    printMarkdown("# Title");
    printImage("<svg></svg>");

    const headers = [_][]const u8{ "A", "B" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "1", "2" },
    };
    printTable(&headers, &rows);
}

test "plot helpers compile" {
    const x = [_]f64{ 1, 2, 3 };
    const y = [_]f64{ 2, 4, 3 };
    try plotLine("Demo", &x, &y);
}
