const State = extern struct {
    counter: i64,
};

export fn ziglab_cell(state: *State) void {
    state.counter += 10;
}
