const std = @import("std");
const Io = std.Io;

const cli_io = @import("cli_io.zig");
const notebook = @import("notebook.zig");
const runner_mod = @import("runner.zig");

const usage =
    \\Zig-lab
    \\
    \\Usage:
    \\  zig-lab run <notebook.ziglab> [--cell <cell-id>]
    \\  zig-lab check <notebook.ziglab>
    \\  zig-lab export <notebook.ziglab> [--out <file.zig>]
    \\
    \\Examples:
    \\  zig-lab run examples/hello.ziglab
    \\  zig-lab run examples/hello.ziglab --cell answer
    \\  zig-lab export examples/hello.ziglab --out generated/hello.zig
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2 or isHelp(args[1])) {
        try cli_io.write(io, usage);
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "run")) {
        try cmdRun(gpa, io, args[2..]);
    } else if (std.mem.eql(u8, command, "check")) {
        try cmdCheck(gpa, io, args[2..]);
    } else if (std.mem.eql(u8, command, "export")) {
        try cmdExport(gpa, io, args[2..]);
    } else {
        try cli_io.printErr(gpa, io, "unknown command: {s}\n\n", .{command});
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }
}

fn cmdRun(gpa: std.mem.Allocator, io: Io, args: []const []const u8) !void {
    if (args.len < 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }

    const path = args[0];
    var selected_cell: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cell")) {
            i += 1;
            if (i >= args.len) {
                try cli_io.printErr(gpa, io, "missing value after --cell\n", .{});
                std.process.exit(2);
            }
            selected_cell = args[i];
        } else {
            try cli_io.printErr(gpa, io, "unknown option: {s}\n", .{args[i]});
            std.process.exit(2);
        }
    }

    var nb = try notebook.load(gpa, io, path);
    defer nb.deinit();

    var runner: runner_mod.Runner = .{ .gpa = gpa, .io = io };
    defer runner.deinit();

    try runner.runNotebook(nb, .{ .selected_cell = selected_cell });
}

fn cmdCheck(gpa: std.mem.Allocator, io: Io, args: []const []const u8) !void {
    if (args.len != 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }

    var nb = try notebook.load(gpa, io, args[0]);
    defer nb.deinit();

    var runner: runner_mod.Runner = .{ .gpa = gpa, .io = io };
    defer runner.deinit();

    try runner.checkNotebook(nb);
}

fn cmdExport(gpa: std.mem.Allocator, io: Io, args: []const []const u8) !void {
    if (args.len < 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }

    const path = args[0];
    var out_path: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--out")) {
            i += 1;
            if (i >= args.len) {
                try cli_io.printErr(gpa, io, "missing value after --out\n", .{});
                std.process.exit(2);
            }
            out_path = args[i];
        } else {
            try cli_io.printErr(gpa, io, "unknown option: {s}\n", .{args[i]});
            std.process.exit(2);
        }
    }

    var nb = try notebook.load(gpa, io, path);
    defer nb.deinit();

    var runner: runner_mod.Runner = .{ .gpa = gpa, .io = io };
    defer runner.deinit();

    try runner.exportNotebook(nb, out_path);
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "help");
}
