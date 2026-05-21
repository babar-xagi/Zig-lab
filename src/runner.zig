const std = @import("std");
const Io = std.Io;

const cli_io = @import("cli_io.zig");
const notebook = @import("notebook.zig");

const GeneratedDir = ".zig-cache/zig-lab";
const OutputLimit = 10 * 1024 * 1024;

const Visibility = enum { visible, silent };

pub const RunOptions = struct {
    selected_cell: ?[]const u8 = null,
    save_outputs: bool = false,
};

pub const SavedOutputKind = enum {
    output,
    stdout,
    stderr,
    meta,

    fn suffix(kind: SavedOutputKind) []const u8 {
        return switch (kind) {
            .output => "output.txt",
            .stdout => "stdout.txt",
            .stderr => "stderr.txt",
            .meta => "meta.json",
        };
    }

    fn label(kind: SavedOutputKind) []const u8 {
        return switch (kind) {
            .output => "output",
            .stdout => "stdout",
            .stderr => "stderr",
            .meta => "meta",
        };
    }
};

const LineMap = struct {
    cell: ?notebook.Cell = null,
    cell_line: usize = 0,
    column_offset: usize = 0,
};

const GeneratedSource = struct {
    source: []u8,
    line_maps: []LineMap,

    fn deinit(self: *GeneratedSource, gpa: std.mem.Allocator) void {
        gpa.free(self.source);
        gpa.free(self.line_maps);
        self.* = undefined;
    }
};

