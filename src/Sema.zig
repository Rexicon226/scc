//! The Semantic Analyer of Sir

const std = @import("std");
const Allocator = std.mem.Allocator;

// Imports
const Sir = @import("Sir.zig");
const Parser = @import("Parser.zig");

const Payload = Sir.Instruction.Payload;

const Sema = @This();

allocator: Allocator,

// Should only contain `block` type instructions.
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
                    .payload = .{
                        .block = block_instructions.items,
                    },
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
            const resolved_result = try sema.allocator.create(Sir.Instruction);

            resolved_result.* = switch (node.ast.unary.op.kind) {
                .NUM => .{
                    .label = .num_lit,
                    .payload = blk: {
                        const payload: Sir.Instruction.Payload = .{
                            .ty_val = .{
                                .ty = .usize,
                                .val = 10,
                                // TODO: .val = node.value
                            },
                        };
                        break :blk payload;
                    },
                },

                else => std.debug.panic(
                    "TODO: {} resolveNode RETURN",
                    .{node.ast.unary.op.kind},
                ),
            };

            const result_inst = try sema.allocator.create(Sir.Instruction);

            result_inst.* = .{ .label = .ret, .payload = .{ .un_op = resolved_result } };

            return result_inst;
        },

        else => std.debug.panic("TODO: {} resolveNode", .{node.kind}),
    }
    unreachable;
}

// Debug Printing

const output = std.io.getStdOut();
const writer = output.writer();

pub fn print(sema: *Sema) noreturn {
    var cursor: u32 = 0;
    while (cursor < sema.instructions.len) : (cursor += 1) {
        const block = sema.instructions.toOwnedSlice().get(cursor);

        sema.printInst(block, 0) catch @panic("failed to print block");
    }

    std.os.exit(0);
}

fn printInst(
    sema: *Sema,
    inst: Sir.Instruction,
    ident: u32,
) !void {
    const indent_buffer = try sema.allocator.alloc(u8, ident);
    @memset(indent_buffer, ' ');

    switch (inst.label) {
        .block => {
            const blocks = inst.payload.block;

            for (blocks) |node| {
                try sema.printInst(node.*, ident + 2);
            }
        },
        .num_lit => {
            try writer.print("{d}", .{inst.payload.ty_val.val});
        },
        .ret => {
            try writer.print("ret(", .{});
            try sema.printInst(inst.payload.un_op.*, ident + 2);
            try writer.print(")\n", .{});
        },
        else => std.debug.panic("TODO: {} printInst", .{inst.label}),
    }
}
