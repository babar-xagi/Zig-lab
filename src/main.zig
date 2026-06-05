const std = @import("std");

const server = @import("http/server.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    try server.serve(io, gpa);
}