pub const Runner = struct {
    gpa: std.mem.Allocator,
    io: Io,
    prepared_cells: std.ArrayList(notebook.Cell) = .empty,

    pub fn deinit(self: *Runner) void {
        self.prepared_cells.deinit(self.gpa);
    }

    pub fn runNotebook(self: *Runner, nb: notebook.Notebook, options: RunOptions) !void {
        try Io.Dir.cwd().createDirPath(self.io, GeneratedDir);

        if (options.selected_cell) |wanted| {
            const selected = nb.findCell(wanted) orelse {
                try cli_io.printErr(self.gpa, self.io, "cell not found: {s}\n", .{wanted});
                return error.CellNotFound;
            };

            if (selected.kind != .zig) {
                try cli_io.printErr(self.gpa, self.io, "cell is not executable Zig: {s}\n", .{wanted});
                return error.CellNotExecutable;
            }

            if (selected.depends_on.len == 0) {
                try self.preparePreviousDeclarationsBefore(nb, selected);
            }

            try self.executeCell(nb, selected, .visible, options.save_outputs);
            return;
        }

        for (nb.cells) |cell| {
            switch (cell.kind) {
                .markdown => try cli_io.print(self.gpa, self.io, "[{d}/{d}] markdown: skipped\n", .{ cell.index + 1, nb.cells.len }),
                .zig => try self.executeCell(nb, cell, .visible, options.save_outputs),
                .other => {},
            }
        }
    }

    pub fn checkNotebook(self: *Runner, nb: notebook.Notebook) !void {
        try cli_io.print(self.gpa, self.io, "Notebook OK\n\n", .{});
        try cli_io.print(self.gpa, self.io, "Cells:        {d}\n", .{nb.cells.len});
        try cli_io.print(self.gpa, self.io, "Markdown:     {d}\n", .{nb.countKind(.markdown)});
        try cli_io.print(self.gpa, self.io, "Zig:          {d}\n", .{nb.countKind(.zig)});

        var dependency_count: usize = 0;
        var has_dependency_error = false;
        for (nb.cells) |cell| {
            dependency_count += cell.depends_on.len;
            for (cell.depends_on) |dep| {
                const dep_cell = nb.findCell(dep) orelse {
                    has_dependency_error = true;
                    try cli_io.printErr(self.gpa, self.io, "missing dependency for cell {s}: {s}\n", .{ cell.displayName(), dep });
                    continue;
                };

                if (dep_cell.kind != .zig or effectiveMode(dep_cell) != .decl) {
                    has_dependency_error = true;
                    try cli_io.printErr(self.gpa, self.io, "dependency must be a Zig declaration cell: {s} -> {s}\n", .{ cell.displayName(), dep });
                }
            }
        }

        try cli_io.print(self.gpa, self.io, "Dependencies: {d}\n", .{dependency_count});
        if (has_dependency_error) return error.InvalidNotebook;
    }

    pub fn listNotebook(self: *Runner, nb: notebook.Notebook) !void {
        try cli_io.print(self.gpa, self.io, "Notebook: {s}\n", .{nb.path});
        try cli_io.print(self.gpa, self.io, "Cells:    {d}\n\n", .{nb.cells.len});

        for (nb.cells) |cell| {
            try cli_io.print(self.gpa, self.io, "[{d}] {s}", .{ cell.index + 1, kindLabel(cell.kind) });

            if (cell.id) |id| {
                try cli_io.print(self.gpa, self.io, " {s}", .{id});
            } else {
                try cli_io.print(self.gpa, self.io, " <no-id>", .{});
            }

            if (cell.kind == .zig) {
                try cli_io.print(self.gpa, self.io, " mode={s}", .{effectiveMode(cell).label()});
                if (cell.mode == .auto) {
                    try cli_io.print(self.gpa, self.io, " inferred", .{});
                }
            }

            if (cell.depends_on.len > 0) {
                try cli_io.write(self.io, " depends-on=");
                for (cell.depends_on, 0..) |dep, dep_index| {
                    if (dep_index > 0) try cli_io.write(self.io, ",");
                    try cli_io.write(self.io, dep);
                }
            }

            try cli_io.print(self.gpa, self.io, " line={d}\n", .{cell.source_start_line});
        }
    }

    pub fn listOutputs(self: *Runner, nb: notebook.Notebook) !void {
        const output_dir = try std.fmt.allocPrint(self.gpa, "{s}.outputs", .{nb.path});
        defer self.gpa.free(output_dir);

        try cli_io.print(self.gpa, self.io, "Notebook: {s}\n", .{nb.path});
        try cli_io.print(self.gpa, self.io, "Outputs:  {s}\n\n", .{output_dir});

        var saved_count: usize = 0;
        for (nb.cells) |cell| {
            if (cell.kind != .zig) continue;

            const files = try self.outputFileStats(output_dir, cell);
            if (!files.hasAny()) continue;

            saved_count += 1;
            try cli_io.print(self.gpa, self.io, "[{d}] {s} mode={s}", .{ cell.index + 1, cell.displayName(), effectiveMode(cell).label() });
            if (files.output) |size| try cli_io.print(self.gpa, self.io, " output={d}B", .{size});
            if (files.stdout) |size| try cli_io.print(self.gpa, self.io, " stdout={d}B", .{size});
            if (files.stderr) |size| try cli_io.print(self.gpa, self.io, " stderr={d}B", .{size});
            if (files.meta) |size| try cli_io.print(self.gpa, self.io, " meta={d}B", .{size});
            try cli_io.write(self.io, "\n");
        }

        if (saved_count == 0) {
            try cli_io.write(self.io, "No saved outputs found. Run a cell with --save-outputs first.\n");
        }
    }

    pub fn showOutput(self: *Runner, nb: notebook.Notebook, cell_id: []const u8, kind: SavedOutputKind) !void {
        const cell = nb.findCell(cell_id) orelse {
            try cli_io.printErr(self.gpa, self.io, "cell not found: {s}\n", .{cell_id});
            return error.CellNotFound;
        };

        const output_dir = try std.fmt.allocPrint(self.gpa, "{s}.outputs", .{nb.path});
        defer self.gpa.free(output_dir);

        const stem = try cellOutputStem(self.gpa, cell);
        defer self.gpa.free(stem);

        const path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.{s}", .{ output_dir, stem, kind.suffix() });
        defer self.gpa.free(path);

        const data = Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(OutputLimit)) catch |err| switch (err) {
            error.FileNotFound => {
                try cli_io.printErr(self.gpa, self.io, "saved {s} not found for cell {s}: {s}\n", .{ kind.label(), cell.displayName(), path });
                return error.OutputNotFound;
            },
            else => |e| return e,
        };
        defer self.gpa.free(data);

        try cli_io.write(self.io, data);
        if (data.len > 0 and !std.mem.endsWith(u8, data, "\n")) {
            try cli_io.write(self.io, "\n");
        }
    }

    pub fn exportNotebook(self: *Runner, nb: notebook.Notebook, out_path: ?[]const u8) !void {
        var exported: std.ArrayList(u8) = .empty;
        defer exported.deinit(self.gpa);

        var declarations: std.ArrayList(u8) = .empty;
        defer declarations.deinit(self.gpa);

        var main_body: std.ArrayList(u8) = .empty;
        defer main_body.deinit(self.gpa);

        var tests: std.ArrayList(u8) = .empty;
        defer tests.deinit(self.gpa);

        try exported.appendSlice(self.gpa, "// Generated by Zig-lab.\n");
        try exported.appendSlice(self.gpa, "// Declaration cells stay top-level; run cells are placed in main().\n\n");

        for (nb.cells) |cell| {
            if (cell.kind != .zig) continue;
            const header = try std.fmt.allocPrint(self.gpa, "// cell {d}: {s}\n", .{ cell.index + 1, cell.displayName() });
            defer self.gpa.free(header);

            switch (effectiveMode(cell)) {
                .test_ => {
                    try tests.appendSlice(self.gpa, header);
                    try tests.appendSlice(self.gpa, cell.source);
                    if (!std.mem.endsWith(u8, cell.source, "\n")) try tests.append(self.gpa, '\n');
                    try tests.append(self.gpa, '\n');
                },
                .run => {
                    try main_body.appendSlice(self.gpa, "    ");
                    try main_body.appendSlice(self.gpa, header);
                    try appendIndented(self.gpa, &main_body, cell.source);
                    try main_body.append(self.gpa, '\n');
                },
                .decl, .auto => {
                    try declarations.appendSlice(self.gpa, header);
                    try declarations.appendSlice(self.gpa, cell.source);
                    if (!std.mem.endsWith(u8, cell.source, "\n")) try declarations.append(self.gpa, '\n');
                    try declarations.append(self.gpa, '\n');
                },
            }
        }

        try exported.appendSlice(self.gpa, declarations.items);

        if (main_body.items.len > 0) {
            trimTrailingNewlines(&main_body);
            try exported.appendSlice(self.gpa, "pub fn main() !void {\n");
            try exported.appendSlice(self.gpa, main_body.items);
            try exported.appendSlice(self.gpa, "\n}\n\n");
        } else {
            try exported.appendSlice(self.gpa, "pub fn main() !void {}\n\n");
        }

        try exported.appendSlice(self.gpa, tests.items);

        if (out_path) |path| {
            try Io.Dir.cwd().writeFile(self.io, .{
                .sub_path = path,
                .data = exported.items,
            });
            try cli_io.print(self.gpa, self.io, "exported: {s}\n", .{path});
        } else {
            try cli_io.write(self.io, exported.items);
        }
    }

    fn executeCell(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, visibility: Visibility, save_outputs: bool) !void {
        try self.prepareDependencies(nb, cell);

        switch (effectiveMode(cell)) {
            .test_ => try self.executeTestCell(nb, cell, visibility, save_outputs),
            .run => try self.executeRunCell(nb, cell, visibility, save_outputs),
            .decl => try self.prepareDeclarationCell(nb, cell, visibility, save_outputs),
            .auto => unreachable,
        }
    }

    fn executeRunCell(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, visibility: Visibility, save_outputs: bool) !void {
        var generated = try self.buildRunSource(cell);
        defer generated.deinit(self.gpa);

        const path = try self.writeGeneratedSource(cell.index, "run", generated.source);
        defer self.gpa.free(path);

        var result = try self.runCommand(&.{ "zig", "run", path });
        defer result.deinit(self.gpa);

        if (visibility == .visible) {
            const status: []const u8 = if (result.succeeded()) "ran" else "failed";
            try cli_io.print(self.gpa, self.io, "[{d}/{d}] {s}: {s}\n", .{ cell.index + 1, nb.cells.len, cell.displayName(), status });
            try self.writeCommandOutput(nb, cell, result, path, generated.line_maps, save_outputs);
        }

        if (!result.succeeded()) return error.CellFailed;
    }

    fn executeTestCell(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, visibility: Visibility, save_outputs: bool) !void {
        var generated = try self.buildTestSource(cell);
        defer generated.deinit(self.gpa);

        const path = try self.writeGeneratedSource(cell.index, "test", generated.source);
        defer self.gpa.free(path);

        var result = try self.runCommand(&.{ "zig", "test", path });
        defer result.deinit(self.gpa);

        if (visibility == .visible) {
            const status: []const u8 = if (result.succeeded()) "passed" else "failed";
            try cli_io.print(self.gpa, self.io, "[{d}/{d}] {s}: test {s}\n", .{ cell.index + 1, nb.cells.len, cell.displayName(), status });
            try self.writeCommandOutput(nb, cell, result, path, generated.line_maps, save_outputs);
            if (result.succeeded() and result.stdout.len == 0 and result.stderr.len == 0) {
                try cli_io.print(self.gpa, self.io, "All tests passed.\n", .{});
            }
        }

        if (!result.succeeded()) return error.CellFailed;
    }

    fn preparePreviousDeclarationsBefore(self: *Runner, nb: notebook.Notebook, target: notebook.Cell) !void {
        for (nb.cells) |cell| {
            if (cell.index >= target.index) break;
            if (cell.kind != .zig) continue;
            if (effectiveMode(cell) != .decl) continue;

            try self.prepareDependencies(nb, cell);
            try self.prepareDeclarationCell(nb, cell, .silent, false);
        }
    }

    fn prepareDependencies(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell) !void {
        var visiting: std.ArrayList(usize) = .empty;
        defer visiting.deinit(self.gpa);

        try self.prepareDependenciesInternal(nb, cell, &visiting);
    }

    fn prepareDependenciesInternal(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, visiting: *std.ArrayList(usize)) !void {
        for (cell.depends_on) |dep| {
            const dep_cell = nb.findCell(dep) orelse {
                try cli_io.printErr(self.gpa, self.io, "missing dependency for cell {s}: {s}\n", .{ cell.displayName(), dep });
                return error.DependencyNotFound;
            };

            if (dep_cell.kind != .zig or effectiveMode(dep_cell) != .decl) {
                try cli_io.printErr(self.gpa, self.io, "dependency must be a Zig declaration cell: {s} -> {s}\n", .{ cell.displayName(), dep });
                return error.DependencyNotDeclaration;
            }

            if (self.isPrepared(dep_cell)) continue;

            for (visiting.items) |index| {
                if (index == dep_cell.index) {
                    try cli_io.printErr(self.gpa, self.io, "dependency cycle includes cell: {s}\n", .{dep_cell.displayName()});
                    return error.DependencyCycle;
                }
            }

            try visiting.append(self.gpa, dep_cell.index);
            defer _ = visiting.pop();

            try self.prepareDependenciesInternal(nb, dep_cell, visiting);
            try self.prepareDeclarationCell(nb, dep_cell, .silent, false);
        }
    }

    fn prepareDeclarationCell(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, visibility: Visibility, save_outputs: bool) !void {
        if (self.isPrepared(cell)) {
            if (visibility == .visible) {
                try cli_io.print(self.gpa, self.io, "[{d}/{d}] {s}: ready (cached)\n", .{ cell.index + 1, nb.cells.len, cell.displayName() });
            }
            return;
        }

        var generated = try self.buildDeclarationSource(cell);
        defer generated.deinit(self.gpa);

        const path = try self.writeGeneratedSource(cell.index, "decl", generated.source);
        defer self.gpa.free(path);

        var result = try self.runCommand(&.{ "zig", "build-exe", path, "-fno-emit-bin" });
        defer result.deinit(self.gpa);

        if (result.succeeded()) {
            try self.prepared_cells.append(self.gpa, cell);
            if (visibility == .visible) {
                try cli_io.print(self.gpa, self.io, "[{d}/{d}] {s}: ready\n", .{ cell.index + 1, nb.cells.len, cell.displayName() });
                try self.writeCommandOutput(nb, cell, result, path, generated.line_maps, save_outputs);
            }
            return;
        }

        if (visibility == .visible) {
            try cli_io.print(self.gpa, self.io, "[{d}/{d}] {s}: failed\n", .{ cell.index + 1, nb.cells.len, cell.displayName() });
        } else {
            try cli_io.printErr(self.gpa, self.io, "failed while preparing cell {s}\n", .{cell.displayName()});
        }
        try self.writeCommandOutput(nb, cell, result, path, generated.line_maps, save_outputs);
        return error.CellFailed;
    }

    fn isPrepared(self: Runner, cell: notebook.Cell) bool {
        for (self.prepared_cells.items) |prepared| {
            if (prepared.index == cell.index) return true;
        }
        return false;
    }

    fn buildDeclarationSource(self: *Runner, cell: notebook.Cell) !GeneratedSource {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.gpa);

        var line_maps: std.ArrayList(LineMap) = .empty;
        errdefer line_maps.deinit(self.gpa);

        try appendNoMap(self.gpa, &output, &line_maps, "// Generated by Zig-lab for declaration checking.\n\n");
        try self.appendPreparedCells(&output, &line_maps);
        try appendMappedCellSource(self.gpa, &output, &line_maps, cell, "");
        try appendNoMap(self.gpa, &output, &line_maps, "\npub fn main() !void {}\n");

        const source = try output.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(source);
        const maps = try line_maps.toOwnedSlice(self.gpa);

        return .{ .source = source, .line_maps = maps };
    }

    fn buildRunSource(self: *Runner, cell: notebook.Cell) !GeneratedSource {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.gpa);

        var line_maps: std.ArrayList(LineMap) = .empty;
        errdefer line_maps.deinit(self.gpa);

        try appendNoMap(self.gpa, &output, &line_maps, "// Generated by Zig-lab for cell execution.\n\n");
        try self.appendPreparedCells(&output, &line_maps);
        try appendNoMap(self.gpa, &output, &line_maps, "pub fn main() !void {\n");
        try appendMappedCellSource(self.gpa, &output, &line_maps, cell, "    ");
        try appendNoMap(self.gpa, &output, &line_maps, "}\n");

        const source = try output.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(source);
        const maps = try line_maps.toOwnedSlice(self.gpa);

        return .{ .source = source, .line_maps = maps };
    }

    fn buildTestSource(self: *Runner, cell: notebook.Cell) !GeneratedSource {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.gpa);

        var line_maps: std.ArrayList(LineMap) = .empty;
        errdefer line_maps.deinit(self.gpa);

        try appendNoMap(self.gpa, &output, &line_maps, "// Generated by Zig-lab for test execution.\n\n");
        try self.appendPreparedCells(&output, &line_maps);
        try appendMappedCellSource(self.gpa, &output, &line_maps, cell, "");

        const source = try output.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(source);
        const maps = try line_maps.toOwnedSlice(self.gpa);

        return .{ .source = source, .line_maps = maps };
    }

    fn appendPreparedCells(self: *Runner, output: *std.ArrayList(u8), line_maps: *std.ArrayList(LineMap)) !void {
        for (self.prepared_cells.items) |cell| {
            try appendMappedCellSource(self.gpa, output, line_maps, cell, "");
            try appendNoMap(self.gpa, output, line_maps, "\n");
        }
    }

    fn writeGeneratedSource(self: *Runner, cell_index: usize, suffix: []const u8, source: []const u8) ![]u8 {
        const path = try std.fmt.allocPrint(self.gpa, GeneratedDir ++ "/cell_{d}_{s}.zig", .{ cell_index + 1, suffix });
        errdefer self.gpa.free(path);

        try Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = path,
            .data = source,
        });

        return path;
    }

    fn runCommand(self: *Runner, argv: []const []const u8) !CommandResult {
        const result = try std.process.run(self.gpa, self.io, .{
            .argv = argv,
            .stdout_limit = .limited(OutputLimit),
            .stderr_limit = .limited(OutputLimit),
        });

        return .{
            .term = result.term,
            .stdout = result.stdout,
            .stderr = result.stderr,
        };
    }

    fn writeCommandOutput(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, result: CommandResult, generated_path: []const u8, line_maps: []const LineMap, save_outputs: bool) !void {
        const rewritten_stderr = if (result.stderr.len > 0)
            try rewriteDiagnostics(self.gpa, result.stderr, generated_path, nb.path, line_maps)
        else
            try self.gpa.dupe(u8, "");
        defer self.gpa.free(rewritten_stderr);

        if (result.stdout.len > 0) {
            try cli_io.write(self.io, result.stdout);
            if (!std.mem.endsWith(u8, result.stdout, "\n")) try cli_io.write(self.io, "\n");
        }
        if (rewritten_stderr.len > 0) {
            try cli_io.write(self.io, rewritten_stderr);
            if (!std.mem.endsWith(u8, rewritten_stderr, "\n")) try cli_io.write(self.io, "\n");
        }

        if (save_outputs) {
            try self.saveCellOutput(nb, cell, result, rewritten_stderr);
        }
    }

    fn saveCellOutput(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, result: CommandResult, stderr: []const u8) !void {
        const output_dir = try std.fmt.allocPrint(self.gpa, "{s}.outputs", .{nb.path});
        defer self.gpa.free(output_dir);

        try Io.Dir.cwd().createDirPath(self.io, output_dir);

        const stem = try cellOutputStem(self.gpa, cell);
        defer self.gpa.free(stem);

        const stdout_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.stdout.txt", .{ output_dir, stem });
        defer self.gpa.free(stdout_path);
        const stderr_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.stderr.txt", .{ output_dir, stem });
        defer self.gpa.free(stderr_path);
        const output_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.output.txt", .{ output_dir, stem });
        defer self.gpa.free(output_path);
        const meta_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.meta.json", .{ output_dir, stem });
        defer self.gpa.free(meta_path);

        var combined: std.ArrayList(u8) = .empty;
        defer combined.deinit(self.gpa);
        try combined.appendSlice(self.gpa, result.stdout);
        if (result.stdout.len > 0 and stderr.len > 0 and !std.mem.endsWith(u8, result.stdout, "\n")) {
            try combined.append(self.gpa, '\n');
        }
        try combined.appendSlice(self.gpa, stderr);

        const meta = try self.buildOutputMeta(nb, cell, result, stderr.len, combined.items.len);
        defer self.gpa.free(meta);

        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = stdout_path, .data = result.stdout });
        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = stderr_path, .data = stderr });
        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = output_path, .data = combined.items });
        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = meta_path, .data = meta });

        try cli_io.print(self.gpa, self.io, "outputs saved: {s}\n", .{output_dir});
    }

    fn buildOutputMeta(self: *Runner, nb: notebook.Notebook, cell: notebook.Cell, result: CommandResult, stderr_len: usize, output_len: usize) ![]u8 {
        var meta: std.ArrayList(u8) = .empty;
        errdefer meta.deinit(self.gpa);

        try meta.appendSlice(self.gpa, "{\n");
        try appendJsonFieldString(self.gpa, &meta, "notebook", nb.path, true);
        try appendJsonFieldString(self.gpa, &meta, "cell_id", cell.displayName(), true);
        try appendJsonFieldNumber(self.gpa, &meta, "cell_index", cell.index + 1, true);
        try appendJsonFieldString(self.gpa, &meta, "mode", effectiveMode(cell).label(), true);
        try appendJsonFieldString(self.gpa, &meta, "status", statusLabel(cell, result), true);
        try appendJsonFieldBool(self.gpa, &meta, "succeeded", result.succeeded(), true);
        if (exitCode(result.term)) |code| {
            try appendJsonFieldNumber(self.gpa, &meta, "exit_code", code, true);
        } else {
            try meta.appendSlice(self.gpa, "  \"exit_code\": null,\n");
        }
        try appendJsonFieldNumber(self.gpa, &meta, "stdout_bytes", result.stdout.len, true);
        try appendJsonFieldNumber(self.gpa, &meta, "stderr_bytes", stderr_len, true);
        try appendJsonFieldNumber(self.gpa, &meta, "output_bytes", output_len, false);
        try meta.appendSlice(self.gpa, "}\n");

        return meta.toOwnedSlice(self.gpa);
    }

    fn outputFileStats(self: *Runner, output_dir: []const u8, cell: notebook.Cell) !OutputFileStats {
        const stem = try cellOutputStem(self.gpa, cell);
        defer self.gpa.free(stem);

        const stdout_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.stdout.txt", .{ output_dir, stem });
        defer self.gpa.free(stdout_path);
        const stderr_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.stderr.txt", .{ output_dir, stem });
        defer self.gpa.free(stderr_path);
        const output_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.output.txt", .{ output_dir, stem });
        defer self.gpa.free(output_path);
        const meta_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}.meta.json", .{ output_dir, stem });
        defer self.gpa.free(meta_path);

        return .{
            .stdout = try self.fileSizeOrNull(stdout_path),
            .stderr = try self.fileSizeOrNull(stderr_path),
            .output = try self.fileSizeOrNull(output_path),
            .meta = try self.fileSizeOrNull(meta_path),
        };
    }

    fn fileSizeOrNull(self: *Runner, path: []const u8) !?u64 {
        const stat = Io.Dir.cwd().statFile(self.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => |e| return e,
        };
        return stat.size;
    }
};

