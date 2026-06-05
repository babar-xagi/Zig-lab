//! `.zignb` notebook file helpers.

const std = @import("std");
const Io = std.Io;
const config = @import("../config.zig");

pub fn sanitizeName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

pub fn ensureNotebookDir(io: Io) !void {
    Io.Dir.cwd().createDirPath(io, config.notebooks_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
}

pub fn listNotebooks(io: Io, gpa: std.mem.Allocator) ![]const []const u8 {
    try ensureNotebookDir(io);

    var dir = try Io.Dir.cwd().openDir(io, config.notebooks_dir, .{ .iterate = true });
    defer dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const ext = std.fs.path.extension(entry.name);
        if (!std.mem.eql(u8, ext, config.ext) and !std.mem.eql(u8, ext, config.legacy_ext)) continue;
        const stem = std.fs.path.stem(entry.name);
        try names.append(gpa, try gpa.dupe(u8, stem));
    }

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    return try names.toOwnedSlice(gpa);
}

pub fn loadNotebook(io: Io, gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    if (!sanitizeName(name)) return error.InvalidName;

    var buf: [1024 * 1024]u8 = undefined;

    const zignb_rel = try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ config.notebooks_dir, name, config.ext });
    defer gpa.free(zignb_rel);

    if (Io.Dir.cwd().readFile(io, zignb_rel, &buf)) |content| {
        return try gpa.dupe(u8, content);
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    const legacy_rel = try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ config.notebooks_dir, name, config.legacy_ext });
    defer gpa.free(legacy_rel);

    const content = try Io.Dir.cwd().readFile(io, legacy_rel, &buf);
    return try gpa.dupe(u8, content);
}

pub fn saveNotebook(io: Io, gpa: std.mem.Allocator, name: []const u8, body: []const u8) !void {
    if (!sanitizeName(name)) return error.InvalidName;
    try ensureNotebookDir(io);

    const rel_path = try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ config.notebooks_dir, name, config.ext });
    defer gpa.free(rel_path);

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = rel_path,
        .data = body,
    });
}

pub const InvalidName = error{InvalidName};

pub fn formatListJson(gpa: std.mem.Allocator, notebooks: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    try out.appendSlice(gpa, "{\"notebooks\":[");
    for (notebooks, 0..) |name, i| {
        if (i > 0) try out.append(gpa, ',');
        try appendJsonString(gpa, &out, name);
    }
    try out.appendSlice(gpa, "]}");
    return try out.toOwnedSlice(gpa);
}

fn appendJsonString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    try out.append(gpa, '"');
    for (text) |c| {
        switch (c) {
            '"', '\\' => {
                try out.append(gpa, '\\');
                try out.append(gpa, c);
            },
            else => try out.append(gpa, c),
        }
    }
    try out.append(gpa, '"');
}

pub fn formatSaveOkJson(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"success\":true,\"name\":\"{s}\",\"format\":\"{s}\",\"format_version\":{d}}}", .{
        name, config.format_name, config.format_version,
    });
}

test "sanitize notebook names" {
    try std.testing.expect(sanitizeName("hello"));
    try std.testing.expect(sanitizeName("hello_world-1"));
    try std.testing.expect(!sanitizeName("../escape"));
    try std.testing.expect(!sanitizeName(""));
}
