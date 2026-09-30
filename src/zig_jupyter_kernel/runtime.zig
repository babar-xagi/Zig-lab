const std = @import("std");
const abi = @import("abi.zig");
const dynlib = @import("dynlib.zig");

const max_vars: usize = 64;
const max_name_len: usize = 48;

const tag_empty: u8 = 0;
const tag_i64: u8 = 1;
const tag_f64: u8 = 2;
const tag_bool: u8 = 3;

const Slot = struct {
    name: [max_name_len]u8,
    name_len: usize,
    tag: u8,
    bits: u64,
};

const Store = struct {
    slots: [max_vars]Slot,
};

const CellFn = *const fn (
    *abi.State,
) callconv(.c) void;

// ---------------------------------------------------------
// Internal store helpers
//
// Only runtime.zig knows how Store and Slot are laid out.
// Dynamic notebook libraries never access them directly.
// ---------------------------------------------------------

fn slotName(
    slot: *const Slot,
) []const u8 {
    return slot.name[0..slot.name_len];
}


fn findSlot(
    store: *Store,
    name: []const u8,
) ?*Slot {
    for (store.slots[0..]) |*slot| {
        if (slot.tag == tag_empty) {
            continue;
        }

        if (std.mem.eql(
            u8,
            slotName(slot),
            name,
        )) {
            return slot;
        }
    }

    return null;
}


fn findOrCreateSlot(
    store: *Store,
    name: []const u8,
) ?*Slot {
    if (findSlot(store, name)) |slot| {
        return slot;
    }

    if (
        name.len == 0 or
        name.len > max_name_len
    ) {
        return null;
    }

    for (store.slots[0..]) |*slot| {
        if (slot.tag != tag_empty) {
            continue;
        }

        @memset(slot.name[0..], 0);

        @memcpy(
            slot.name[0..name.len],
            name,
        );

        slot.name_len = name.len;
        slot.bits = 0;

        return slot;
    }

    return null;
}


fn storeSetI64(
    store: *Store,
    name: []const u8,
    value: i64,
) bool {
    const slot = findOrCreateSlot(
        store,
        name,
    ) orelse return false;

    slot.tag = tag_i64;
    slot.bits = @bitCast(value);

    return true;
}


fn storeGetI64(
    store: *Store,
    name: []const u8,
) ?i64 {
    const slot = findSlot(
        store,
        name,
    ) orelse return null;

    if (slot.tag != tag_i64) {
        return null;
    }

    const value: i64 = @bitCast(slot.bits);

    return value;
}


fn storeSetF64(
    store: *Store,
    name: []const u8,
    value: f64,
) bool {
    const slot = findOrCreateSlot(
        store,
        name,
    ) orelse return false;

    slot.tag = tag_f64;
    slot.bits = @bitCast(value);

    return true;
}


fn storeGetF64(
    store: *Store,
    name: []const u8,
) ?f64 {
    const slot = findSlot(
        store,
        name,
    ) orelse return null;

    if (slot.tag != tag_f64) {
        return null;
    }

    const value: f64 = @bitCast(slot.bits);

    return value;
}


fn storeSetBool(
    store: *Store,
    name: []const u8,
    value: bool,
) bool {
    const slot = findOrCreateSlot(
        store,
        name,
    ) orelse return false;

    slot.tag = tag_bool;
    slot.bits = if (value) 1 else 0;

    return true;
}


fn storeGetBool(
    store: *Store,
    name: []const u8,
) ?bool {
    const slot = findSlot(
        store,
        name,
    ) orelse return null;

    if (slot.tag != tag_bool) {
        return null;
    }

    return slot.bits != 0;
}


fn tagName(tag: u8) []const u8 {
    return switch (tag) {
        tag_i64 => "i64",
        tag_f64 => "f64",
        tag_bool => "bool",
        else => "unknown",
    };
}