const OutputFileStats = struct {
    stdout: ?u64 = null,
    stderr: ?u64 = null,
    output: ?u64 = null,
    meta: ?u64 = null,

    fn hasAny(stats: OutputFileStats) bool {
        return stats.stdout != null or stats.stderr != null or stats.output != null or stats.meta != null;
    }
};

const CommandResult = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: *CommandResult, gpa: std.mem.Allocator) void {
        gpa.free(self.stdout);
        gpa.free(self.stderr);
        self.* = undefined;
    }

    fn succeeded(self: CommandResult) bool {
        return switch (self.term) {
            .exited => |code| code == 0,
            else => false,
        };
    }
};

fn appendNoMap(gpa: std.mem.Allocator, output: *std.ArrayList(u8), line_maps: *std.ArrayList(LineMap), text: []const u8) !void {
    try output.appendSlice(gpa, text);
    for (text) |char| {
        if (char == '\n') try line_maps.append(gpa, .{});
    }
}

fn appendMappedCellSource(
    gpa: std.mem.Allocator,
    output: *std.ArrayList(u8),
    line_maps: *std.ArrayList(LineMap),
    cell: notebook.Cell,
    indent: []const u8,
) !void {
    var offset: usize = 0;
    var cell_line: usize = 1;
    while (offset < cell.source.len) : (cell_line += 1) {
        const newline_index = std.mem.indexOfScalarPos(u8, cell.source, offset, '\n') orelse cell.source.len;
        const line = cell.source[offset..newline_index];
        if (line.len > 0) try output.appendSlice(gpa, indent);
        try output.appendSlice(gpa, line);
        try output.append(gpa, '\n');
        try line_maps.append(gpa, .{
            .cell = cell,
            .cell_line = cell_line,
            .column_offset = if (line.len > 0) indent.len else 0,
        });
        offset = if (newline_index < cell.source.len) newline_index + 1 else cell.source.len;
    }
}

