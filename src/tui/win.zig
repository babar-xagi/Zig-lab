// Windows console control for the Zig-lab TUI.
// Handles raw mode, terminal size, and ANSI virtual terminal support.

const std = @import("std");

const HANDLE = std.os.windows.HANDLE;
const DWORD = std.os.windows.DWORD;
// On x64 Windows, Win32 APIs use the standard C calling convention.
// We omit callconv() on extern declarations so Zig picks the platform default.
// Use c_int instead of std.os.windows.BOOL so that == 0 comparisons work
// with all Zig versions (BOOL is a wrapped type in Zig 0.16).
const WinBool = c_int;

// Standard handle constants (negative numbers cast to DWORD).
const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));

// Input mode flags.
const ENABLE_PROCESSED_INPUT: DWORD = 0x0001;
const ENABLE_LINE_INPUT: DWORD = 0x0002;
const ENABLE_ECHO_INPUT: DWORD = 0x0004;
const ENABLE_VIRTUAL_TERMINAL_INPUT: DWORD = 0x0200;

// Output mode flags.
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;
const DISABLE_NEWLINE_AUTO_RETURN: DWORD = 0x0008;

const COORD = extern struct { X: i16, Y: i16 };
const SMALL_RECT = extern struct { Left: i16, Top: i16, Right: i16, Bottom: i16 };
const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: u16,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) ?HANDLE;
extern "kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: *DWORD) WinBool;
extern "kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) WinBool;
extern "kernel32" fn GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE, lpInfo: *CONSOLE_SCREEN_BUFFER_INFO) WinBool;
extern "kernel32" fn ReadFile(hFile: HANDLE, lpBuffer: [*]u8, nNumberOfBytesToRead: DWORD, lpNumberOfBytesRead: ?*DWORD, lpOverlapped: ?*anyopaque) WinBool;
extern "kernel32" fn WriteFile(hFile: HANDLE, lpBuffer: [*]const u8, nNumberOfBytesToWrite: DWORD, lpNumberOfBytesWritten: ?*DWORD, lpOverlapped: ?*anyopaque) WinBool;

/// Saved console state that can be restored on exit.
pub const Console = struct {
    in_handle: HANDLE,
    out_handle: HANDLE,
    old_in_mode: DWORD,
    old_out_mode: DWORD,

    /// Obtain handles and save current console modes.
    pub fn init() !Console {
        const in_handle = GetStdHandle(STD_INPUT_HANDLE) orelse return error.NoConsole;
        const out_handle = GetStdHandle(STD_OUTPUT_HANDLE) orelse return error.NoConsole;

        var old_in_mode: DWORD = 0;
        var old_out_mode: DWORD = 0;
        if (GetConsoleMode(in_handle, &old_in_mode) == 0) return error.NoConsole;
        if (GetConsoleMode(out_handle, &old_out_mode) == 0) return error.NoConsole;

        return .{
            .in_handle = in_handle,
            .out_handle = out_handle,
            .old_in_mode = old_in_mode,
            .old_out_mode = old_out_mode,
        };
    }

    /// Switch to raw mode:
    ///   - Input: virtual terminal sequences, no echo, no line buffering.
    ///   - Output: enable ANSI/VT processing.
    pub fn enterRawMode(self: Console) void {
        _ = SetConsoleMode(self.in_handle, ENABLE_VIRTUAL_TERMINAL_INPUT);
        _ = SetConsoleMode(
            self.out_handle,
            self.old_out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN,
        );
    }

    /// Restore the saved console modes.
    pub fn leaveRawMode(self: Console) void {
        _ = SetConsoleMode(self.in_handle, self.old_in_mode);
        _ = SetConsoleMode(self.out_handle, self.old_out_mode);
    }

    /// Read raw bytes from the console input handle (blocking until data arrives).
    pub fn readInput(self: Console, buf: []u8) !usize {
        var count: DWORD = 0;
        if (ReadFile(self.in_handle, buf.ptr, @intCast(buf.len), &count, null) == 0) {
            return error.ReadFailed;
        }
        return @intCast(count);
    }

    /// Write raw bytes directly to the console output handle.
    pub fn writeOutput(self: Console, buf: []const u8) !void {
        var offset: usize = 0;
        while (offset < buf.len) {
            var written: DWORD = 0;
            const chunk: DWORD = @intCast(@min(buf.len - offset, std.math.maxInt(DWORD)));
            if (WriteFile(self.out_handle, buf.ptr + offset, chunk, &written, null) == 0) {
                return error.WriteFailed;
            }
            offset += written;
        }
    }

    /// Return current terminal width and height, falling back to 80×24.
    pub fn getSize(self: Console) struct { cols: u16, rows: u16 } {
        var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (GetConsoleScreenBufferInfo(self.out_handle, &info) == 0) {
            return .{ .cols = 80, .rows = 24 };
        }
        const cols: u16 = @intCast(info.srWindow.Right - info.srWindow.Left + 1);
        const rows: u16 = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
        return .{ .cols = cols, .rows = rows };
    }
};
