const std = @import("std");
const TokenImport = @import("token.zig");

const Token = TokenImport.Token;
const Kind = TokenImport.Kind;

pub var allocator: std.mem.Allocator = undefined;

pub fn stringToInt(source: []const u8) !usize {
    return try std.fmt.parseInt(usize, source, 10);
}

pub const Parser = struct {
    source: [:0]const u8,
    tokens: []Token,
    index: usize,

    pub fn init(source: [:0]const u8, tokens: []Token) Parser {
        return Parser{
            .source = source,
            .tokens = tokens,
            .index = 0,
        };
    }

    pub fn parse(self: *Parser) ![]*Node {
        // List of statement nodes.
        var statements = std.ArrayList(*Node).init(allocator);

        var tokensEaten: usize = 0;
        // -1 for the last SemiColon
        while (tokensEaten < self.tokens.len - 1) {
            self.index = 0;
            const node = try Node.construct(
                &self.index,
                self.source,
                self.tokens[tokensEaten..self.tokens.len],
                null,
            );
            tokensEaten += self.index;

            try statements.append(node);
        }

        return statements.items;
    }
};

pub const AstTree = struct {
    root: *Node,
};

pub const NodeKind = enum {
    // Operators
    ADD,
    SUB,
    MUL,
    DIV,

    // Literals
    NUM,

    NEG,

    // Equality
    EQ,
    NE,
    LT,
    LE,
    GT,
    GE,

    // Extra
    INVALID,
    STATEMENT,
};

fn tok2node(kind: Kind) NodeKind {
    switch (kind) {
        .Plus => return .ADD,
        .Minus => return .SUB,
        .Mul => return .MUL,
        .Div => return .DIV,
        else => @panic("invalid token"),
    }
}

fn node2tok(kind: NodeKind) Kind {
    switch (kind) {
        .ADD => return .Plus,
        .SUB => return .Minus,
        .MUL => return .Mul,
        .DIV => return .Div,
        else => @panic("invalid node"),
    }
}

pub const Ast = union(enum) {
    binary: struct {
        lhs: *Node,
        rhs: *Node,
    },
    invalid,

    pub inline fn new(comptime k: std.meta.Tag(@This()), init: anytype) @This() {
        return @unionInit(@This(), @tagName(k), init);
    }
};