// ---------------------------------------------------------
// ABI callbacks
//
// These functions are what dynamically compiled notebook
// libraries call.
//
// The .so sees only:
//     userdata + function pointers
//
// It does NOT know Store's memory layout.
// ---------------------------------------------------------

fn apiSetI64(
    userdata: *anyopaque,
    name_ptr: [*:0]const u8,
    value: i64,
) callconv(.c) u8 {
    const store: *Store = @ptrCast(
        @alignCast(userdata)
    );

    const name = std.mem.span(name_ptr);

    return if (
        storeSetI64(
            store,
            name,
            value,
        )
    ) 1 else 0;
}


fn apiGetI64(
    userdata: *anyopaque,
    name_ptr: [*:0]const u8,
    output: *i64,
) callconv(.c) u8 {
    const store: *Store = @ptrCast(
        @alignCast(userdata)
    );

    const name = std.mem.span(name_ptr);

    const value = storeGetI64(
        store,
        name,
    ) orelse return 0;

    output.* = value;

    return 1;
}


fn apiSetF64(
    userdata: *anyopaque,
    name_ptr: [*:0]const u8,
    value: f64,
) callconv(.c) u8 {
    const store: *Store = @ptrCast(
        @alignCast(userdata)
    );

    const name = std.mem.span(name_ptr);

    return if (
        storeSetF64(
            store,
            name,
            value,
        )
    ) 1 else 0;
}


fn apiGetF64(
    userdata: *anyopaque,
    name_ptr: [*:0]const u8,
    output: *f64,
) callconv(.c) u8 {
    const store: *Store = @ptrCast(
        @alignCast(userdata)
    );

    const name = std.mem.span(name_ptr);

    const value = storeGetF64(
        store,
        name,
    ) orelse return 0;

    output.* = value;

    return 1;
}


fn apiSetBool(
    userdata: *anyopaque,
    name_ptr: [*:0]const u8,
    value: u8,
) callconv(.c) u8 {
    const store: *Store = @ptrCast(
        @alignCast(userdata)
    );

    const name = std.mem.span(name_ptr);

    return if (
        storeSetBool(
            store,
            name,
            value != 0,
        )
    ) 1 else 0;
}


fn apiGetBool(
    userdata: *anyopaque,
    name_ptr: [*:0]const u8,
    output: *u8,
) callconv(.c) u8 {
    const store: *Store = @ptrCast(
        @alignCast(userdata)
    );

    const name = std.mem.span(name_ptr);

    const value = storeGetBool(
        store,
        name,
    ) orelse return 0;

    output.* = if (value) 1 else 0;

    return 1;
}


