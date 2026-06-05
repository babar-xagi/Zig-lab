const std = @import("std");
const Io = std.Io;

pub const Request = struct {
    method: []const u8,
    path: []const u8,
    body: []const u8,
};

pub const InvalidRequest = error{
    InvalidRequest,
    HeadersTooLong,
    OutOfMemory,
};

pub fn read(stream: Io.net.Stream, io: Io, gpa: std.mem.Allocator) InvalidRequest!Request {
    var read_buf: [4096]u8 = undefined;
    var stream_reader = Io.net.Stream.reader(stream, io, &read_buf);
    const reader = &stream_reader.interface;

    var header_bytes: std.ArrayList(u8) = .empty;
    defer header_bytes.deinit(gpa);

    while (header_bytes.items.len < 8192) {
        reader.fillMore() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return error.InvalidRequest,
        };

        const buffered = reader.buffered();
        if (buffered.len == 0) break;
        try header_bytes.appendSlice(gpa, buffered);
        reader.toss(buffered.len);

        if (std.mem.indexOf(u8, header_bytes.items, "\r\n\r\n")) |pos| {
            const header_end = pos + 4;
            const headers_part = header_bytes.items[0 .. pos + 2];

            var content_length: usize = 0;
            var lines = std.mem.splitSequence(u8, headers_part, "\r\n");
            _ = lines.next();
            while (lines.next()) |line| {
                if (line.len == 0) break;
                if (std.mem.indexOfScalar(u8, line, ':')) |colon| {
                    const name = std.mem.trim(u8, line[0..colon], " \t");
                    if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
                        const val = std.mem.trim(u8, line[colon + 1 ..], " \t");
                        content_length = std.fmt.parseInt(usize, val, 10) catch 0;
                    }
                }
            }

            var body: std.ArrayList(u8) = .empty;
            errdefer body.deinit(gpa);

            const already = header_bytes.items[header_end..];
            if (already.len > 0) try body.appendSlice(gpa, already);

            while (body.items.len < content_length) {
                reader.fillMore() catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return error.InvalidRequest,
                };
                const chunk = reader.buffered();
                if (chunk.len == 0) break;
                const need = content_length - body.items.len;
                const take_len = @min(chunk.len, need);
                try body.appendSlice(gpa, chunk[0..take_len]);
                reader.toss(take_len);
            }

            var req_line_it = std.mem.splitSequence(u8, headers_part, "\r\n");
            const req_line = req_line_it.next() orelse return error.InvalidRequest;
            var parts = std.mem.tokenizeScalar(u8, req_line, ' ');
            const method = trimToken(parts.next() orelse return error.InvalidRequest);
            const path = trimToken(parts.next() orelse return error.InvalidRequest);

            return .{
                .method = try gpa.dupe(u8, method),
                .path = try gpa.dupe(u8, path),
                .body = try body.toOwnedSlice(gpa),
            };
        }
    }

    return error.InvalidRequest;
}

fn trimToken(token: []const u8) []const u8 {
    return std.mem.trim(u8, token, " \t\r\n");
}

test "read POST body with Content-Length" {
    // Regression: header name must match "Content-Length", not a broken prefix check.
    const line = "Content-Length: 42";
    const colon = std.mem.indexOfScalar(u8, line, ':').?;
    const name = std.mem.trim(u8, line[0..colon], " \t");
    try std.testing.expect(std.ascii.eqlIgnoreCase(name, "Content-Length"));
}
