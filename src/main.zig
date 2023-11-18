const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");

const ParserImport = @import("parser.zig");
const CodeGen = @import("codegen.zig");
const ErrorManager = @import("error.zig").ErrorManager;

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};

var arena = std.heap.ArenaAllocator.init(alloc: {
    if (builtin.mode == .Debug) {
        break :alloc gpa.allocator();
    } else if (builtin.link_libc) {
        break :alloc std.heap.c_allocator;
    } else {
        std.log.warn("libc not linked, had to fallback to gpa in release mode", .{});
        break :alloc gpa.allocator();
    }
});
const allocator = arena.allocator();

const benchmark = if (build_options.@"enable-bench") @embedFile("./bench/bench.c");

fn usage() void {
    const stdout = std.io.getStdOut().writer();

    const usage_string =
        \\ 
        \\ Usage:
        \\ scc <file> [options]
        \\
        \\ Options:
        \\  --cli <code> [options]  Run code as CLI
        \\               Cli Options:
        \\               --ast         Print AST
        \\
        \\  --bench       Run pre-set benchmark (only for testing purposes)
        \\  --help, -h    Print this message
        \\
    ;
    stdout.print(usage_string, .{}) catch @panic("failed to print usage");
}

pub fn main() !u8 {
    defer _ = gpa.deinit();
    defer arena.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("Invalid arguments\n", .{});
        usage();
        return 1;
    }

    const file = args[1];
    var options: CodeGen.ParserOptions = .{};

    if (std.mem.eql(u8, file, "--cli")) {
        const cli = args[2];

        options.print = true;

        if (args.len > 3) {
            if (std.mem.eql(u8, args[3], "--ast")) {
                options.printAst = true;
            }
        }

        try CodeGen.parse(
            cli,
            "",
            options,
            allocator,
        );

        return 0;
    } else if (std.mem.eql(u8, file, "--bench")) {
        if (!build_options.@"enable-bench") {
            std.log.err(
                \\Benchmarking is disabled
                \\Please recompile with -Denable-bench=true to enable benchmarking
            , .{});
            return 1;
        }

        try CodeGen.parse(
            benchmark,
            "",
            .{ .print = true },
            allocator,
        );

        return 0;
    } else if (std.mem.eql(u8, file, "--help") or std.mem.eql(u8, file, "-h")) {
        usage();
        return 0;
    }

    var source = try std.fs.cwd().openFile(file, .{});
    defer source.close();
    const source_size = (try source.stat()).size;

    // max 2 ^ 32 - 1 bytes
    if (source_size > std.math.maxInt(u32) - 1) {
        std.log.err("File too big\n", .{});
        return 1;
    }

    const data = try source.readToEndAllocOptions(allocator, source_size, null, 4, 0);

    var outputFile = std.mem.splitSequence(u8, file, ".c");
    var outputFileName = outputFile.next().?;
    outputFileName = try std.fmt.allocPrint(allocator, "{s}.s", .{outputFileName});

    try CodeGen.parse(
        data,
        outputFileName,
        null,
        allocator,
    );

    return 0;
}
