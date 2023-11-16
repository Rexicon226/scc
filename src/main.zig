const std = @import("std");
const tracy = @import("tracy");

const ParserImport = @import("parser.zig");
const CodeGen = @import("codegen.zig");
const ErrorManager = @import("error.zig").ErrorManager;

const builtin = @import("builtin");

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const allocator = arena.allocator();

const MB = 1024 * 1024;

const benchmark = "{ return 10; }";

fn usage() void {
    const stdout = std.io.getStdOut().writer();

    const usage_string =
        \\ Usage:
        \\ scc <file> [options]
        \\
        \\ Options:
        \\  --cli <code>  Run code as CLI
        \\  --bench       Run pre-set benchmark (100% for testing purposes)
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

    if (std.mem.eql(u8, file, "--cli")) {
        const cli = args[2];

        const errorManager = ErrorManager.init(allocator, cli);
        ParserImport.errorManager = errorManager;

        try CodeGen.parse(
            cli,
            "cli",
            .{ .print = true },
            allocator,
        );

        return 0;
    } else if (std.mem.eql(u8, file, "--bench")) {
        try CodeGen.parse(
            benchmark,
            "bench",
            .{ .print = true },
            allocator,
        );

        return 0;
    }

    var source = try std.fs.cwd().openFile(file, .{});
    defer source.close();

    const data = try source.readToEndAllocOptions(allocator, 500 * MB, null, 4, 0);

    const errorManager = ErrorManager.init(allocator, data);
    ParserImport.errorManager = errorManager;

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
