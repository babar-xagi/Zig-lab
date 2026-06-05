const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const notebook_mod = b.addModule("notebook", .{
        .root_source_file = b.path("lib/notebook.zig"),
        .target = target,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "znotebook",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the ZNotebook server");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const notebook_tests = b.addTest(.{
        .root_module = notebook_mod,
    });
    const run_notebook_tests = b.addRunArtifact(notebook_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/engine/parser.zig"),
            .target = target,
        }),
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);

    const test_step = b.step("test", "Run ZNotebook tests");
    test_step.dependOn(&run_notebook_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_parser_tests.step);
}
