const std = @import("std");
const Io = std.Io;

pub fn write(io: Io, bytes: []const u8) !void {
    try Io.File.stdout().writeStreamingAll(io, bytes);
}

pub fn writeErr(io: Io, bytes: []const u8) !void {
    try Io.File.stderr().writeStreamingAll(io, bytes);
}

pub fn print(gpa: std.mem.Allocator, io: Io, comptime fmt: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(message);
    try write(io, message);
}

pub fn printErr(gpa: std.mem.Allocator, io: Io, comptime fmt: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(message);
    try writeErr(io, message);
}
