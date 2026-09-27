const std = @import("std");
const abi = @import("abi.zig");

const State = abi.State;

const CellFn = *const fn (*State) callconv(.c) void;

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdout_buffer: [4096]u8 = undefined;

    var stdin_file = std.Io.File.stdin().readerStreaming(
        init.io,
        &stdin_buffer,
    );

    var stdout_file = std.Io.File.stdout().writerStreaming(
        init.io,
        &stdout_buffer,
    );

    const stdin = &stdin_file.interface;
    const stdout = &stdout_file.interface;

    var state = std.mem.zeroes(State);

    try stdout.writeAll("READY\n");
    try stdout.flush();

    while (try stdin.takeDelimiter('\n')) |raw_line| {
        const line = std.mem.trim(
            u8,
            raw_line,
            " \t\r\n",
        );

        if (std.mem.eql(u8, line, "ping")) {
            try stdout.writeAll("PONG\n");

        } else if (std.mem.eql(u8, line, "inc")) {
            const old = abi.getI64(
                &state,
                "counter",
            ) orelse 0;

            _ = abi.setI64(
                &state,
                "counter",
                old + 1,
            );

            try stdout.print(
                "COUNTER {d}\n",
                .{old + 1},
            );

        } else if (std.mem.eql(u8, line, "get")) {
            const value = abi.getI64(
                &state,
                "counter",
            ) orelse 0;

            try stdout.print(
                "COUNTER {d}\n",
                .{value},
            );

        } else if (std.mem.eql(u8, line, "reset")) {
            abi.clear(&state);

            try stdout.writeAll(
                "COUNTER 0\n",
            );

        } else if (std.mem.eql(u8, line, "vars")) {
            try stdout.writeAll("VARS");

            for (state.slots[0..]) |*slot| {
                if (slot.tag == abi.tag_empty) {
                    continue;
                }

                const name_len: usize = @intCast(
                    slot.name_len
                );

                try stdout.print(
                    " {s}:{s}",
                    .{
                        slot.name[0..name_len],
                        abi.tagName(slot.tag),
                    },
                );
            }

            try stdout.writeAll("\n");

        } else if (
            std.mem.startsWith(
                u8,
                line,
                "var-get ",
            )
        ) {
            const name = std.mem.trim(
                u8,
                line["var-get ".len..],
                " \t\r\n",
            );

            const slot = abi.find(
                &state,
                name,
            ) orelse {
                try stdout.print(
                    "VAR {s} MISSING\n",
                    .{name},
                );

                try stdout.flush();
                continue;
            };

            if (slot.tag == abi.tag_i64) {
                const value: i64 = @bitCast(
                    slot.bits
                );

                try stdout.print(
                    "VAR {s} I64 {d}\n",
                    .{ name, value },
                );

            } else if (slot.tag == abi.tag_f64) {
                const value: f64 = @bitCast(
                    slot.bits
                );

                try stdout.print(
                    "VAR {s} F64 {d}\n",
                    .{ name, value },
                );

            } else if (slot.tag == abi.tag_bool) {
                const value = slot.bits != 0;

                try stdout.print(
                    "VAR {s} BOOL {s}\n",
                    .{
                        name,
                        if (value) "true" else "false",
                    },
                );

            } else {
                try stdout.print(
                    "VAR {s} UNKNOWN\n",
                    .{name},
                );
            }

        } else if (
            std.mem.startsWith(
                u8,
                line,
                "load ",
            )
        ) {
            const path = std.mem.trim(
                u8,
                line["load ".len..],
                " \t\r\n",
            );

            if (path.len == 0) {
                try stdout.writeAll(
                    "ERROR missing library path\n",
                );

                try stdout.flush();
                continue;
            }

            var lib = std.DynLib.open(
                path
            ) catch |err| {
                try stdout.print(
                    "ERROR load {s}\n",
                    .{@errorName(err)},
                );

                try stdout.flush();
                continue;
            };

            defer lib.close();

            const run_cell = lib.lookup(
                CellFn,
                "ziglab_cell",
            ) orelse {
                try stdout.writeAll(
                    "ERROR symbol ziglab_cell not found\n",
                );

                try stdout.flush();
                continue;
            };

            run_cell(&state);

            const counter = abi.getI64(
                &state,
                "counter",
            ) orelse 0;

            try stdout.print(
                "CELL OK COUNTER {d}\n",
                .{counter},
            );

        } else if (std.mem.eql(u8, line, "quit")) {
            try stdout.writeAll("BYE\n");
            try stdout.flush();

            break;

        } else if (line.len == 0) {
            try stdout.writeAll("EMPTY\n");

        } else {
            try stdout.print(
                "ERROR unknown command: {s}\n",
                .{line},
            );
        }

        try stdout.flush();
    }
}
