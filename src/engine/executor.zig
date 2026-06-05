const std = @import("std");
const Io = std.Io;

const config = @import("../config.zig");
const codegen = @import("codegen.zig");

pub const ErrorDetail = struct {
    gen_line: usize,
    cell_idx: ?usize,
    cell_line: ?usize,
    col: usize,
    message: []const u8,
};

pub const RunResult = struct {
    success: bool,
    returncode: i32,
    stdout: []const u8,
    stderr: []const u8,
    errors: []ErrorDetail,

    pub fn deinit(self: *RunResult, gpa: std.mem.Allocator) void {
        gpa.free(self.stdout);
        gpa.free(self.stderr);
        for (self.errors) |e| gpa.free(e.message);
        gpa.free(self.errors);
    }
};

pub fn extractCellOutput(gpa: std.mem.Allocator, full_output: []const u8, cell_id: []const u8) ![]const u8 {
    const start_marker = try std.fmt.allocPrint(gpa, "[ZNB_CELL_START:{s}]", .{cell_id});
    defer gpa.free(start_marker);
    const end_marker = try std.fmt.allocPrint(gpa, "[ZNB_CELL_END:{s}]", .{cell_id});
    defer gpa.free(end_marker);

    const start_idx = std.mem.indexOf(u8, full_output, start_marker) orelse return try gpa.dupe(u8, "");
    var content_start = start_idx + start_marker.len;
    if (content_start < full_output.len and full_output[content_start] == '\n') content_start += 1;
    if (content_start + 1 < full_output.len and full_output[content_start] == '\r' and full_output[content_start + 1] == '\n')
        content_start += 2;

    const tail = full_output[content_start..];
    const end_rel = std.mem.indexOf(u8, tail, end_marker) orelse return try gpa.dupe(u8, tail);
    var slice = tail[0..end_rel];
    if (slice.len > 0 and slice[slice.len - 1] == '\n') slice = slice[0 .. slice.len - 1];
    if (slice.len > 0 and slice[slice.len - 1] == '\r') slice = slice[0 .. slice.len - 1];
    return try gpa.dupe(u8, slice);
}

fn mapErrors(
    gpa: std.mem.Allocator,
    stderr_str: []const u8,
    temp_filename: []const u8,
    source_map: []const codegen.SourceMapItem,
) ![]ErrorDetail {
    var errors: std.ArrayList(ErrorDetail) = .empty;
    errdefer {
        for (errors.items) |e| gpa.free(e.message);
        errors.deinit(gpa);
    }

    var line_it = std.mem.splitScalar(u8, stderr_str, '\n');
    while (line_it.next()) |line| {
        const fn_idx = std.mem.indexOf(u8, line, temp_filename) orelse continue;
        const after_fn = line[fn_idx + temp_filename.len + 1 ..];
        var parts = std.mem.splitScalar(u8, after_fn, ':');
        const line_str = parts.next() orelse continue;
        const col_str = parts.next() orelse continue;
        const gen_line_num = std.fmt.parseInt(usize, line_str, 10) catch continue;
        const col_num = std.fmt.parseInt(usize, col_str, 10) catch 0;

        const rest = parts.rest();
        var msg = rest;
        if (std.mem.indexOf(u8, rest, "error:")) |err_idx| {
            msg = std.mem.trimStart(u8, rest[err_idx + 6 ..], " ");
        }

        var cell_idx: ?usize = null;
        var cell_line: ?usize = null;
        if (gen_line_num > 0 and gen_line_num <= source_map.len) {
            const item = source_map[gen_line_num - 1];
            cell_idx = item.cell_idx;
            cell_line = item.line_in_cell;
        }

        try errors.append(gpa, .{
            .gen_line = gen_line_num,
            .cell_idx = cell_idx,
            .cell_line = cell_line,
            .col = col_num,
            .message = try gpa.dupe(u8, msg),
        });
    }

    return try errors.toOwnedSlice(gpa);
}

