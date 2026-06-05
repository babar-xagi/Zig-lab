//! Static frontend assets loaded from disk at startup.

const std = @import("std");
const Io = std.Io;

pub const Bundle = struct {
    index_html: []const u8,
    style_css: []const u8,
    app_js: []const u8,

    pub fn load(io: Io, gpa: std.mem.Allocator) !Bundle {
        return .{
            .index_html = try readAsset(io, gpa, "frontend/index.html"),
            .style_css = try readAsset(io, gpa, "frontend/style.css"),
            .app_js = try readAsset(io, gpa, "frontend/app.js"),
        };
    }

    pub fn deinit(self: *Bundle, gpa: std.mem.Allocator) void {
        gpa.free(self.index_html);
        gpa.free(self.style_css);
        gpa.free(self.app_js);
        self.* = undefined;
    }
};

fn readAsset(io: Io, gpa: std.mem.Allocator, path: []const u8) ![]const u8 {
    var buffer: [1024 * 1024]u8 = undefined;
    const data = try Io.Dir.cwd().readFile(io, path, &buffer);
    return try gpa.dupe(u8, data);
}
