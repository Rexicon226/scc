const std = @import("std");
const ParserImport = @import("parser.zig");
const CodeGen = @import("codegen.zig");
const ErrorManager = @import("error.zig").ErrorManager;

const builtin = @import("builtin");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const allocator = arena.allocator();

const MB = 1024 * 1024;

const stdout = std.io.getStdOut().writer();

pub fn print(comptime source: []const u8, args: anytype) void {
    stdout.print(source, args) catch |err| {
        std.log.err("Unable to print: {}\n", .{err});
        @panic("Unable to print");
    };
}

// Main
pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    ParserImport.allocator = allocator;

    CodeGen.allocator = allocator;

    if (args.len != 2) {
        std.log.warn("Usage: {s} <code>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const file = args[1];

    var source = try std.fs.cwd().openFile(file, .{});
    defer source.close();

    const data = try source.readToEndAllocOptions(allocator, 500 * MB, null, 4, 0);

    const errorManager = ErrorManager.init(allocator, data);
    ParserImport.errorManager = errorManager;

    var outputFile = std.mem.splitSequence(u8, file, ".c");
    var outputFileName = outputFile.next().?;
    outputFileName = try std.fmt.allocPrint(allocator, "{s}.s", .{outputFileName});

    try CodeGen.parse(data, outputFileName);
}
