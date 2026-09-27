pub const max_name_len: usize = 48;


pub const Context = extern struct {
    userdata: *anyopaque,

    set_i64_fn: *const fn (
        *anyopaque,
        [*:0]const u8,
        i64,
    ) callconv(.c) u8,

    get_i64_fn: *const fn (
        *anyopaque,
        [*:0]const u8,
        *i64,
    ) callconv(.c) u8,

    set_f64_fn: *const fn (
        *anyopaque,
        [*:0]const u8,
        f64,
    ) callconv(.c) u8,

    get_f64_fn: *const fn (
        *anyopaque,
        [*:0]const u8,
        *f64,
    ) callconv(.c) u8,

    set_bool_fn: *const fn (
        *anyopaque,
        [*:0]const u8,
        u8,
    ) callconv(.c) u8,

    get_bool_fn: *const fn (
        *anyopaque,
        [*:0]const u8,
        *u8,
    ) callconv(.c) u8,
};


pub const State = Context;


fn makeName(
    name: []const u8,
    buffer: *[max_name_len + 1]u8,
) ?[*:0]const u8 {
    if (
        name.len == 0 or
        name.len > max_name_len
    ) {
        return null;
    }

    @memset(buffer[0..], 0);

    @memcpy(
        buffer[0..name.len],
        name,
    );

    buffer[name.len] = 0;

    const z_name = buffer[0..name.len :0];

    return z_name.ptr;
}


pub fn setI64(
    state: *State,
    name: []const u8,
    value: i64,
) bool {
    var buffer: [max_name_len + 1]u8 =
        undefined;

    const z_name = makeName(
        name,
        &buffer,
    ) orelse return false;

    return state.set_i64_fn(
        state.userdata,
        z_name,
        value,
    ) != 0;
}


pub fn getI64(
    state: *State,
    name: []const u8,
) ?i64 {
    var buffer: [max_name_len + 1]u8 =
        undefined;

    const z_name = makeName(
        name,
        &buffer,
    ) orelse return null;

    var value: i64 = undefined;

    const found = state.get_i64_fn(
        state.userdata,
        z_name,
        &value,
    );

    if (found == 0) {
        return null;
    }

    return value;
}


pub fn setF64(
    state: *State,
    name: []const u8,
    value: f64,
) bool {
    var buffer: [max_name_len + 1]u8 =
        undefined;

    const z_name = makeName(
        name,
        &buffer,
    ) orelse return false;

    return state.set_f64_fn(
        state.userdata,
        z_name,
        value,
    ) != 0;
}


pub fn getF64(
    state: *State,
    name: []const u8,
) ?f64 {
    var buffer: [max_name_len + 1]u8 =
        undefined;

    const z_name = makeName(
        name,
        &buffer,
    ) orelse return null;

    var value: f64 = undefined;

    const found = state.get_f64_fn(
        state.userdata,
        z_name,
        &value,
    );

    if (found == 0) {
        return null;
    }

    return value;
}


pub fn setBool(
    state: *State,
    name: []const u8,
    value: bool,
) bool {
    var buffer: [max_name_len + 1]u8 =
        undefined;

    const z_name = makeName(
        name,
        &buffer,
    ) orelse return false;

    return state.set_bool_fn(
        state.userdata,
        z_name,
        if (value) 1 else 0,
    ) != 0;
}


pub fn getBool(
    state: *State,
    name: []const u8,
) ?bool {
    var buffer: [max_name_len + 1]u8 =
        undefined;

    const z_name = makeName(
        name,
        &buffer,
    ) orelse return null;

    var value: u8 = 0;

    const found = state.get_bool_fn(
        state.userdata,
        z_name,
        &value,
    );

    if (found == 0) {
        return null;
    }

    return value != 0;
}
