const std = @import("std");

var trace: ?bool = false;
var @"enable-bench": ?bool = false;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "scc",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Build Flags
    const enable_tests = b.option(bool, "enable-tests",
        \\Enables C files steps
    );

    @"enable-bench" = b.option(bool, "enable-bench",
        \\Embeds benchmarks into the executable and allows for --bench flag
        \\                                  - Forces ReleaseFast
    );

    trace = b.option(bool, "trace",
        \\Enables tracing of the compiler using the default backend (spall)
    );

    // Options
    const exe_options = b.addOptions();

    if (@"enable-bench") |bench| {
        if (bench) exe.optimize = .ReleaseFast;
    }

    exe_options.addOption(bool, "enable-bench", @"enable-bench" orelse false);
    exe_options.addOption(bool, "trace", trace orelse false);
    exe_options.addOption(usize, "src_file_trimlen", std.fs.path.dirname(std.fs.path.dirname(@src().file).?).?.len);

    exe.addOptions("options", exe_options);

    // Dependencies

    try addDeps(b, exe);

    // exe.use_lld = false;
    // exe.use_llvm = false;

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Testing
    if (enable_tests) |_| try addTests(b);
}

fn addDeps(
    b: *std.Build,
    exe: *std.build.Step.Compile,
) !void {
    if (trace) |_| {
        const tracer_dep = b.dependency("tracer", .{
            .target = exe.target,
        });
        exe.addModule("tracer", tracer_dep.module("tracer"));
        exe.linkLibC(); // Needs libc.
    }

    exe.linkLibC();
}

fn addTests(b: *std.Build) !void {
    var files = std.ArrayList([]const u8).init(b.allocator);
    const test_dir = try std.fs.cwd().openIterableDir("./tests", .{});

    var walker = try test_dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |w| {
        if (w.kind != .file) continue;

        if (!(std.ascii.endsWithIgnoreCase(w.basename, ".c"))) {
            continue;
        }

        try files.append(b.dupe(w.path));
    }

    const test_files = files.items;

    var steps = std.ArrayList(*std.build.Step).init(b.allocator);

    for (test_files) |file| {
        // Parse out the file
        var outputFileSplit = std.mem.splitSequence(u8, file, ".c");
        var outputFile = outputFileSplit.next().?;
        var outputFileName = try std.fmt.allocPrint(b.allocator, "{s}.s", .{outputFile});

        // Setup the ASM Build
        const test_command = [_][]const u8{
            "./zig-out/bin/scc",
            try std.fmt.allocPrint(b.allocator, "tests/{s}", .{file}),
        };
        const test_build = b.addSystemCommand(&test_command);
        const test_step = b.step(try std.fmt.allocPrint(b.allocator, "test-{s}", .{outputFile}), "Run Compiler Test");

        // Compile with Zig CC
        const cc_command = [_][]const u8{
            "zig",
            "cc",
            "-static",
            "-Wno-unused-command-line-argument",
            "-o",
            try std.fmt.allocPrint(b.allocator, "tests/{s}.o", .{outputFile}),
            try std.fmt.allocPrint(b.allocator, "tests/{s}", .{outputFileName}),
        };

        const cc_step = b.step(try std.fmt.allocPrint(b.allocator, "cc-{s}", .{outputFile}), "Compile with Zig CC");
        const cc_build = b.addSystemCommand(&cc_command);

        cc_step.dependOn(&test_build.step);
        cc_step.dependOn(&cc_build.step);

        // Run the test
        const run_command = [_][]const u8{
            "./tests/run.sh",
            try std.fmt.allocPrint(b.allocator, "tests/{s}.o", .{outputFile}),
            "0",
        };

        const run_test_step = b.step(try std.fmt.allocPrint(b.allocator, "run-{s}", .{outputFile}), "Run Test");
        const run_build = b.addSystemCommand(&run_command);

        run_test_step.dependOn(cc_step);

        run_build.step.dependOn(run_test_step);

        test_step.dependOn(b.default_step);
        test_step.dependOn(&run_build.step);

        try steps.append(test_step);
    }

    b.step("test", "Run all tests").dependencies = steps;
}
