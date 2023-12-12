//! Sir - Sub-par Intermediate Representation.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Sir = @This();

pub const Instruction = struct {
    label: Label,
    payload: Payload,
    index: u32,

    pub const Label = enum {
        /// `return`
        ret,

        // Math
        add,

        /// number literal
        num_lit,

        /// A block of instructions.
        block,

        /// Allocates its payload and referring this instruction later
        /// is the same as referencing the pointer of the payload.
        alloc,

        /// Loads a payload into a pointer.
        ///
        /// `load(index, type, value)
        load,

        /// A statement
        statement,

        /// A reference to another instruction
        ///
        /// ```
        /// $0 = alloc(4)
        /// ret($0)
        /// ```
        ///
        /// the `$0` inside of the `ret` is a label of `instruction`
        ///
        /// the point is to not mix up `num_lit` and instruction indices
        instruction,
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

        // TODO: I don't know if I like having a triple_op
        // maybe limit it to 2 children max.
        load_op: struct {
            lhs: *Instruction,
            ty: Type,
            rhs: *Instruction,
        },

        /// Custom block data
        block: []Instruction,

        /// Variables with both a type and a value.
        ty_val: struct {
            ty: Type,
            val: usize,
        },

        /// Just a simple usize payload.
        val: usize,

        ty: Type,
    };

    /// Primatives
    pub const Type = enum(u8) {
        u64_ty,

        pub fn format(
            self: Type,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            std.debug.assert(fmt.len == 0);
            _ = options;

            switch (self) {
                .u64_ty => try writer.print("u64", .{}),
            }
        }

        /// Returns the byte footprint of the Type
        pub fn sizeOf(self: Type) u32 {
            return switch (self) {
                .u64_ty => 4,
            };
        }
    };
};