fn appendIndented(gpa: std.mem.Allocator, output: *std.ArrayList(u8), source: []const u8) !void {
    var offset: usize = 0;
    while (offset < source.len) {
        const newline_index = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse source.len;
        const line = source[offset..newline_index];
        if (line.len > 0) {
            try output.appendSlice(gpa, "    ");
            try output.appendSlice(gpa, line);
        }
        try output.append(gpa, '\n');
        offset = if (newline_index < source.len) newline_index + 1 else source.len;
    }
}

fn trimTrailingNewlines(output: *std.ArrayList(u8)) void {
    while (output.items.len > 0 and output.items[output.items.len - 1] == '\n') {
        output.items.len -= 1;
    }
}

fn rewriteDiagnostics(
    gpa: std.mem.Allocator,
    text: []const u8,
    generated_path: []const u8,
    notebook_path: []const u8,
    line_maps: []const LineMap,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);

    var offset: usize = 0;
    while (offset < text.len) {
        const newline_index = std.mem.indexOfScalarPos(u8, text, offset, '\n') orelse text.len;
        const line = text[offset..newline_index];
        try appendRewrittenDiagnosticLine(gpa, &output, line, generated_path, notebook_path, line_maps);
        if (newline_index < text.len) try output.append(gpa, '\n');
        offset = if (newline_index < text.len) newline_index + 1 else text.len;
    }

    return output.toOwnedSlice(gpa);
}

