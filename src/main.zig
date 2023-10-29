const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

const allocator = arena.allocator();

const print = std.debug.print;

const MAX_TOKENS = 10;

pub fn stringToInt(source: []const u8) !usize {
    return try std.fmt.parseInt(usize, source, 10);
}

pub const Kind = enum {
    // Operators
    Plus,
    Minus,
    Mul,
    Div,

    // Literals
    Number,

    // Punctuation
    LeftParen,
    RightParen,
};

pub const Token = struct {
    kind: Kind,

    start: usize,
    end: usize,

    pub fn new_token(
        kind: Kind,
        start: usize,
        end: usize,
    ) !Token {
        return .{
            .kind = kind,
            .start = start,
            .end = end,
        };
    }
};

pub const Tokenizer = struct {
    buffer: [:0]const u8 = undefined,
    index: usize = 0,
    tokens: std.ArrayList(Token),

    pub fn init(source: [:0]const u8) Tokenizer {
        return Tokenizer{
            .buffer = source,
            .tokens = std.ArrayList(Token).init(allocator),
        };
    }

    pub fn generate(self: *Tokenizer) !void {
        const buffer = self.buffer;

        if (self.index >= buffer.len) {
            @panic("empty buffer");
        }

        while (self.index < buffer.len) {
            const c = buffer[self.index];

            if (c == ' ') {
                self.index += 1;
                continue;
            }

            if (std.ascii.isDigit(c)) {
                const start = self.index;
                while (std.ascii.isDigit(buffer[self.index])) {
                    self.index += 1;

                    if (self.index - start > MAX_TOKENS) {
                        @panic("token too long");
                    }
                }

                try self.tokens.append(
                    try Token.new_token(
                        .Number,
                        start,
                        self.index,
                    ),
                );

                continue;
            }

            if (c == '+') {
                try self.tokens.append(
                    try Token.new_token(
                        .Plus,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '-') {
                try self.tokens.append(
                    try Token.new_token(
                        .Minus,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '*') {
                try self.tokens.append(
                    try Token.new_token(
                        .Mul,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '/') {
                try self.tokens.append(
                    try Token.new_token(
                        .Div,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '(') {
                try self.tokens.append(
                    try Token.new_token(
                        .LeftParen,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == ')') {
                try self.tokens.append(
                    try Token.new_token(
                        .RightParen,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }
        }
    }
};

pub const AstTree = struct {
    root: *Node,
};

pub const NodeKind = enum {
    ADD,
    SUB,
    MUL,
    DIV,

    NUM,

    NEG,

    INVALID,
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

    pub fn construct(source: [:0]const u8, tokens: []Token) !*Node {
        if (tokens.len == 0) {
            @panic("empty tokens");
        }

        // Check for a single number
        if (tokens.len == 1) {
            const token = tokens[0];

            if (token.kind != .Number) {
                @panic("expected number");
            }

            const value = try stringToInt(source[token.start..token.end]);

            return try Node.new_num(value);
        }

        var operand_stack = std.ArrayList(*Node).init(allocator);
        var operator_stack = std.ArrayList(Kind).init(allocator);

        var i: usize = 0;
        var index: usize = 0;

        while (index < tokens.len) : (index += 1) {
            const token = tokens[index];

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
                const node = try Node.construct(source, sliceToParse);

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

                        print("Token: {}\n", .{tokens[index]});
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
            }
        }

        while (operand_stack.items.len > 1 and operator_stack.items.len > 0) {
            const op = operator_stack.pop();
            const rhs = operand_stack.pop();
            const lhs = operand_stack.pop();

            const node = try new_binary(tok2node(op), lhs, rhs);
            try operand_stack.append(node);
        }

        const node = operand_stack.pop();
        return node;
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

// Code Generation

var depth: usize = 0;

fn push() void {
    print("  push %rax\n", .{});
    depth += 1;
}

fn pop(reg: []const u8) void {
    print("  pop {s}\n", .{reg});
    depth -= 1;
}

// Main
pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        print("Usage: {s} <code>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const source = args[1];

    try parse(source);
}

fn parse(source: [:0]const u8) !void {
    var tokenizer = Tokenizer.init(source);
    try tokenizer.tokens.ensureTotalCapacity(source.len);

    print("  .globl main\n", .{});
    print("main:\n", .{});

    try tokenizer.generate();

    const tokens = try tokenizer.tokens.toOwnedSlice();

    const node = try Node.construct(source, tokens);

    emit(node);

    print("  ret\n", .{});
    std.debug.assert(depth == 0);
}

fn emit(node: *Node) void {
    if (node.kind == .INVALID) {
        return;
    }

    if (node.kind == .NUM) {
        print("  mov ${d}, %rax\n", .{node.value});

        return;
    }

    if (node.kind == .NEG) {
        emit(node.ast.binary.rhs);
        print("  neg %rax\n", .{});

        return;
    }

    switch (node.ast) {
        .binary => {
            emit(node.ast.binary.rhs);
            push();
        },
        .invalid => {},
    }

    switch (node.ast) {
        .binary => {
            emit(node.ast.binary.lhs);
            pop("%rdi");
        },
        .invalid => {},
    }

    switch (node.kind) {
        .ADD => {
            print("  add %rdi, %rax\n", .{});
        },

        .SUB => {
            print("  sub %rdi, %rax\n", .{});
        },

        .MUL => {
            print("  imul %rdi, %rax\n", .{});
        },

        .DIV => {
            print("  cqo\n", .{});
            print("  idiv %rdi\n", .{});
        },

        .NEG => {
            print("  neg %rax\n", .{});
        },

        else => {
            @panic("uh oh");
        },
    }
}
