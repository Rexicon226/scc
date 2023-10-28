const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

const allocator = arena.allocator();

const print = std.debug.print;

const MAX_TOKENS = 10;

pub fn stringToInt(source: []const u8) usize {
    return std.fmt.parseInt(usize, source, 10) catch unreachable;
}

pub const Kind = enum {
    Plus,
    Minus,
    Mul,
    Div,
    Number,

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
    ND_ADD,
    ND_SUB,
    ND_MUL,
    ND_DIV,
    ND_NUM,
};

pub const Node = struct {
    kind: NodeKind,

    lhs: *Node,
    rhs: *Node,

    value: usize,

    pub fn new_node(kind: NodeKind) !*Node {
        const node = try allocator.create(Node);
        node.kind = kind;
        return node;
    }

    pub fn new_binary(kind: NodeKind, lhs: *Node, rhs: *Node) !*Node {
        const node = try allocator.create(Node);
        node.kind = kind;
        node.lhs = lhs;
        node.rhs = rhs;

        return node;
    }

    pub fn new_num(value: usize) !*Node {
        const node = try allocator.create(Node);
        node.kind = .ND_NUM;
        node.value = value;

        return node;
    }

    pub fn construct(source: [:0]const u8, tokens: []Token) !*Node {
        if (tokens.len == 0) {
            @panic("empty tokens");
        }

        // Check for a number
        if (tokens.len == 1) {
            const token = tokens[0];

            if (token.kind != .Number) {
                @panic("expected number");
            }

            const value = stringToInt(source[token.start..token.end]);

            return try Node.new_num(value);
        }

        var i: usize = 0;
        var node: *Node = try new_num(stringToInt(source[tokens[i].start..tokens[i].end]));
        i += 1;
        while (i < tokens.len) : (i += 1) {
            if (tokens[i].kind == .Number) {
                node = try new_binary(.ND_ADD, node, try new_num(stringToInt(source[tokens[i].start..tokens[i].end])));
                continue;
            }

            if (tokens[i].kind == .Plus) {
                node = try new_binary(.ND_ADD, node, try new_num(stringToInt(source[tokens[i + 1].start..tokens[i + 1].end])));
                i += 1;
                continue;
            }

            if (tokens[i].kind == .Minus) {
                node = try new_binary(.ND_SUB, node, try new_num(stringToInt(source[tokens[i + 1].start..tokens[i + 1].end])));
                i += 1;
                continue;
            }
        }

        return node;
    }
};

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
    if (node.kind == .ND_NUM) {
        print("  mov ${d}, %rax\n", .{node.value});
        return;
    }

    emit(node.lhs);
    push();
    emit(node.rhs);
    pop("%rdi");

    switch (node.kind) {
        .ND_ADD => {
            print("  add %rdi, %rax\n", .{});
        },

        .ND_SUB => {
            print("  sub %rdi, %rax\n", .{});
        },

        .ND_MUL => {},

        .ND_DIV => {},

        .ND_NUM => {
            @panic("uh oh");
        },
    }
}
