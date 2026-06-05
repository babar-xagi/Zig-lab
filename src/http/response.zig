const std = @import("std");
const Io = std.Io;

pub fn writeOk(stream: Io.net.Stream, io: Io, mime: []const u8, body: []const u8) !void {
    var header_buf: [512]u8 = undefined;
    var stream_writer = Io.net.Stream.writer(stream, io, &header_buf);
    const w = &stream_writer.interface;

    try w.print(
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {}\r\n" ++
            "Cache-Control: no-cache, no-store, must-revalidate\r\n" ++
            "Connection: close\r\n\r\n",
        .{ mime, body.len },
    );
    try w.writeAll(body);
    try w.flush();
}

pub fn writeJson(stream: Io.net.Stream, io: Io, body: []const u8) !void {
    try writeOk(stream, io, "application/json", body);
}

pub fn writeNotFound(stream: Io.net.Stream, io: Io) !void {
    const body = "404 Not Found";
    var header_buf: [256]u8 = undefined;
    var stream_writer = Io.net.Stream.writer(stream, io, &header_buf);
    const w = &stream_writer.interface;

    try w.print(
        "HTTP/1.1 404 Not Found\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Content-Length: {}\r\n" ++
            "Connection: close\r\n\r\n{s}",
        .{ body.len, body },
    );
    try w.flush();
}

pub fn writePlain(stream: Io.net.Stream, io: Io, status: []const u8, body: []const u8) !void {
    var header_buf: [512]u8 = undefined;
    var stream_writer = Io.net.Stream.writer(stream, io, &header_buf);
    const w = &stream_writer.interface;

    try w.print(
        "HTTP/1.1 {s}\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Content-Length: {}\r\n" ++
            "Connection: close\r\n\r\n{s}",
        .{ status, body.len, body },
    );
    try w.flush();
}
