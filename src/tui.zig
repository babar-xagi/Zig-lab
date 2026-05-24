// Zig-lab TUI entry point.
// Opens a .ziglab notebook in an interactive terminal UI.

const std = @import("std");
const Io = std.Io;

const notebook = @import("notebook.zig");
const win = @import("tui/win.zig");
const App = @import("tui/app.zig").App;

/// Open `path` in the interactive TUI.  Returns when the user quits.
/// `self_exe` is the path to the zig-lab executable (argv[0]) used for
/// spawning runner subprocesses from within the TUI.
pub fn open(gpa: std.mem.Allocator, io: Io, self_exe: []const u8, path: []const u8) !void {
    const nb = try notebook.load(gpa, io, path);
    // nb is owned by App from here on; App.deinit() will call nb.deinit().

    const console = try win.Console.init();
    console.enterRawMode();
    defer {
        // Restore console state and clear the screen before returning.
        console.leaveRawMode();
        console.writeOutput("\x1b[2J\x1b[H\x1b[?25h") catch {};
    }

    var app = App.init(gpa, io, self_exe, nb, console);
    defer app.deinit();

    try app.run();
}
