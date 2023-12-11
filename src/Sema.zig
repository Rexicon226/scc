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

pub fn generate(sema: *Sema, body: []*Parser.Node) !void {
    for (body) |node| {
        switch (node.kind) {
            .BLOCK => {
                var block_instructions = std.ArrayList(*Sir.Instruction).init(sema.allocator);

                for (node.body) |sub_node| {
                    const resolved_inst = try sema.resolveNode(sub_node);
                    try block_instructions.append(resolved_inst);
                }

                const result_inst = try sema.allocator.create(Sir.Instruction);

                result_inst.* = .{
                    .label = .block,
                    .payload = Payload.new(.block, block_instructions.items),
                };

                try sema.instructions.append(sema.allocator, result_inst.*);
            },
            else => std.debug.panic("TODO: {} generate", .{node.kind}),
        }
    }
}

fn resolveNode(sema: *Sema, node: *Parser.Node) anyerror!*Sir.Instruction {
    switch (node.kind) {
        .RETURN => {
            const result_inst = try sema.allocator.create(Sir.Instruction);

            result_inst.* = switch (node.ast.unary.op.kind) {
                .NUM => .{
                    .label = .num_lit,
                    .payload = Payload.new(.no_op, void{}),
                },
                else => std.debug.panic(
                    "TODO: {} resolveNode RETURN",
                    .{node.ast.unary.op.kind},
                ),
            };

            return result_inst;
        },

        else => std.debug.panic("TODO: {} resolveNode", .{node.kind}),
    }
    unreachable;
}

pub fn print(sema: *Sema) noreturn {
    var cursor: u32 = 0;
    while (cursor < sema.instructions.len) : (cursor += 1) {
        const inst = sema.instructions.toOwnedSlice().get(cursor);
        _ = inst;

        // switch (inst.label) {
        //     .block =>
        // }
    }

    std.os.exit(0);
}
