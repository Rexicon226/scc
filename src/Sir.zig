//! Sir - Sub-par Intermediate Representation.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Sir = @This();

pub const Instruction = struct {
    label: Label,
    payload: Payload,

    pub const Label = enum {
        /// `return`
        ret,

        /// `+`
        add,

        /// `-`
        sub,

        /// `/`
        div,

        /// `*`
        mul,

        /// `=`
        cmp_eq,

        /// number literal
        num_lit,

        /// A block of instructions.
        block,
    };

    pub const Payload = union(enum) {
        /// no-op contains, by defintion, not instructions.
        no_op: void,

        /// Unary operator contains a single instruction.
        ///
        /// i.e `return 10`, `return` contains the payload `10`
        un_op: *Instruction,

        /// Binary operator contains two instructions.
        ///
        /// i.e `10 + 20`, `add` contains the payload `10, 20`
        bin_op: struct {
            lhs: *Instruction,
            rhs: *Instruction,
        },

        /// Custom block data
        block: []*Instruction,

        /// Variables with both a type and a value.
        ty_val: struct {
            ty: Type,
            val: usize,
        },
    };

    /// General type delcs for all possible variables
    pub const Type = enum {
        usize,
    };
};
