const std = @import("std");

const State = extern struct {
    counter: i64,
};

const CellFn = *const fn (*State) callconv(.c) void;

pub fn main() !void {
    var state = State{
        .counter = 3,
    };

    std.debug.print(
        "before = {d}\n",
        .{state.counter},
    );

    var lib = try std.DynLib.open(
        "experiments/dynload/libcell.so",
    );
    defer lib.close();

    const run_cell = lib.lookup(
        CellFn,
        "ziglab_cell",
    ) orelse return error.SymbolNotFound;

    run_cell(&state);

    std.debug.print(
        "after = {d}\n",
        .{state.counter},
    );
}