fn appendRewrittenDiagnosticLine(
    gpa: std.mem.Allocator,
    output: *std.ArrayList(u8),
    line: []const u8,
    generated_path: []const u8,
    notebook_path: []const u8,
    line_maps: []const LineMap,
) !void {
    const diagnostic = parseGeneratedDiagnostic(line, generated_path) orelse {
        try output.appendSlice(gpa, line);
        return;
    };

    if (diagnostic.line == 0 or diagnostic.line > line_maps.len) {
        try output.appendSlice(gpa, line);
        return;
    }

    const map = line_maps[diagnostic.line - 1];
    const cell = map.cell orelse {
        try output.appendSlice(gpa, line);
        return;
    };

    const mapped_column = if (diagnostic.column > map.column_offset)
        diagnostic.column - map.column_offset
    else
        1;
    const notebook_line = cell.source_start_line + map.cell_line - 1;

    const rewritten = try std.fmt.allocPrint(
        gpa,
        "{s}:{d}:{d}: cell {s} line {d}{s}",
        .{ notebook_path, notebook_line, mapped_column, cell.displayName(), map.cell_line, diagnostic.rest },
    );
    defer gpa.free(rewritten);

    try output.appendSlice(gpa, rewritten);
}

const ParsedDiagnostic = struct {
    line: usize,
    column: usize,
    rest: []const u8,
};

