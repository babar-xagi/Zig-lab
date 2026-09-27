const std = @import("std");

const State = extern struct {
    counter: i64,
};

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

    var state = State{
        .counter = 0,
    };

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
            state.counter += 1;

            try stdout.print(
                "COUNTER {d}\n",
                .{state.counter},
            );

        } else if (std.mem.eql(u8, line, "get")) {
            try stdout.print(
                "COUNTER {d}\n",
                .{state.counter},
            );

        } else if (std.mem.eql(u8, line, "reset")) {
            state.counter = 0;

            try stdout.writeAll("COUNTER 0\n");

        } else if (std.mem.startsWith(u8, line, "load ")) {
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

            var lib = std.DynLib.open(path) catch |err| {
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

            try stdout.print(
                "CELL OK COUNTER {d}\n",
                .{state.counter},
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
