const std = @import("std");
const Io = std.Io;

const cli_io = @import("cli_io.zig");
const notebook = @import("notebook.zig");
const runner_mod = @import("runner.zig");
const tui = @import("tui.zig");

const usage =
    \\Zig-lab
    \\
    \\Usage:
    \\  zig-lab tui <notebook.ziglab>
    \\  zig-lab run <notebook.ziglab> [--cell <cell-id>] [--save-outputs]
    \\  zig-lab check <notebook.ziglab>
    \\  zig-lab list <notebook.ziglab>
    \\  zig-lab outputs <notebook.ziglab>
    \\  zig-lab show-output <notebook.ziglab> --cell <cell-id> [--output|--stdout|--stderr|--meta]
    \\  zig-lab export <notebook.ziglab> [--out <file.zig>]
    \\
    \\Examples:
    \\  zig-lab run examples/hello.ziglab
    \\  zig-lab run examples/hello.ziglab --cell answer --save-outputs
    \\  zig-lab list examples/hello.ziglab
    \\  zig-lab outputs examples/hello.ziglab
    \\  zig-lab show-output examples/hello.ziglab --cell answer
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
    if (std.mem.eql(u8, command, "tui")) {
        cmdTui(gpa, io, args[0], args[2..]) catch |err| try handleCommandError(err);
    } else if (std.mem.eql(u8, command, "run")) {
        cmdRun(gpa, io, args[2..]) catch |err| try handleCommandError(err);
    } else if (std.mem.eql(u8, command, "check")) {
        cmdCheck(gpa, io, args[2..]) catch |err| try handleCommandError(err);
    } else if (std.mem.eql(u8, command, "list")) {
        cmdList(gpa, io, args[2..]) catch |err| try handleCommandError(err);
    } else if (std.mem.eql(u8, command, "outputs")) {
        cmdOutputs(gpa, io, args[2..]) catch |err| try handleCommandError(err);
    } else if (std.mem.eql(u8, command, "show-output")) {
        cmdShowOutput(gpa, io, args[2..]) catch |err| try handleCommandError(err);
    } else if (std.mem.eql(u8, command, "export")) {
        cmdExport(gpa, io, args[2..]) catch |err| try handleCommandError(err);
    } else {
        try cli_io.printErr(gpa, io, "unknown command: {s}\n\n", .{command});
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }
}

fn cmdTui(gpa: std.mem.Allocator, io: Io, self_exe: []const u8, args: []const []const u8) !void {
    if (args.len != 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }
    try tui.open(gpa, io, self_exe, args[0]);
}

fn cmdRun(gpa: std.mem.Allocator, io: Io, args: []const []const u8) !void {
    if (args.len < 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }

    const path = args[0];
    var selected_cell: ?[]const u8 = null;
    var save_outputs = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cell")) {
            i += 1;
            if (i >= args.len) {
                try cli_io.printErr(gpa, io, "missing value after --cell\n", .{});
                std.process.exit(2);
            }
            selected_cell = args[i];
        } else if (std.mem.eql(u8, args[i], "--save-outputs")) {
            save_outputs = true;
        } else {
            try cli_io.printErr(gpa, io, "unknown option: {s}\n", .{args[i]});
            std.process.exit(2);
        }
    }

    var nb = try notebook.load(gpa, io, path);
    defer nb.deinit();

    var runner: runner_mod.Runner = .{ .gpa = gpa, .io = io };
    defer runner.deinit();

    try runner.runNotebook(nb, .{ .selected_cell = selected_cell, .save_outputs = save_outputs });
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

fn cmdList(gpa: std.mem.Allocator, io: Io, args: []const []const u8) !void {
    if (args.len != 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }

    var nb = try notebook.load(gpa, io, args[0]);
    defer nb.deinit();

    var runner: runner_mod.Runner = .{ .gpa = gpa, .io = io };
    defer runner.deinit();

    try runner.listNotebook(nb);
}

fn cmdOutputs(gpa: std.mem.Allocator, io: Io, args: []const []const u8) !void {
    if (args.len != 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }

    var nb = try notebook.load(gpa, io, args[0]);
    defer nb.deinit();

    var runner: runner_mod.Runner = .{ .gpa = gpa, .io = io };
    defer runner.deinit();

    try runner.listOutputs(nb);
}

fn cmdShowOutput(gpa: std.mem.Allocator, io: Io, args: []const []const u8) !void {
    if (args.len < 1) {
        try cli_io.writeErr(io, usage);
        std.process.exit(2);
    }

    const path = args[0];
    var selected_cell: ?[]const u8 = null;
    var kind: runner_mod.SavedOutputKind = .output;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cell")) {
            i += 1;
            if (i >= args.len) {
                try cli_io.printErr(gpa, io, "missing value after --cell\n", .{});
                std.process.exit(2);
            }
            selected_cell = args[i];
        } else if (std.mem.eql(u8, args[i], "--output")) {
            kind = .output;
        } else if (std.mem.eql(u8, args[i], "--stdout")) {
            kind = .stdout;
        } else if (std.mem.eql(u8, args[i], "--stderr")) {
            kind = .stderr;
        } else if (std.mem.eql(u8, args[i], "--meta")) {
            kind = .meta;
        } else {
            try cli_io.printErr(gpa, io, "unknown option: {s}\n", .{args[i]});
            std.process.exit(2);
        }
    }

    const cell_id = selected_cell orelse {
        try cli_io.printErr(gpa, io, "missing required --cell <cell-id>\n", .{});
        std.process.exit(2);
    };

    var nb = try notebook.load(gpa, io, path);
    defer nb.deinit();

    var runner: runner_mod.Runner = .{ .gpa = gpa, .io = io };
    defer runner.deinit();

    try runner.showOutput(nb, cell_id, kind);
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

fn handleCommandError(err: anyerror) anyerror!void {
    switch (err) {
        error.CellFailed,
        error.CellNotFound,
        error.CellNotExecutable,
        error.DependencyNotFound,
        error.DependencyNotDeclaration,
        error.DependencyCycle,
        error.InvalidNotebook,
        error.OutputNotFound,
        => std.process.exit(1),
        else => return err,
    }
}