fn parseGeneratedDiagnostic(line: []const u8, generated_path: []const u8) ?ParsedDiagnostic {
    const path_index = indexOfPathFlexible(line, generated_path) orelse return null;
    var index = path_index + generated_path.len;

    if (index >= line.len or line[index] != ':') return null;
    index += 1;

    const line_start = index;
    while (index < line.len and std.ascii.isDigit(line[index])) index += 1;
    if (line_start == index or index >= line.len or line[index] != ':') return null;
    const generated_line = std.fmt.parseUnsigned(usize, line[line_start..index], 10) catch return null;
    index += 1;

    const column_start = index;
    while (index < line.len and std.ascii.isDigit(line[index])) index += 1;
    if (column_start == index) return null;
    const generated_column = std.fmt.parseUnsigned(usize, line[column_start..index], 10) catch return null;

    return .{
        .line = generated_line,
        .column = generated_column,
        .rest = line[index..],
    };
}

fn indexOfPathFlexible(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > haystack.len) return null;

    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        var i: usize = 0;
        while (i < needle.len) : (i += 1) {
            if (!pathCharsEqual(haystack[start + i], needle[i])) break;
        } else {
            return start;
        }
    }

    return null;
}

fn pathCharsEqual(a: u8, b: u8) bool {
    if ((a == '/' or a == '\\') and (b == '/' or b == '\\')) return true;
    return a == b;
}

