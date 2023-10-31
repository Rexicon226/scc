const std = @import("std");
const ParserImport = @import("parser.zig");
const CodeGen = @import("codegen.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const allocator = arena.allocator();

const print = std.debug.print;

// Main
pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    ParserImport.allocator = allocator;
    CodeGen.allocator = allocator;

    if (args.len != 2) {
        print("Usage: {s} <code>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const file = args[1];
    // var source = try std.fs.cwd().openFile(file, .{});
    // defer source.close();

    // const data = try source.readToEndAlloc(allocator, 500);

    // try CodeGen.parse("{ i=0; j=0; for (i=0; i<=10; i=i+1) j=i+j; return j; }");
    try CodeGen.parse(file);
}
