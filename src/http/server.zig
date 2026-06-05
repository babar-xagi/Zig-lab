const std = @import("std");
const Io = std.Io;
const net = Io.net;

const assets = @import("../assets.zig");
const config = @import("../config.zig");
const request = @import("request.zig");
const router = @import("../api/router.zig");

pub fn serve(io: Io, gpa: std.mem.Allocator) !void {
    try ensureWorkspace(io);

    var static_assets = try assets.Bundle.load(io, gpa);
    defer static_assets.deinit(gpa);

    const listen_literal = try std.fmt.allocPrint(gpa, "{s}:{d}", .{ config.host, config.port });
    defer gpa.free(listen_literal);

    const address = try net.IpAddress.parseLiteral(listen_literal);

    var server = try net.IpAddress.listen(&address, io, .{
        .reuse_address = true,
    });
    defer server.deinit(io);

    std.debug.print("==================================================\n", .{});
    std.debug.print("   ZNotebook Server (Zig) http://{s}:{d}\n", .{ config.host, config.port });
    std.debug.print("   Notebook files: *{s}\n", .{config.ext});
    std.debug.print("==================================================\n", .{});

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.debug.print("accept error: {}\n", .{err});
            continue;
        };

        handleConnection(stream, io, gpa, &static_assets) catch |err| {
            std.debug.print("connection error: {}\n", .{err});
        };
        stream.close(io);
    }
}

fn ensureWorkspace(io: Io) !void {
    Io.Dir.cwd().createDirPath(io, config.notebooks_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
    Io.Dir.cwd().createDirPath(io, config.temp_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
}

fn handleConnection(stream: net.Stream, io: Io, gpa: std.mem.Allocator, static_assets: *const assets.Bundle) !void {
    const req = request.read(stream, io, gpa) catch {
        return router.dispatch(stream, io, gpa, static_assets, "GET", "/", "");
    };
    defer gpa.free(req.body);
    defer gpa.free(req.path);
    defer gpa.free(req.method);

    try router.dispatch(stream, io, gpa, static_assets, req.method, req.path, req.body);
}

test "server config" {
    const config_mod = @import("../config.zig");
    try std.testing.expectEqual(@as(u16, 8000), config_mod.port);
    try std.testing.expectEqualStrings(".zignb", config_mod.ext);
}