fn effectiveMode(cell: notebook.Cell) notebook.CellMode {
    if (cell.mode != .auto) return cell.mode;
    if (isTestCell(cell.source)) return .test_;
    if (containsLikelyStatement(cell.source)) return .run;
    return .decl;
}

fn kindLabel(kind: notebook.CellKind) []const u8 {
    return switch (kind) {
        .markdown => "markdown",
        .zig => "zig",
        .other => "other",
    };
}

fn statusLabel(cell: notebook.Cell, result: CommandResult) []const u8 {
    if (!result.succeeded()) return "failed";
    return switch (effectiveMode(cell)) {
        .decl => "ready",
        .run => "ran",
        .test_ => "passed",
        .auto => "ready",
    };
}

fn exitCode(term: std.process.Child.Term) ?u8 {
    return switch (term) {
        .exited => |code| code,
        else => null,
    };
}

fn cellOutputStem(gpa: std.mem.Allocator, cell: notebook.Cell) ![]u8 {
    if (cell.id) |id| {
        var stem: std.ArrayList(u8) = .empty;
        errdefer stem.deinit(gpa);

        for (id) |char| {
            try stem.append(gpa, if (isSafeFileChar(char)) char else '_');
        }

        if (stem.items.len == 0) {
            try stem.appendSlice(gpa, "cell");
        }

        return stem.toOwnedSlice(gpa);
    }

    return std.fmt.allocPrint(gpa, "cell_{d}", .{cell.index + 1});
}

