// A visually pleasing AST printer.

const std = @import("std");
const Parser = @import("../parser.zig");

const Node = @import("../parser.zig").Node;

const stdout = std.io.getStdOut().writer();

// Almost static
pub const Printer = struct {
    /// The allocator used to allocate memory for the printer.
    allocator: std.mem.Allocator,

    const spaces_per_indent = 4;

    pub fn init(allocator: std.mem.Allocator) Printer {
        return .{
            .allocator = allocator,
        };
    }

    pub fn print(self: *Printer, nodes: []*Node) !void {
        std.debug.print("\n", .{});

        for (nodes) |node| {
            try self.print_node(node, 0);
        }
    }

    fn print_node(self: *Printer, node: *Node, indent: u32) !void {
        const node_kind = node.kind;
        const node_name = @tagName(node_kind);

        const index_string = try self.allocator.alloc(u8, indent);
        @memset(index_string, ' ');

        switch (node_kind) {
            // Special
            .BLOCK => {
                try stdout.print("{s}{s}\n", .{ index_string, node_name });

                for (node.body) |statement| {
                    try self.print_node(statement, indent + spaces_per_indent);
                }

                return;
            },

            .RETURN => {
                try stdout.print("{s}{s}\n", .{ index_string, node_name });
                try self.print_node(node.ast.binary.lhs, indent + spaces_per_indent);
                return;
            },

            .ASSIGN => {
                try stdout.print("{s}{s}\n", .{ index_string, node_name });
                try self.print_node(node.ast.binary.lhs, indent + spaces_per_indent);
                try self.print_node(node.ast.binary.rhs, indent + spaces_per_indent);
                return;
            },

            .STATEMENT => {
                switch (node.ast) {
                    .binary => |b| {
                        try stdout.print("{s}{s}\n", .{ index_string, node_name });
                        try self.print_node(b.lhs, indent + spaces_per_indent);
                        try self.print_node(b.rhs, indent + spaces_per_indent);
                    },
                    else => {},
                }
                return;
            },

            // Literals

            .NUM => {
                try stdout.print("{s}{s} {d}\n", .{ index_string, node_name, node.value });
                return;
            },

            // Variables

            .VAR => {
                try stdout.print("{s}{s} {s}\n", .{ index_string, node_name, node.variable.name });
                return;
            },

            // Operations
            .ADD, .SUB, .MUL, .DIV => {
                try stdout.print("{s}{s}\n", .{ index_string, node_name });
                try self.print_node(node.ast.binary.lhs, indent + spaces_per_indent);
                try self.print_node(node.ast.binary.rhs, indent + spaces_per_indent);
                return;
            },

            .NEG => {
                try stdout.print("{s}{s}\n", .{ index_string, node_name });
                try self.print_node(node.ast.binary.rhs, indent + spaces_per_indent);
                return;
            },

            // Equality
            .EQ, .NE, .LT, .LE, .GT, .GE => {
                try stdout.print("{s}{s}\n", .{ index_string, node_name });
                try self.print_node(node.ast.binary.lhs, indent + spaces_per_indent);
                try self.print_node(node.ast.binary.rhs, indent + spaces_per_indent);
                return;
            },

            else => std.log.warn("undocumented node kind: {s}", .{node_name}),
        }
    }
};
