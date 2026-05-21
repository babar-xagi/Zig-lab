const std = @import("std");
const Io = std.Io;

pub const CellKind = enum {
    markdown,
    zig,
    other,
};

pub const Cell = struct {
    index: usize,
    kind: CellKind,
    language: []const u8,
    id: ?[]const u8,
    depends_on: []const []const u8,
    source: []const u8,
    source_start_line: usize,

    pub fn displayName(cell: Cell) []const u8 {
        return cell.id orelse cell.language;
    }
};

pub const Notebook = struct {
    allocator: std.mem.Allocator,
    path: []u8,
    source: []u8,
    cells: []Cell,

    pub fn deinit(self: *Notebook) void {
        for (self.cells) |cell| {
            if (cell.depends_on.len > 0) self.allocator.free(cell.depends_on);
        }
        self.allocator.free(self.cells);
        self.allocator.free(self.source);
        self.allocator.free(self.path);
        self.* = undefined;
    }

    pub fn findCell(self: Notebook, id: []const u8) ?Cell {
        for (self.cells) |cell| {
            if (cell.id) |cell_id| {
                if (std.mem.eql(u8, cell_id, id)) return cell;
            }
        }
        return null;
    }

    pub fn countKind(self: Notebook, kind: CellKind) usize {
        var count: usize = 0;
        for (self.cells) |cell| {
            if (cell.kind == kind) count += 1;
        }
        return count;
    }
};

pub fn load(gpa: std.mem.Allocator, io: Io, path: []const u8) !Notebook {
    const data = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
    errdefer gpa.free(data);

    const owned_path = try gpa.dupe(u8, path);
    errdefer gpa.free(owned_path);

    var cells: std.ArrayList(Cell) = .empty;
    errdefer cells.deinit(gpa);

    try parseCells(gpa, data, &cells);

    return .{
        .allocator = gpa,
        .path = owned_path,
        .source = data,
        .cells = try cells.toOwnedSlice(gpa),
    };
}

fn parseCells(gpa: std.mem.Allocator, data: []const u8, cells: *std.ArrayList(Cell)) !void {
    var offset: usize = 0;
    var in_cell = false;
    var cell_start: usize = 0;
    var cell_language: []const u8 = "";
    var cell_id: ?[]const u8 = null;
    var cell_depends_on: []const []const u8 = &.{};
    var cell_kind: CellKind = .other;
    var cell_source_start_line: usize = 1;
    var line_number: usize = 1;

    while (offset < data.len) : (line_number += 1) {
        const line_start = offset;
        const newline_index = std.mem.indexOfScalarPos(u8, data, offset, '\n') orelse data.len;
        const line_end = if (newline_index > line_start and data[newline_index - 1] == '\r') newline_index - 1 else newline_index;
        const line = data[line_start..line_end];
        offset = if (newline_index < data.len) newline_index + 1 else data.len;

        if (!std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), "```")) continue;

        const fence_line = std.mem.trim(u8, line, " \t\r");
        if (in_cell) {
            if (std.mem.eql(u8, fence_line, "```")) {
                try cells.append(gpa, .{
                    .index = cells.items.len,
                    .kind = cell_kind,
                    .language = cell_language,
                    .id = cell_id,
                    .depends_on = cell_depends_on,
                    .source = data[cell_start..line_start],
                    .source_start_line = cell_source_start_line,
                });
                cell_depends_on = &.{};
                in_cell = false;
            }
            continue;
        }

        const header = std.mem.trim(u8, fence_line[3..], " \t");
        if (header.len == 0) continue;

        var tokens = std.mem.tokenizeAny(u8, header, " \t");
        const language = tokens.next() orelse continue;
        const kind = kindFromLanguage(language);
        if (kind == .other) continue;

        var id: ?[]const u8 = null;
        var depends_on: []const []const u8 = &.{};
        while (tokens.next()) |token| {
            if (std.mem.startsWith(u8, token, "cell-id=")) {
                id = token["cell-id=".len..];
            } else if (std.mem.startsWith(u8, token, "id=")) {
                id = token["id=".len..];
            } else if (std.mem.startsWith(u8, token, "depends-on=")) {
                depends_on = try parseDepends(gpa, token["depends-on=".len..]);
            }
        }

        in_cell = true;
        cell_start = offset;
        cell_language = language;
        cell_id = id;
        cell_depends_on = depends_on;
        cell_kind = kind;
        cell_source_start_line = line_number + 1;
    }

    if (in_cell and cell_depends_on.len > 0) {
        gpa.free(cell_depends_on);
    }
}

fn kindFromLanguage(language: []const u8) CellKind {
    if (std.mem.eql(u8, language, "zig")) return .zig;
    if (std.mem.eql(u8, language, "markdown")) return .markdown;
    if (std.mem.eql(u8, language, "md")) return .markdown;
    return .other;
}

fn parseDepends(gpa: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var deps: std.ArrayList([]const u8) = .empty;
    errdefer deps.deinit(gpa);

    var parts = std.mem.splitScalar(u8, raw, ',');
    while (parts.next()) |part| {
        const dep = std.mem.trim(u8, part, " \t\r");
        if (dep.len > 0) {
            try deps.append(gpa, dep);
        }
    }

    if (deps.items.len == 0) return &.{};
    return deps.toOwnedSlice(gpa);
}

test "parse fenced notebook cells" {
    const input =
        \\```markdown cell-id=intro
        \\# Hello
        \\```
        \\
        \\```zig cell-id=hello
        \\const std = @import("std");
        \\```
        \\
    ;

    var cells: std.ArrayList(Cell) = .empty;
    defer cells.deinit(std.testing.allocator);

    try parseCells(std.testing.allocator, input, &cells);

    try std.testing.expectEqual(@as(usize, 2), cells.items.len);
    try std.testing.expectEqual(CellKind.markdown, cells.items[0].kind);
    try std.testing.expectEqual(CellKind.zig, cells.items[1].kind);
    try std.testing.expectEqualStrings("intro", cells.items[0].id.?);
    try std.testing.expectEqualStrings("hello", cells.items[1].id.?);
    try std.testing.expectEqual(@as(usize, 2), cells.items[0].source_start_line);

    for (cells.items) |cell| {
        if (cell.depends_on.len > 0) std.testing.allocator.free(cell.depends_on);
    }
}

test "parse cell dependencies" {
    const input =
        \\```zig cell-id=answer depends-on=imports,add-fn
        \\const answer = add(20, 22);
        \\```
        \\
    ;

    var cells: std.ArrayList(Cell) = .empty;
    defer cells.deinit(std.testing.allocator);

    try parseCells(std.testing.allocator, input, &cells);
    defer {
        for (cells.items) |cell| {
            if (cell.depends_on.len > 0) std.testing.allocator.free(cell.depends_on);
        }
    }

    try std.testing.expectEqual(@as(usize, 1), cells.items.len);
    try std.testing.expectEqual(@as(usize, 2), cells.items[0].depends_on.len);
    try std.testing.expectEqualStrings("imports", cells.items[0].depends_on[0]);
    try std.testing.expectEqualStrings("add-fn", cells.items[0].depends_on[1]);
}
