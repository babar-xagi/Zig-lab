const std = @import("std");

pub const max_vars: usize = 64;
pub const max_name_len: usize = 48;

pub const tag_empty: u8 = 0;
pub const tag_i64: u8 = 1;
pub const tag_f64: u8 = 2;
pub const tag_bool: u8 = 3;

pub const Slot = extern struct {
    name: [max_name_len]u8,
    name_len: u8,
    tag: u8,
    _padding: [6]u8,
    bits: u64,
};

pub const State = extern struct {
    slots: [max_vars]Slot,
};

pub fn clear(state: *State) void {
    state.* = std.mem.zeroes(State);
}

fn slotName(slot: *const Slot) []const u8 {
    const len: usize = @intCast(slot.name_len);
    return slot.name[0..len];
}

pub fn find(
    state: *State,
    name: []const u8,
) ?*Slot {
    for (state.slots[0..]) |*slot| {
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

fn findOrCreate(
    state: *State,
    name: []const u8,
) ?*Slot {
    if (find(state, name)) |slot| {
        return slot;
    }

    if (
        name.len == 0 or
        name.len > max_name_len
    ) {
        return null;
    }

    for (state.slots[0..]) |*slot| {
        if (slot.tag != tag_empty) {
            continue;
        }

        @memset(slot.name[0..], 0);

        @memcpy(
            slot.name[0..name.len],
            name,
        );

        slot.name_len = @intCast(name.len);
        slot.bits = 0;

        return slot;
    }

    return null;
}

pub fn setI64(
    state: *State,
    name: []const u8,
    value: i64,
) bool {
    const slot = findOrCreate(
        state,
        name,
    ) orelse return false;

    slot.tag = tag_i64;
    slot.bits = @bitCast(value);

    return true;
}

pub fn getI64(
    state: *State,
    name: []const u8,
) ?i64 {
    const slot = find(
        state,
        name,
    ) orelse return null;

    if (slot.tag != tag_i64) {
        return null;
    }

    const value: i64 = @bitCast(slot.bits);

    return value;
}

pub fn setF64(
    state: *State,
    name: []const u8,
    value: f64,
) bool {
    const slot = findOrCreate(
        state,
        name,
    ) orelse return false;

    slot.tag = tag_f64;
    slot.bits = @bitCast(value);

    return true;
}

pub fn getF64(
    state: *State,
    name: []const u8,
) ?f64 {
    const slot = find(
        state,
        name,
    ) orelse return null;

    if (slot.tag != tag_f64) {
        return null;
    }

    const value: f64 = @bitCast(slot.bits);

    return value;
}

pub fn setBool(
    state: *State,
    name: []const u8,
    value: bool,
) bool {
    const slot = findOrCreate(
        state,
        name,
    ) orelse return false;

    slot.tag = tag_bool;
    slot.bits = if (value) 1 else 0;

    return true;
}

pub fn getBool(
    state: *State,
    name: []const u8,
) ?bool {
    const slot = find(
        state,
        name,
    ) orelse return null;

    if (slot.tag != tag_bool) {
        return null;
    }

    return slot.bits != 0;
}

pub fn count(state: *State) usize {
    var total: usize = 0;

    for (state.slots[0..]) |*slot| {
        if (slot.tag != tag_empty) {
            total += 1;
        }
    }

    return total;
}

pub fn tagName(tag: u8) []const u8 {
    return switch (tag) {
        tag_i64 => "i64",
        tag_f64 => "f64",
        tag_bool => "bool",
        else => "unknown",
    };
}
