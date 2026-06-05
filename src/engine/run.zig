const std = @import("std");
const Io = std.Io;

const codegen = @import("codegen.zig");
const executor = @import("executor.zig");

const CellJson = struct {
    id: []const u8,
    @"type": []const u8,
    source: []const u8,
};

const RunRequestJson = struct {
    cells: []const CellJson,
    target_index: usize,
    notebook_name: []const u8,
};

const ErrorJson = struct {
    gen_line: usize,
    cell_idx: ?usize,
    cell_line: ?usize,
    col: usize,
    message: []const u8,
};

const RunResponseJson = struct {
    success: bool,
    returncode: i32,
    stdout: []const u8,
    stderr: []const u8,
    errors: []const ErrorJson,
};

pub fn runCells(gpa: std.mem.Allocator, io: Io, body: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(RunRequestJson, gpa, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    if (parsed.value.cells.len == 0) {
        return try encodeResponse(gpa, .{
            .success = false,
            .returncode = 1,
            .stdout = "",
            .stderr = "No cells in request",
            .errors = &.{},
        });
    }

    const target_idx = parsed.value.target_index;
    if (target_idx >= parsed.value.cells.len) {
        return try encodeResponse(gpa, .{
            .success = false,
            .returncode = 1,
            .stdout = "",
            .stderr = "target_index out of range",
            .errors = &.{},
        });
    }

    var inputs: std.ArrayList(codegen.CellInput) = .empty;
    defer inputs.deinit(gpa);
    for (parsed.value.cells) |c| {
        try inputs.append(gpa, .{
            .id = c.id,
            .cell_type = c.type,
            .source = c.source,
        });
    }

    var generated = try codegen.generate(
        gpa,
        inputs.items,
        target_idx,
        parsed.value.notebook_name,
    );
    defer generated.deinit(gpa);

    const target_id = parsed.value.cells[target_idx].id;
    var result = try executor.execute(gpa, io, &generated, target_id);
    defer result.deinit(gpa);

    var err_json: std.ArrayList(ErrorJson) = .empty;
    defer err_json.deinit(gpa);
    for (result.errors) |e| {
        try err_json.append(gpa, .{
            .gen_line = e.gen_line,
            .cell_idx = e.cell_idx,
            .cell_line = e.cell_line,
            .col = e.col,
            .message = e.message,
        });
    }

    return try encodeResponse(gpa, .{
        .success = result.success,
        .returncode = result.returncode,
        .stdout = result.stdout,
        .stderr = result.stderr,
        .errors = err_json.items,
    });
}

fn encodeResponse(gpa: std.mem.Allocator, resp: RunResponseJson) ![]u8 {
    return try std.json.Stringify.valueAlloc(gpa, resp, .{});
}

test "runCells simple print" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const body =
        \\{"cells":[{"id":"cell-1","type":"code","source":"const std = @import(\"std\");\nstd.debug.print(\"Hello\\n\", .{});"}],"target_index":0,"notebook_name":"test"}
    ;
    const json = runCells(gpa, io, body) catch |err| {
        std.debug.print("runCells error: {}\n", .{err});
        return err;
    };
    defer gpa.free(json);
    std.debug.print("run result: {s}\n", .{json});
    try std.testing.expect(std.mem.indexOf(u8, json, "\"success\":true") != null);
}
