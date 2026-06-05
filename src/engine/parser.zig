const std = @import("std");

pub const BlockType = enum {
    decl,
    stmt,
};

pub const Block = struct {
    block_type: BlockType,
    name: ?[]const u8,
    lines: []const []const u8,
    start_line: usize,
};

pub fn splitTopLevelBlocks(allocator: std.mem.Allocator, source: []const u8) ![]Block {
    var blocks: std.ArrayList(Block) = .empty;
    errdefer {
        for (blocks.items) |b| freeBlock(allocator, b);
        blocks.deinit(allocator);
    }

    var current_lines: std.ArrayList([]const u8) = .empty;
    defer current_lines.deinit(allocator);

    var brace_depth: usize = 0;
    var in_string = false;
    var in_char = false;
    var in_multiline_comment = false;
    var has_terminator = false;
    var block_start_line: usize = 1;
    var current_line_idx: usize = 0;

    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |line| {
        current_line_idx += 1;
        if (current_lines.items.len == 0) block_start_line = current_line_idx;
        try current_lines.append(allocator, try allocator.dupe(u8, line));

        const chars = line;
        var i: usize = 0;
        while (i < chars.len) {
            const c = chars[i];
            if (in_multiline_comment) {
                if (i + 1 < chars.len and c == '*' and chars[i + 1] == '/') {
                    in_multiline_comment = false;
                    i += 2;
                } else i += 1;
                continue;
            }
            if (in_string) {
                if (c == '\\') i += @min(2, chars.len - i)
                else if (c == '"') {
                    in_string = false;
                    i += 1;
                } else i += 1;
                continue;
            }
            if (in_char) {
                if (c == '\\') i += @min(2, chars.len - i)
                else if (c == '\'') {
                    in_char = false;
                    i += 1;
                } else i += 1;
                continue;
            }

            if (c == '/' and i + 1 < chars.len and chars[i + 1] == '/') break;
            if (c == '/' and i + 1 < chars.len and chars[i + 1] == '*') {
                in_multiline_comment = true;
                i += 2;
            } else if (c == '"') {
                in_string = true;
                i += 1;
            } else if (c == '\'') {
                in_char = true;
                i += 1;
            } else if (c == '{') {
                brace_depth += 1;
                i += 1;
            } else if (c == '}') {
                if (brace_depth > 0) brace_depth -= 1;
                if (brace_depth == 0) has_terminator = true;
                i += 1;
            } else if (brace_depth == 0 and c == ';') {
                has_terminator = true;
                i += 1;
            } else i += 1;
        }

        if (brace_depth == 0 and has_terminator) {
            const lines = try current_lines.toOwnedSlice(allocator);
            const classified = classifyBlock(allocator, lines) catch |err| {
                allocator.free(lines);
                return err;
            };
            try blocks.append(allocator, .{
                .block_type = classified.block_type,
                .name = classified.name,
                .lines = lines,
                .start_line = block_start_line,
            });
            current_lines = .empty;
            has_terminator = false;
        }
    }

    if (current_lines.items.len > 0) {
        var has_content = false;
        for (current_lines.items) |l| {
            if (l.len > 0 and std.mem.trim(u8, l, " \t\r").len > 0) {
                has_content = true;
                break;
            }
        }
        if (has_content) {
            const lines = try current_lines.toOwnedSlice(allocator);
            const classified = classifyBlock(allocator, lines) catch |err| {
                allocator.free(lines);
                return err;
            };
            try blocks.append(allocator, .{
                .block_type = classified.block_type,
                .name = classified.name,
                .lines = lines,
                .start_line = block_start_line,
            });
        }
    }

    return try blocks.toOwnedSlice(allocator);
}

fn freeBlock(allocator: std.mem.Allocator, block: Block) void {
    for (block.lines) |line| allocator.free(line);
    allocator.free(block.lines);
    if (block.name) |n| allocator.free(n);
}

const Classified = struct {
    block_type: BlockType,
    name: ?[]const u8,
};

fn classifyBlock(allocator: std.mem.Allocator, lines: []const []const u8) !Classified {
    var first_line: []const u8 = "";
    for (lines) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) {
            first_line = trimmed;
            break;
        }
    }
    if (first_line.len == 0) return .{ .block_type = .stmt, .name = null };

    if (std.mem.startsWith(u8, first_line, "fn ") or std.mem.startsWith(u8, first_line, "pub fn ")) {
        var rest = first_line;
        if (std.mem.startsWith(u8, rest, "pub ")) rest = rest[4..];
        rest = std.mem.trimStart(u8, rest[3..], " \t");
        const name_len = takeIdentLen(rest);
        if (name_len > 0) {
            return .{
                .block_type = .decl,
                .name = try allocator.dupe(u8, rest[0..name_len]),
            };
        }
    }

    var is_const = false;
    var is_var = false;
    var rest = first_line;
    if (std.mem.startsWith(u8, rest, "pub ")) rest = rest[4..];
    if (std.mem.startsWith(u8, rest, "const ")) {
        is_const = true;
        rest = rest[6..];
    } else if (std.mem.startsWith(u8, rest, "var ")) {
        is_var = true;
        rest = rest[4..];
    }

    if (is_const or is_var) {
        rest = std.mem.trimStart(u8, rest, " \t");
        const name_len = takeIdentLen(rest);
        const name = rest[0..name_len];

        var has_decl_keyword = false;
        for (lines) |l| {
            if (std.mem.indexOf(u8, l, "@import") != null or
                std.mem.indexOf(u8, l, "struct") != null or
                std.mem.indexOf(u8, l, "union") != null or
                std.mem.indexOf(u8, l, "enum") != null)
            {
                has_decl_keyword = true;
                break;
            }
        }

        if (is_const and !has_decl_keyword) {
            if (std.mem.indexOfScalar(u8, first_line, '=')) |eq_idx| {
                const rhs = first_line[eq_idx + 1 ..];
                const rhs_clean = if (std.mem.indexOf(u8, rhs, "//")) |slash| rhs[0..slash] else rhs;
                if (std.mem.indexOfScalar(u8, rhs_clean, '(') == null and name_len > 0) {
                    has_decl_keyword = true;
                }
            }
        }

        if (has_decl_keyword and name_len > 0) {
            return .{
                .block_type = .decl,
                .name = try allocator.dupe(u8, name),
            };
        }
    }

    if (std.mem.startsWith(u8, first_line, "usingnamespace")) {
        return .{ .block_type = .decl, .name = null };
    }
    if (std.mem.startsWith(u8, first_line, "test ") or
        std.mem.startsWith(u8, first_line, "test{") or
        std.mem.startsWith(u8, first_line, "test\""))
    {
        return .{ .block_type = .decl, .name = null };
    }

    return .{ .block_type = .stmt, .name = null };
}

fn takeIdentLen(text: []const u8) usize {
    var n: usize = 0;
    for (text) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_') n += 1 else break;
    }
    return n;
}

pub fn freeBlocks(allocator: std.mem.Allocator, blocks: []Block) void {
    for (blocks) |b| freeBlock(allocator, b);
    allocator.free(blocks);
}

test "split fn decl and stmt" {
    const src =
        \\const std = @import("std");
        \\
        \\std.debug.print("hi\n", .{});
    ;
    const blocks = try splitTopLevelBlocks(std.testing.allocator, src);
    defer freeBlocks(std.testing.allocator, blocks);
    try std.testing.expect(blocks.len >= 2);
    try std.testing.expect(blocks[0].block_type == .decl);
    try std.testing.expect(blocks[1].block_type == .stmt);
}
