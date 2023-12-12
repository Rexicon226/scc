//! The Semantic Analyer of Sir

const std = @import("std");
const tracer = @import("tracer");

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
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    for (body) |node| {
        switch (node.kind) {
            .BLOCK => {
                var block_instructions = std.ArrayListUnmanaged(Sir.Instruction){};

                for (node.body) |sub_node| {
                    const resolved_inst = try sema.resolveSet(sub_node);
                    try block_instructions.appendSlice(sema.allocator, resolved_inst);
                }

                try sema.instructions.append(
                    sema.allocator,
                    .{
                        .label = .block,
                        .payload = .{
                            .block = block_instructions.items,
                        },
                        .index = 0,
                    },
                );
            },
            else => std.debug.panic("TODO: {} generate", .{node.kind}),
        }
    }
}

fn resolveSet(sema: *Sema, node: *Parser.Node) ![]Sir.Instruction {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    switch (node.kind) {
        .RETURN => {
            const resolved_result = try sema.resolveNode(node.ast.unary.op);

            const result_inst = try sema.allocator.alloc(Sir.Instruction, 1);

            result_inst[0] = .{
                .label = .ret,
                .payload = .{ .un_op = resolved_result },
                .index = 0,
            };

            return result_inst;
        },

        .STATEMENT => {
            const resolved_inst = try sema.resolveSet(node.ast.unary.op);
            return resolved_inst;
        },

        .ASSIGN => {
            // Allocate the space for the assignment.
            const return_inst = try sema.allocator.alloc(Sir.Instruction, 2);

            return_inst[0] = .{
                .index = 0,
                .label = .alloc,
                .payload = .{
                    .val = 4,
                },
            };

            const load_rhs_inst = try sema.allocator.create(Sir.Instruction);

            load_rhs_inst.* = .{
                .index = 0,
                .label = .num_lit,
                .payload = .{
                    .val = node.ast.binary.rhs.value,
                },
            };

            return_inst[1] = Sir.Instruction{
                .index = 0,
                .label = .load,
                .payload = .{
                    .load_op = .{
                        .lhs = &return_inst[0],
                        .ty = .usize_val,
                        .rhs = load_rhs_inst,
                    },
                },
            };

            return return_inst;
        },

        else => std.debug.panic("TODO: {} resolveSet", .{node}),
    }

    unreachable;
}

fn resolveNode(sema: *Sema, node: *Parser.Node) !*Sir.Instruction {
    switch (node.kind) {
        .NUM => {
            const result_inst = try sema.allocator.create(Sir.Instruction);

            result_inst.* =
                .{
                .label = .num_lit,
                .payload = blk: {
                    const payload: Sir.Instruction.Payload = .{
                        .ty_val = .{
                            .ty = .usize_val,
                            .val = node.value,
                        },
                    };
                    break :blk payload;
                },
                .index = 0,
            };

            return result_inst;
        },
        else => std.debug.panic("TODO: {} resolveNode", .{node}),
    }
}

// Debug Printing
const output = std.io.getStdOut();
const writer = output.writer();

pub fn print(sema: *Sema) void {
    var cursor: u32 = 0;
    while (cursor < sema.instructions.len) : (cursor += 1) {
        var block = sema.instructions.toOwnedSlice().get(cursor);

        sema.printInst(&block, 0) catch @panic("failed to print block");
    }
}

fn printInst(
    sema: *Sema,
    inst: *Sir.Instruction,
    ident: u32,
) !void {
    const indent_buffer = try sema.allocator.alloc(u8, ident);
    @memset(indent_buffer, ' ');

    switch (inst.label) {
        .block => {
            const blocks = inst.payload.block;

            for (blocks) |*node| {
                try sema.printInst(node, ident + 2);
            }
        },
        .num_lit => {
            try writer.print("{d}", .{inst.payload.ty_val.val});
        },
        .ret => {
            try writer.print("${} = ", .{inst.index});
            try writer.print("ret(", .{});
            try sema.printInst(inst.payload.un_op, ident + 2);
            try writer.print(")\n", .{});
        },
        .alloc => {
            try writer.print("${} = ", .{inst.index});
            try writer.print("alloc({})\n", .{inst.payload.val});
        },
        .load => {
            const payload = inst.payload.load_op;
            try writer.print("load(${}, {}, {})\n", .{
                payload.lhs.index,
                payload.ty,
                payload.rhs.payload.val,
            });
        },
        else => try writer.print("TODO: {} printInst\n", .{inst.label}),
    }
}
