const std = @import("std");
const Io = std.Io;

const assets = @import("../assets.zig");
const config = @import("../config.zig");
const response = @import("../http/response.zig");
const zignb = @import("../format/zignb.zig");
const engine_run = @import("../engine/run.zig");

const notebooks_prefix = "/api/notebook/";

pub fn dispatch(
    stream: Io.net.Stream,
    io: Io,
    gpa: std.mem.Allocator,
    static_assets: *const assets.Bundle,
    method: []const u8,
    path: []const u8,
    body: []const u8,
) !void {
    if (std.mem.eql(u8, method, "GET")) {
        if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
            return response.writeOk(stream, io, "text/html", static_assets.index_html);
        }
        if (std.mem.eql(u8, path, "/style.css")) {
            return response.writeOk(stream, io, "text/css", static_assets.style_css);
        }
        if (std.mem.eql(u8, path, "/app.js")) {
            return response.writeOk(stream, io, "text/javascript", static_assets.app_js);
        }
        if (std.mem.eql(u8, path, "/api/notebooks")) {
            return handleListNotebooks(stream, io, gpa);
        }
        if (std.mem.startsWith(u8, path, notebooks_prefix)) {
            const name = path[notebooks_prefix.len..];
            return handleLoadNotebook(stream, io, gpa, name);
        }
        return response.writeNotFound(stream, io);
    }

    if (std.mem.eql(u8, method, "POST")) {
        if (std.mem.eql(u8, path, "/api/save")) {
            return handleSaveNotebook(stream, io, gpa, body);
        }
        if (std.mem.eql(u8, path, "/api/run")) {
            return handleRun(stream, io, gpa, body);
        }
        return response.writeNotFound(stream, io);
    }

    _ = config;
    return response.writeNotFound(stream, io);
}

fn handleListNotebooks(stream: Io.net.Stream, io: Io, gpa: std.mem.Allocator) !void {
    const notebooks = zignb.listNotebooks(io, gpa) catch {
        return response.writeJson(stream, io, "{\"notebooks\":[]}");
    };
    defer {
        for (notebooks) |n| gpa.free(n);
        gpa.free(notebooks);
    }

    const json = zignb.formatListJson(gpa, notebooks) catch {
        return response.writeJson(stream, io, "{\"notebooks\":[]}");
    };
    defer gpa.free(json);
    try response.writeJson(stream, io, json);
}

fn handleLoadNotebook(stream: Io.net.Stream, io: Io, gpa: std.mem.Allocator, name: []const u8) !void {
    const content = zignb.loadNotebook(io, gpa, name) catch {
        return response.writeNotFound(stream, io);
    };
    defer gpa.free(content);
    try response.writeJson(stream, io, content);
}

const SaveRequest = struct {
    name: []const u8,
};

fn handleSaveNotebook(stream: Io.net.Stream, io: Io, gpa: std.mem.Allocator, body: []const u8) !void {
    const parsed = std.json.parseFromSlice(SaveRequest, gpa, body, .{
        .ignore_unknown_fields = true,
    }) catch {
        return response.writeNotFound(stream, io);
    };
    defer parsed.deinit();

    if (!zignb.sanitizeName(parsed.value.name)) {
        return response.writeNotFound(stream, io);
    }

    zignb.saveNotebook(io, gpa, parsed.value.name, body) catch {
        return response.writePlain(stream, io, "500 Internal Server Error", "Failed to save notebook");
    };

    const json = zignb.formatSaveOkJson(gpa, parsed.value.name) catch {
        return response.writePlain(stream, io, "500 Internal Server Error", "Failed to encode response");
    };
    defer gpa.free(json);
    try response.writeJson(stream, io, json);
}

fn handleRun(stream: Io.net.Stream, io: Io, gpa: std.mem.Allocator, body: []const u8) !void {
    const json = engine_run.runCells(gpa, io, body) catch {
        return response.writeJson(stream, io,
            \\{"success":false,"returncode":-1,"stdout":"","stderr":"Failed to execute notebook cells","errors":[]}
        );
    };
    defer gpa.free(json);
    try response.writeJson(stream, io, json);
}
