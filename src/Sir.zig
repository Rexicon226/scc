//! Sir - Sub-par Intermediate Representation. A SSA IR.
//! parser.zig converts a stream of tokens into an AST tree,
//! which Sir.zig then converts into fully typed IR instructions.
//! Both error checking of the AST, and semantic analyses happens here.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Sir = @This();

instructions: std.MultiArrayList(Instruction).Slice,

pub const Instruction = struct {
    tag: Tag,

    pub const Tag = enum(u8) {
        add,
    };
};