pub const Node = struct {
    kind: NodeKind,

    ast: Ast,

    value: usize,

    pub fn new_node(kind: NodeKind) !*Node {
        const node = try allocator.create(Node);
        node.kind = kind;
        return node;
    }

    pub fn new_statement(current: *Node, lhs: *Node) !*Node {
        const empty = try allocator.create(Node);

        current.ast = Ast.new(.binary, .{
            .lhs = lhs,
            .rhs = empty, // To be the next statement.
        });

        return current;
    }

    pub fn new_binary(kind: NodeKind, lhs: *Node, rhs: *Node) !*Node {
        const node = try allocator.create(Node);
        node.kind = kind;

        node.ast = Ast.new(.binary, .{
            .lhs = lhs,
            .rhs = rhs,
        });

        return node;
    }

    pub fn new_num(value: usize) !*Node {
        const node = try allocator.create(Node);
        node.kind = .NUM;
        node.value = value;

        node.ast = .invalid;

        return node;
    }

    pub fn new_negative(rhs: *Node) !*Node {
        if (rhs.kind != .NUM) {
            @panic("expected number");
        }

        const node = try allocator.create(Node);
        const empty = try allocator.create(Node);
        empty.kind = .INVALID;
        node.kind = .NEG;

        node.ast = Ast.new(.binary, .{
            .lhs = empty,
            .rhs = rhs,
        });

        return node;
    }

    // Used for 'double negative'.
    // RHS is expected to be filled later.
    pub fn empty_negative() !*Node {
        const node = try allocator.create(Node);
        const empty = try allocator.create(Node);
        node.kind = .NEG;

        node.ast = Ast.new(.binary, .{
            .lhs = empty,
            .rhs = empty,
        });

        return node;
    }

    pub const ConstructOptions = struct {
        requireSemiColon: bool = true,
    };

    pub fn construct(
        index_: *usize,
        source: [:0]const u8,
        tokens: []Token,
        options_: ?ConstructOptions,
    ) !*Node {
        var options = ConstructOptions{};
        if (options_) |op| {
            options = op;
        }

        var index = index_.*;
        if (tokens.len == 0) {
            @panic("empty tokens");
        }

        // Check for a single number
        if (tokens.len == 1) {
            if (options.requireSemiColon) {
                @panic("no semicolon found");
            }
        }

        var operand_stack = std.ArrayList(*Node).init(allocator);
        var operator_stack = std.ArrayList(Kind).init(allocator);

        var i: usize = 0;

        while (index < tokens.len) : (index += 1) {
            const token = tokens[index];
            // If a SemiColon is found, the expression is over
            // Wrap everything up, and return it.
            if (token.kind == .SemiColon) {
                while (operand_stack.items.len > 1 and operator_stack.items.len > 0) {
                    const op = operator_stack.pop();
                    const rhs = operand_stack.pop();
                    const lhs = operand_stack.pop();

                    const node = try new_binary(tok2node(op), lhs, rhs);
                    try operand_stack.append(node);
                }

                index_.* = index + 1;

                const node = operand_stack.pop();
                return node;
            }

            if (token.kind == .Number) {
                const value = try stringToInt(source[token.start..token.end]);
                const node = try Node.new_num(value);
                try operand_stack.append(node);
            } else if (token.kind == .LeftParen) {
                i = 0;

                // Go until we find the matching right paren
                while (i < tokens.len) {
                    if (tokens[index + i].kind == .RightParen) {
                        break;
                    }

                    if (i == tokens.len) {
                        @panic("unmatched paren");
                    }

                    i += 1;
                }

                const sliceToParse = tokens[index + 1 .. index + i];

                // Artificially add a semicolon to the end of the slice

                const node = try Node.construct(index_, source, sliceToParse, .{
                    .requireSemiColon = false,
                });

                try operand_stack.append(node);
                index += i;
            } else if (token.kind == .Plus or token.kind == .Minus) {

                // Plus
                if (token.kind == .Plus) {
                    // If the token befoer the plus is a operator, this can be ignored
                    if (index > 0 and tokens[index - 1].kind != .Number) {
                        // try operator_stack.append(token.kind);
                        index += 1;
                        continue;
                    }

                    // If the token before the plus is a number, this is an addition
                    while (operator_stack.items.len > 1 and hasHigherPrecedence(operator_stack.items[operator_stack.items.len - 1], token.kind)) {
                        const op = operator_stack.pop();

                        const rhs = operand_stack.pop();
                        const lhs = operand_stack.pop();
                        const node = try Node.new_binary(tok2node(op), lhs, rhs);
                        try operand_stack.append(node);
                    }
                    try operator_stack.append(token.kind);
                }

                // Print the token

                // Check if there is a number before the minus, this is a subtraction
                if (index > 0 and tokens[index - 1].kind == .Number) {
                    while (operator_stack.items.len > 0 and hasHigherPrecedence(operator_stack.items[operator_stack.items.len - 1], token.kind)) {
                        const op = operator_stack.pop();

                        const rhs = operand_stack.pop();
                        const lhs = operand_stack.pop();
                        const node = try Node.new_binary(tok2node(op), lhs, rhs);
                        try operand_stack.append(node);
                    }
                    try operator_stack.append(token.kind);
                    continue;
                }

                if (token.kind == .Minus) {
                    const value = stringToInt(source[tokens[index + 1].start..tokens[index + 1].end]) catch {
                        // Check if an empty negative is on the stack
                        if (!(operand_stack.items.len > 0 and operand_stack.items[operand_stack.items.len - 1].kind == .NEG)) {
                            const node = try empty_negative();
                            try operand_stack.append(node);
                            continue;
                        }

                        // Now there is a empty negative on the stack.
                        // There can be up to 3 "signs" in a row, before the value.
                        // Then it's a panic.

                        // Check if the next token is a + or -
                        if (tokens[index + 1].kind == .Plus or tokens[index + 1].kind == .Minus) {
                            // Check if the next token is a number
                            if (tokens[index + 2].kind == .Number) {
                                const value = stringToInt(source[tokens[index + 2].start..tokens[index + 2].end]) catch {
                                    @panic("invalid expression");
                                };

                                const node = try new_negative(try new_num(value));

                                // Check if there already is a empty negative on the stack
                                if (operand_stack.items.len > 0 and operand_stack.items[operand_stack.items.len - 1].kind == .NEG) {
                                    const lhs = operand_stack.pop();
                                    lhs.ast.binary.rhs = node;
                                    try operand_stack.append(lhs);
                                    index += 2;
                                    continue;
                                }

                                try operand_stack.append(node);
                                index += 3;
                                continue;
                            }
                        }

                        std.debug.print("Token: {}\n", .{tokens[index]});
                        @panic("invalid expression");
                    };

                    const node = try new_negative(try new_num(value));

                    // Check if there already is a empty negative on the stack
                    if (operand_stack.items.len > 0 and operand_stack.items[operand_stack.items.len - 1].kind == .NEG) {
                        const lhs = operand_stack.pop();
                        lhs.ast.binary.rhs = node;
                        try operand_stack.append(lhs);
                        index += 1;
                        continue;
                    }

                    try operand_stack.append(node);
                    index += 1;
                    continue;
                }
            } else if (token.kind == .Mul or token.kind == .Div) {
                while (operator_stack.items.len > 0 and hasHigherPrecedence(operator_stack.items[operator_stack.items.len - 1], token.kind)) {
                    const op = operator_stack.pop();

                    const rhs = operand_stack.pop();
                    const lhs = operand_stack.pop();
                    const node = try Node.new_binary(tok2node(op), lhs, rhs);
                    try operand_stack.append(node);
                }
                try operator_stack.append(token.kind);
            } else if (token.kind == .Eq) {
                // Get both sides
                const lhs = operand_stack.pop();

                // Construct the rhs node
                const rhs = try Node.construct(index_, source, tokens[index + 1 .. tokens.len], null);

                const node = try Node.new_binary(.EQ, lhs, rhs);
                try operand_stack.append(node);
                index += 1;
                continue;
            } else if (token.kind == .Ne) {
                // Get both sides
                const lhs = operand_stack.pop();

                // Construct the rhs node
                const rhs = try Node.construct(index_, source, tokens[index + 1 .. tokens.len], null);

                const node = try Node.new_binary(.NE, lhs, rhs);
                try operand_stack.append(node);
                index += 1;
                continue;
            } else if (token.kind == .Lt) {
                // Get both sides
                const lhs = operand_stack.pop();

                // Construct the rhs node
                const rhs = try Node.construct(index_, source, tokens[index + 1 .. tokens.len], null);

                const node = try Node.new_binary(.LT, lhs, rhs);
                try operand_stack.append(node);
                index += 1;
                continue;
            } else if (token.kind == .Le) {
                // Get both sides
                const lhs = operand_stack.pop();

                // Construct the rhs node
                const rhs = try Node.construct(index_, source, tokens[index + 1 .. tokens.len], null);

                const node = try Node.new_binary(.LE, lhs, rhs);
                try operand_stack.append(node);
                index += 1;
                continue;
            } else if (token.kind == .Gt) {
                // Get both sides
                const lhs = operand_stack.pop();

                // Construct the rhs node
                const rhs = try Node.construct(index_, source, tokens[index + 1 .. tokens.len], null);

                const node = try Node.new_binary(.GT, lhs, rhs);
                try operand_stack.append(node);
                index += 1;
                continue;
            } else if (token.kind == .Ge) {
                // Get both sides
                const lhs = operand_stack.pop();

                // Construct the rhs node
                const rhs = try Node.construct(index_, source, tokens[index + 1 .. tokens.len], null);

                const node = try Node.new_binary(.GE, lhs, rhs);
                try operand_stack.append(node);
                index += 1;
                continue;
            } else {
                @panic("invalid token");
            }
        }

        if (options.requireSemiColon) {
            @panic("no semicolon found");
        } else {
            while (operand_stack.items.len > 1 and operator_stack.items.len > 0) {
                const op = operator_stack.pop();
                const rhs = operand_stack.pop();
                const lhs = operand_stack.pop();

                const node = try new_binary(tok2node(op), lhs, rhs);
                try operand_stack.append(node);
            }

            index_.* = index + 1;

            const node = operand_stack.pop();
            return node;
        }
    }
};

fn hasHigherPrecedence(op1: Kind, op2: Kind) bool {
    return precedence(op1) > precedence(op2);
}

fn precedence(kind: Kind) u8 {
    switch (kind) {
        .Plus, .Minus => return 1,
        .Mul, .Div => return 2,
        else => @panic("invalid token"),
    }
}
