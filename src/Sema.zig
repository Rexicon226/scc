//! The Semantic Analyer of Sir

const std = @import("std");
const Allocator = std.mem.Allocator;

// Imports
const Sir = @import("Sir.zig");
const Parser = @import("Parser.zig");

const Payload = Sir.Instruction.Payload;

const Sema = @This();

allocator: Allocator,

instructions: std.MultiArrayList(Sir.Instruction),

pub fn init(alloc: Allocator) !Sema {
    return .{
        .allocator = alloc,
        .instructions = std.MultiArrayList(Sir.Instruction){},
    };
}

pub fn generate(self: *Sema, body: []*Parser.Node) !void {
    _ = body;

    try self.instructions.append(self.allocator, .{
        .label = .ret,
        .payload = Payload.new(.no_op, void{}),
    });
}

pub fn print(self: *Sema) noreturn {
    std.debug.print("Instructions:\n", .{});
    for (self.instructions.toOwnedSlice().items(.label)) |label| {
        std.debug.print("  {}\n", .{label});
    }

    std.os.exit(0);
}