// ---------------------------------------------------------
// Runtime
// ---------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdout_buffer: [4096]u8 = undefined;

    var stdin_file = std.Io.File.stdin().readerStreaming(
        init.io,
        &stdin_buffer,
    );

    var stdout_file = std.Io.File.stdout().writerStreaming(
        init.io,
        &stdout_buffer,
    );

    const stdin = &stdin_file.interface;
    const stdout = &stdout_file.interface;

    // Real persistent notebook state.
    //
    // Dynamic libraries never see Store directly.
    var store = std.mem.zeroes(Store);

    // Small stable interface passed across the dynamic-library boundary.
    var context = abi.Context{
        .userdata = @ptrCast(&store),

        .set_i64_fn = apiSetI64,
        .get_i64_fn = apiGetI64,

        .set_f64_fn = apiSetF64,
        .get_f64_fn = apiGetF64,

        .set_bool_fn = apiSetBool,
        .get_bool_fn = apiGetBool,
    };

    try stdout.writeAll("READY\n");
    try stdout.flush();

    while (try stdin.takeDelimiter('\n')) |raw_line| {
        const line = std.mem.trim(
            u8,
            raw_line,
            " \t\r\n",
        );

        if (std.mem.eql(
            u8,
            line,
            "ping",
        )) {
            try stdout.writeAll(
                "PONG\n",
            );

        } else if (std.mem.eql(
            u8,
            line,
            "inc",
        )) {
            const old = storeGetI64(
                &store,
                "counter",
            ) orelse 0;

            _ = storeSetI64(
                &store,
                "counter",
                old + 1,
            );

            try stdout.print(
                "COUNTER {d}\n",
                .{old + 1},
            );

        } else if (std.mem.eql(
            u8,
            line,
            "get",
        )) {
            const value = storeGetI64(
                &store,
                "counter",
            ) orelse 0;

            try stdout.print(
                "COUNTER {d}\n",
                .{value},
            );

        } else if (std.mem.eql(
            u8,
            line,
            "reset",
        )) {
            store = std.mem.zeroes(Store);

            try stdout.writeAll(
                "COUNTER 0\n",
            );

        } else if (std.mem.eql(
            u8,
            line,
            "vars",
        )) {
            try stdout.writeAll("VARS");

            for (store.slots[0..]) |*slot| {
                if (slot.tag == tag_empty) {
                    continue;
                }

                try stdout.print(
                    " {s}:{s}",
                    .{
                        slotName(slot),
                        tagName(slot.tag),
                    },
                );
            }

            try stdout.writeAll("\n");

        } else if (std.mem.startsWith(
            u8,
            line,
            "var-get ",
        )) {
            const name = std.mem.trim(
                u8,
                line["var-get ".len..],
                " \t\r\n",
            );

            const slot = findSlot(
                &store,
                name,
            ) orelse {
                try stdout.print(
                    "VAR {s} MISSING\n",
                    .{name},
                );

                try stdout.flush();
                continue;
            };

            if (slot.tag == tag_i64) {
                const value: i64 = @bitCast(
                    slot.bits
                );

                try stdout.print(
                    "VAR {s} I64 {d}\n",
                    .{ name, value },
                );

            } else if (slot.tag == tag_f64) {
                const value: f64 = @bitCast(
                    slot.bits
                );

                try stdout.print(
                    "VAR {s} F64 {d}\n",
                    .{ name, value },
                );

            } else if (slot.tag == tag_bool) {
                try stdout.print(
                    "VAR {s} BOOL {s}\n",
                    .{
                        name,
                        if (slot.bits != 0)
                            "true"
                        else
                            "false",
                    },
                );

            } else {
                try stdout.print(
                    "VAR {s} UNKNOWN\n",
                    .{name},
                );
            }

        } else if (std.mem.startsWith(
            u8,
            line,
            "load ",
        )) {
            const path = std.mem.trim(
                u8,
                line["load ".len..],
                " \t\r\n",
            );

            if (path.len == 0) {
                try stdout.writeAll(
                    "ERROR missing library path\n",
                );

                try stdout.flush();
                continue;
            }

            var lib = dynlib.DynamicLibrary.open(
                init.arena.allocator(),
                path,
            ) catch |err| {
                try stdout.print(
                    "ERROR load {s}\n",
                    .{@errorName(err)},
                );

                try stdout.flush();
                continue;
            };

            defer lib.close();

            const run_cell = lib.lookup(
                CellFn,
                "ziglab_cell",
            ) orelse {
                try stdout.writeAll(
                    "ERROR symbol ziglab_cell not found\n",
                );

                try stdout.flush();
                continue;
            };

            // This is the critical new architecture:
            //
            // old:
            //     run_cell(&store)
            //
            // new:
            //     run_cell(&context)
            //
            run_cell(&context);

            const counter = storeGetI64(
                &store,
                "counter",
            ) orelse 0;

            try stdout.print(
                "CELL OK COUNTER {d}\n",
                .{counter},
            );

        } else if (std.mem.eql(
            u8,
            line,
            "quit",
        )) {
            try stdout.writeAll(
                "BYE\n",
            );

            try stdout.flush();
            break;

        } else if (line.len == 0) {
            try stdout.writeAll(
                "EMPTY\n",
            );

        } else {
            try stdout.print(
                "ERROR unknown command: {s}\n",
                .{line},
            );
        }

        try stdout.flush();
    }
}
