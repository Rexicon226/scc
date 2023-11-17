const std = @import("std");
const builtin = @import("builtin");

const ParserImport = @import("parser.zig");
const CodeGen = @import("codegen.zig");
const ErrorManager = @import("error.zig").ErrorManager;

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const allocator = arena.allocator();

const benchmark = "{ return 10; }";

fn usage() void {
    const stdout = std.io.getStdOut().writer();

    const usage_string =
        \\ Usage:
        \\ scc <file> [options]
        \\
        \\ Options:
        \\  --cli <code>  Run code as CLI
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

    if (std.mem.eql(u8, file, "--cli")) {
        const cli = args[2];

        try CodeGen.parse(
            cli,
            "",
            .{ .print = true },
            allocator,
        );

        return 0;
    } else if (std.mem.eql(u8, file, "--bench")) {
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
