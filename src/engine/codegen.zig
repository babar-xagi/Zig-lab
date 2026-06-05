const std = @import("std");
const parser = @import("parser.zig");

pub const SourceMapItem = struct {
    cell_idx: ?usize,
    line_in_cell: ?usize,
};

pub const StmtEntry = struct {
    lines: []const []const u8,
    cell_idx: usize,
    start_line: usize,
};

pub const DeclEntry = struct {
    lines: []const []const u8,
    cell_idx: usize,
    start_line: usize,
};

pub const CellInput = struct {
    id: []const u8,
    cell_type: []const u8,
    source: []const u8,
};

pub const Generated = struct {
    code: []const u8,
    source_map: []SourceMapItem,
    temp_filename: []const u8,
    has_statements: bool,
    has_tests: bool,

    pub fn deinit(self: *Generated, gpa: std.mem.Allocator) void {
        gpa.free(self.code);
        gpa.free(self.source_map);
        gpa.free(self.temp_filename);
    }
};

pub fn generate(
    gpa: std.mem.Allocator,
    cells: []const CellInput,
    target_index: usize,
    notebook_name: []const u8,
) !Generated {
    var global_decls = std.StringHashMap(DeclEntry).init(gpa);
    defer {
        var it = global_decls.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.lines) |l| gpa.free(l);
            gpa.free(entry.value_ptr.lines);
            gpa.free(entry.key_ptr.*);
        }
        global_decls.deinit();
    }

    var statements: std.ArrayList(StmtEntry) = .empty;
    defer {
        for (statements.items) |s| {
            for (s.lines) |l| gpa.free(l);
            gpa.free(s.lines);
        }
        statements.deinit(gpa);
    }

    if (cells.len == 0) {
        return .{
            .code = try gpa.dupe(u8, ""),
            .source_map = try gpa.alloc(SourceMapItem, 0),
            .temp_filename = try std.fmt.allocPrint(gpa, "notebook_untitled.zig", .{}),
            .has_statements = false,
            .has_tests = false,
        };
    }

    const end = @min(target_index, cells.len - 1);
    var idx: usize = 0;
    while (idx <= end) : (idx += 1) {
        const cell = cells[idx];
        if (!std.mem.eql(u8, cell.cell_type, "code")) continue;

        const blocks = try parser.splitTopLevelBlocks(gpa, cell.source);
        defer parser.freeBlocks(gpa, blocks);

        for (blocks) |block| {
            if (block.block_type == .decl) {
                var key_owned: ?[]u8 = null;
                defer if (key_owned) |k| gpa.free(k);

                var block_lines: std.ArrayList([]const u8) = .empty;
                errdefer {
                    for (block_lines.items) |l| gpa.free(l);
                    block_lines.deinit(gpa);
                }

                if (block.name != null and std.mem.eql(u8, block.name.?, "main")) {
                    const sanitized_id = try sanitizeId(gpa, cell.id);
                    defer gpa.free(sanitized_id);
                    key_owned = try std.fmt.allocPrint(gpa, "__znb_user_main_{s}", .{sanitized_id});
                    const new_fn = try std.fmt.allocPrint(gpa, "fn __znb_user_main_{s}", .{sanitized_id});
                    defer gpa.free(new_fn);

                    for (block.lines) |line| {
                        if (std.mem.indexOf(u8, line, "fn main") != null) {
                            var out: std.ArrayList(u8) = .empty;
                            defer out.deinit(gpa);
                            var parts = std.mem.splitSequence(u8, line, "fn main");
                            var first = true;
                            while (parts.next()) |part| {
                                if (!first) try out.appendSlice(gpa, new_fn);
                                try out.appendSlice(gpa, part);
                                first = false;
                            }
                            try block_lines.append(gpa, try out.toOwnedSlice(gpa));
                        } else {
                            try block_lines.append(gpa, try gpa.dupe(u8, line));
                        }
                    }

                    const call_line = try std.fmt.allocPrint(gpa, "try __znb_call_user_main({s});", .{key_owned.?});
                    var call_lines = [_][]const u8{call_line};
                    try statements.append(gpa, .{
                        .lines = try gpa.dupe([]const u8, &call_lines),
                        .cell_idx = idx,
                        .start_line = block.start_line,
                    });
                } else {
                    if (block.name != null and std.mem.eql(u8, block.name.?, "std")) {
                        continue;
                    }
                    key_owned = if (block.name) |n|
                        try gpa.dupe(u8, n)
                    else
                        try std.fmt.allocPrint(gpa, "decl_{s}_{d}", .{ cell.id, block.start_line });

                    for (block.lines) |line| {
                        try block_lines.append(gpa, try gpa.dupe(u8, line));
                    }
                }

                const key = key_owned.?;
                if (global_decls.get(key)) |old| {
                    for (old.lines) |l| gpa.free(l);
                    gpa.free(old.lines);
                }
                const key_copy = try gpa.dupe(u8, key);
                try global_decls.put(key_copy, .{
                    .lines = try block_lines.toOwnedSlice(gpa),
                    .cell_idx = idx,
                    .start_line = block.start_line,
                });
            } else {
                var dup_lines: std.ArrayList([]const u8) = .empty;
                defer dup_lines.deinit(gpa);
                for (block.lines) |line| try dup_lines.append(gpa, try gpa.dupe(u8, line));
                try statements.append(gpa, .{
                    .lines = try dup_lines.toOwnedSlice(gpa),
                    .cell_idx = idx,
                    .start_line = block.start_line,
                });
            }
        }
    }

    var gen: std.ArrayList(u8) = .empty;
    var source_map: std.ArrayList(SourceMapItem) = .empty;
    errdefer gen.deinit(gpa);
    errdefer source_map.deinit(gpa);

    const W = struct {
        fn lines(
            gpa2: std.mem.Allocator,
            code: *std.ArrayList(u8),
            sm: *std.ArrayList(SourceMapItem),
            ls: []const []const u8,
            c_idx: ?usize,
            s_line: ?usize,
        ) !void {
            for (ls, 0..) |line, i| {
                try code.appendSlice(gpa2, line);
                try code.append(gpa2, '\n');
                try sm.append(gpa2, .{
                    .cell_idx = c_idx,
                    .line_in_cell = if (s_line) |sl| sl + i else null,
                });
            }
        }
    };

    try W.lines(gpa, &gen, &source_map, &.{"const std = @import(\"std\");", ""}, null, null);

    try W.lines(gpa, &gen, &source_map, &.{
        "const nb = @import(\"notebook.zig\");",
        "",
        "fn __znb_call_user_main(comptime func: anytype) !void {",
        "    const return_type = @typeInfo(@TypeOf(func)).@\"fn\".return_type.?;",
        "    switch (@typeInfo(return_type)) {",
        "        .error_union => try func(),",
        "        else => func(),",
        "    }",
        "}",
        "",
        "fn __znb_cell_marker(comptime tag: []const u8, cell_id: []const u8, io: std.Io) void {",
        "    var out_buf: [256]u8 = undefined;",
        "    var out_wr = std.Io.File.stdout().writer(io, &out_buf);",
        "    out_wr.interface.print(\"[ZNB_CELL_{s}:{s}]\\n\", .{ tag, cell_id }) catch {};",
        "    out_wr.interface.flush() catch {};",
        "    var err_buf: [256]u8 = undefined;",
        "    var err_wr = std.Io.File.stderr().writer(io, &err_buf);",
        "    err_wr.interface.print(\"[ZNB_CELL_{s}:{s}]\\n\", .{ tag, cell_id }) catch {};",
        "    err_wr.interface.flush() catch {};",
        "}",
        "",
    }, null, null);

    var decl_keys: std.ArrayList([]const u8) = .empty;
    defer {
        for (decl_keys.items) |k| gpa.free(k);
        decl_keys.deinit(gpa);
    }
    {
        var it = global_decls.keyIterator();
        while (it.next()) |k| try decl_keys.append(gpa, try gpa.dupe(u8, k.*));
    }
    std.mem.sort([]const u8, decl_keys.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lt);

    for (decl_keys.items) |key| {
        const entry = global_decls.get(key).?;
        try W.lines(gpa, &gen, &source_map, entry.lines, entry.cell_idx, entry.start_line);
        try W.lines(gpa, &gen, &source_map, &.{""}, null, null);
    }

    try W.lines(gpa, &gen, &source_map, &.{"pub fn main(init: std.process.Init) !void {"}, null, null);
    try W.lines(gpa, &gen, &source_map, &.{"    const io = init.io;", "    nb.initOutput(io);"}, null, null);

    idx = 0;
    while (idx <= end) : (idx += 1) {
        if (idx >= cells.len) break;
        const cell = cells[idx];
        if (!std.mem.eql(u8, cell.cell_type, "code")) continue;

        const start1 = try std.fmt.allocPrint(gpa, "    __znb_cell_marker(\"START\", \"{s}\", io);", .{cell.id});
        defer gpa.free(start1);
        const end1 = try std.fmt.allocPrint(gpa, "    __znb_cell_marker(\"END\", \"{s}\", io);", .{cell.id});
        defer gpa.free(end1);
        try W.lines(gpa, &gen, &source_map, &.{start1}, null, null);

        for (statements.items) |stmt| {
            if (stmt.cell_idx != idx) continue;
            var indented: std.ArrayList([]const u8) = .empty;
            defer {
                for (indented.items) |l| gpa.free(l);
                indented.deinit(gpa);
            }
            for (stmt.lines) |line| {
                const ind = try std.fmt.allocPrint(gpa, "    {s}", .{line});
                try indented.append(gpa, ind);
            }
            try W.lines(gpa, &gen, &source_map, indented.items, stmt.cell_idx, stmt.start_line);
        }

        try W.lines(gpa, &gen, &source_map, &.{end1}, null, null);
    }

    try W.lines(gpa, &gen, &source_map, &.{"}"}, null, null);

    var has_tests = false;
    var line_iter = std.mem.splitScalar(u8, gen.items, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "test ") or
            std.mem.startsWith(u8, trimmed, "test{") or
            std.mem.startsWith(u8, trimmed, "test\""))
        {
            has_tests = true;
            break;
        }
    }

    const sanitized = try sanitizeNotebookName(gpa, notebook_name);
    const temp_filename = try std.fmt.allocPrint(gpa, "notebook_{s}.zig", .{sanitized});

    return .{
        .code = try gen.toOwnedSlice(gpa),
        .source_map = try source_map.toOwnedSlice(gpa),
        .temp_filename = temp_filename,
        .has_statements = statements.items.len > 0,
        .has_tests = has_tests,
    };
}

fn sanitizeId(gpa: std.mem.Allocator, id: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (id) |c| try out.append(gpa, if (c == '-') '_' else c);
    return try out.toOwnedSlice(gpa);
}

fn sanitizeNotebookName(gpa: std.mem.Allocator, name: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_')
            try out.append(gpa, c)
        else
            try out.append(gpa, '_');
    }
    if (out.items.len == 0) return try gpa.dupe(u8, "untitled");
    return try out.toOwnedSlice(gpa);
}