fn isSafeFileChar(char: u8) bool {
    return (char >= 'a' and char <= 'z') or
        (char >= 'A' and char <= 'Z') or
        (char >= '0' and char <= '9') or
        char == '-' or
        char == '_' or
        char == '.';
}

fn appendJsonFieldString(gpa: std.mem.Allocator, output: *std.ArrayList(u8), key: []const u8, value: []const u8, comma: bool) !void {
    try output.appendSlice(gpa, "  ");
    try appendJsonString(gpa, output, key);
    try output.appendSlice(gpa, ": ");
    try appendJsonString(gpa, output, value);
    try output.appendSlice(gpa, if (comma) ",\n" else "\n");
}

fn appendJsonFieldNumber(gpa: std.mem.Allocator, output: *std.ArrayList(u8), key: []const u8, value: anytype, comma: bool) !void {
    const number = try std.fmt.allocPrint(gpa, "{}", .{value});
    defer gpa.free(number);

    try output.appendSlice(gpa, "  ");
    try appendJsonString(gpa, output, key);
    try output.appendSlice(gpa, ": ");
    try output.appendSlice(gpa, number);
    try output.appendSlice(gpa, if (comma) ",\n" else "\n");
}

fn appendJsonFieldBool(gpa: std.mem.Allocator, output: *std.ArrayList(u8), key: []const u8, value: bool, comma: bool) !void {
    try output.appendSlice(gpa, "  ");
    try appendJsonString(gpa, output, key);
    try output.appendSlice(gpa, ": ");
    try output.appendSlice(gpa, if (value) "true" else "false");
    try output.appendSlice(gpa, if (comma) ",\n" else "\n");
}

fn appendJsonString(gpa: std.mem.Allocator, output: *std.ArrayList(u8), value: []const u8) !void {
    try output.append(gpa, '"');
    for (value) |char| {
        switch (char) {
            '"' => try output.appendSlice(gpa, "\\\""),
            '\\' => try output.appendSlice(gpa, "\\\\"),
            '\n' => try output.appendSlice(gpa, "\\n"),
            '\r' => try output.appendSlice(gpa, "\\r"),
            '\t' => try output.appendSlice(gpa, "\\t"),
            else => {
                if (char < 0x20) {
                    const hex = "0123456789abcdef";
                    try output.appendSlice(gpa, "\\u00");
                    try output.append(gpa, hex[char >> 4]);
                    try output.append(gpa, hex[char & 0x0f]);
                } else {
                    try output.append(gpa, char);
                }
            },
        }
    }
    try output.append(gpa, '"');
}

fn isTestCell(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "test ")) return true;
    }
    return false;
}

fn containsLikelyStatement(source: []const u8) bool {
    if (startsAsFunctionDeclaration(source)) return false;

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;

        if (startsWithAny(trimmed, &.{
            "std.",
            "try ",
            "_ =",
            "return ",
            "defer ",
            "for ",
            "while ",
            "if ",
            "switch ",
            "break",
            "continue",
        })) return true;

        if (std.mem.endsWith(u8, trimmed, ";") and !startsWithAny(trimmed, &.{
            "const ",
            "var ",
            "fn ",
            "pub ",
            "test ",
            "extern ",
            "export ",
            "comptime ",
            "usingnamespace ",
        })) return true;
    }
    return false;
}

fn startsAsFunctionDeclaration(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        return std.mem.startsWith(u8, trimmed, "fn ") or std.mem.startsWith(u8, trimmed, "pub fn ");
    }
    return false;
}

fn startsWithAny(value: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.startsWith(u8, value, needle)) return true;
    }
    return false;
}

test "statement detection catches simple print cells" {
    try std.testing.expect(containsLikelyStatement(
        \\const name = "Zig-lab";
        \\std.debug.print("hello {s}\n", .{name});
    ));
}

test "diagnostics rewrite generated file locations to notebook locations" {
    const cell: notebook.Cell = .{
        .index = 0,
        .kind = .zig,
        .language = "zig",
        .id = "answer",
        .mode = .run,
        .depends_on = &.{},
        .source = "const answer = missing;\n",
        .source_start_line = 12,
    };
    const maps = [_]LineMap{
        .{},
        .{ .cell = cell, .cell_line = 1, .column_offset = 4 },
    };

    const rewritten = try rewriteDiagnostics(
        std.testing.allocator,
        ".zig-cache\\zig-lab\\cell_1_run.zig:2:20: error: use of undeclared identifier 'missing'\n",
        ".zig-cache/zig-lab/cell_1_run.zig",
        "examples/error.ziglab",
        &maps,
    );
    defer std.testing.allocator.free(rewritten);

    try std.testing.expectEqualStrings(
        "examples/error.ziglab:12:16: cell answer line 1: error: use of undeclared identifier 'missing'\n",
        rewritten,
    );
}