fn runZig(
    gpa: std.mem.Allocator,
    io: Io,
    comptime cmd: []const u8,
    filename: []const u8,
) !struct { stdout: []u8, stderr: []u8, success: bool, code: i32 } {
    const argv = [_][]const u8{ "zig", cmd, "-fno-llvm", "-fno-lld", filename };
    const result = try std.process.run(gpa, io, .{
        .argv = &argv,
        .cwd = .{ .path = config.temp_dir },
        .stdout_limit = .limited(10 * 1024 * 1024),
        .stderr_limit = .limited(10 * 1024 * 1024),
    });

    const code: i32 = switch (result.term) {
        .exited => |c| @intCast(c),
        else => 1,
    };

    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .success = code == 0,
        .code = code,
    };
}

fn copyNotebookLib(io: Io) !void {
    const cwd = Io.Dir.cwd();
    try Io.Dir.copyFile(cwd, "lib/notebook.zig", cwd, "temp/notebook.zig", io, .{
        .make_path = true,
        .replace = true,
    });
}

pub fn execute(
    gpa: std.mem.Allocator,
    io: Io,
    generated: *const codegen.Generated,
    target_cell_id: []const u8,
) !RunResult {
    Io.Dir.cwd().createDirPath(io, config.temp_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };

    const temp_rel = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ config.temp_dir, generated.temp_filename });
    defer gpa.free(temp_rel);

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = temp_rel,
        .data = generated.code,
    });

    copyNotebookLib(io) catch {
        var buf: [512 * 1024]u8 = undefined;
        const lib_data = try Io.Dir.cwd().readFile(io, "lib/notebook.zig", &buf);
        try Io.Dir.cwd().writeFile(io, .{
            .sub_path = "temp/notebook.zig",
            .data = lib_data,
        });
    };

    var success = true;
    var returncode: i32 = 0;
    var stdout_buf: []const u8 = "";
    var stderr_buf: []const u8 = "";
    var stdout_owned: ?[]u8 = null;
    defer if (stdout_owned) |s| gpa.free(s);
    var stderr_owned: ?[]u8 = null;
    defer if (stderr_owned) |s| gpa.free(s);

    if (generated.has_statements) {
        const run_out = try runZig(gpa, io, "run", generated.temp_filename);
        success = run_out.success;
        returncode = run_out.code;
        stdout_owned = run_out.stdout;
        stderr_owned = run_out.stderr;
        stdout_buf = stdout_owned.?;
        stderr_buf = stderr_owned.?;
    }

    var filtered_stdout = try extractCellOutput(gpa, stdout_buf, target_cell_id);
    var filtered_stderr = try extractCellOutput(gpa, stderr_buf, target_cell_id);

    if (!success and filtered_stderr.len == 0) {
        gpa.free(filtered_stderr);
        filtered_stderr = try gpa.dupe(u8, stderr_buf);
    }

    if (generated.has_tests and success) {
        const test_out = try runZig(gpa, io, "test", generated.temp_filename);
        success = success and test_out.success;
        if (!test_out.success and returncode == 0) returncode = 1;

        if (test_out.stdout.len > 0) {
            const merged = try std.fmt.allocPrint(gpa, "{s}\n--- Test stdout ---\n{s}", .{ filtered_stdout, test_out.stdout });
            gpa.free(filtered_stdout);
            filtered_stdout = merged;
        }
        if (test_out.stderr.len > 0) {
            const merged = try std.fmt.allocPrint(gpa, "{s}\n--- Test Results ---\n{s}", .{ filtered_stderr, test_out.stderr });
            gpa.free(filtered_stderr);
            filtered_stderr = merged;
        }
        gpa.free(test_out.stdout);
        gpa.free(test_out.stderr);
    }

    var errors: []ErrorDetail = &.{} ;
    if (!success) {
        errors = try mapErrors(gpa, stderr_buf, generated.temp_filename, generated.source_map);
    }

    return .{
        .success = success,
        .returncode = returncode,
        .stdout = filtered_stdout,
        .stderr = filtered_stderr,
        .errors = errors,
    };
}
