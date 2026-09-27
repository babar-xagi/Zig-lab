const std = @import("std");

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

    var counter: i64 = 0;

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
            counter += 1;

            try stdout.print(
                "COUNTER {d}\n",
                .{counter},
            );
        } else if (std.mem.eql(u8, line, "get")) {
            try stdout.print(
                "COUNTER {d}\n",
                .{counter},
            );
        } else if (std.mem.eql(u8, line, "reset")) {
            counter = 0;

            try stdout.writeAll(
                "COUNTER 0\n",
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
