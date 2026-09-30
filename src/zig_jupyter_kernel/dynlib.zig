const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const HMODULE = *anyopaque;
const FARPROC = *anyopaque;

extern "kernel32" fn LoadLibraryExW(
    lpLibFileName: [*:0]const u16,
    hFile: ?*anyopaque,
    dwFlags: u32,
) callconv(.winapi) ?HMODULE;

extern "kernel32" fn GetProcAddress(
    hModule: HMODULE,
    lpProcName: [*:0]const u8,
) callconv(.winapi) ?FARPROC;

extern "kernel32" fn FreeLibrary(
    hLibModule: HMODULE,
) callconv(.winapi) i32;


const WindowsLibrary = struct {
    handle: HMODULE,

    fn open(
        allocator: Allocator,
        path: []const u8,
    ) !WindowsLibrary {
        const wide_path = try (
            std.unicode.utf8ToUtf16LeAllocZ(
                allocator,
                path,
            )
        );

        defer allocator.free(
            wide_path
        );

        const handle = LoadLibraryExW(
            wide_path.ptr,
            null,
            0,
        ) orelse {
            return error.LibraryOpenFailed;
        };

        return .{
            .handle = handle,
        };
    }

    fn close(
        self: *WindowsLibrary,
    ) void {
        _ = FreeLibrary(
            self.handle
        );
    }

    fn lookup(
        self: *WindowsLibrary,
        comptime T: type,
        name: [:0]const u8,
    ) ?T {
        const address = GetProcAddress(
            self.handle,
            name.ptr,
        ) orelse return null;

        return @ptrCast(
            @alignCast(address)
        );
    }
};


const UnixLibrary = struct {
    inner: std.DynLib,

    fn open(
        allocator: Allocator,
        path: []const u8,
    ) !UnixLibrary {
        _ = allocator;

        return .{
            .inner = try std.DynLib.open(
                path
            ),
        };
    }

    fn close(
        self: *UnixLibrary,
    ) void {
        self.inner.close();
    }

    fn lookup(
        self: *UnixLibrary,
        comptime T: type,
        name: [:0]const u8,
    ) ?T {
        return self.inner.lookup(
            T,
            name,
        );
    }
};


const Implementation = if (
    builtin.os.tag == .windows
)
    WindowsLibrary
else
    UnixLibrary;


pub const DynamicLibrary = struct {
    implementation: Implementation,

    pub fn open(
        allocator: Allocator,
        path: []const u8,
    ) !DynamicLibrary {
        return .{
            .implementation = try (
                Implementation.open(
                    allocator,
                    path,
                )
            ),
        };
    }

    pub fn close(
        self: *DynamicLibrary,
    ) void {
        self.implementation.close();
    }

    pub fn lookup(
        self: *DynamicLibrary,
        comptime T: type,
        name: [:0]const u8,
    ) ?T {
        return self.implementation.lookup(
            T,
            name,
        );
    }
};
