const std = @import("std");
const TokenImport = @import("token.zig");

const Token = TokenImport.Token;
const Kind = TokenImport.Kind;

pub var allocator: std.mem.Allocator = undefined;

pub fn stringToInt(source: []const u8) usize {
    return std.fmt.parseInt(usize, source, 10) catch {
        std.log.err("Failed to parse int: {s}\n", .{source});
        @panic("failed to parse int");
    };
}

pub const Parser = struct {
    source: [:0]const u8,
    tokens: []Token,
    index: usize,

    locals: std.ArrayList(*Object),

    pub fn init(source: [:0]const u8, tokens: []Token) Parser {
        return Parser{
            .source = source,
            .tokens = tokens,
            .index = 0,
            .locals = std.ArrayList(*Object).init(allocator),
        };
    }

    pub fn find_var(self: *Parser, tok: Token) ?*Object {
        for (self.locals.items) |local| {
            if (std.mem.eql(u8, local.name, self.source[tok.start..tok.end])) {
                return local;
            }
        }
        return null;
    }

    pub fn parse(self: *Parser) !*Function {
        var function = try allocator.create(Function);

        var statements = std.ArrayList(*Node).init(allocator);

        while (self.index < self.tokens.len) {
            const node = self.assign(self.tokens[self.index]);
            try statements.append(node);

            self.skip(.SemiColon);
        }

        function.body = statements.items;
        function.locals = self.locals.items;

        return function;
    }

    pub fn assign(self: *Parser, token: Token) *Node {
        var node = self.equality(token);

        if (self.tokens[self.index].kind == .Assign) {
            self.index += 1;
            node = Node.new_binary(.ASSIGN, node, self.assign(self.tokens[self.index]));
        }

        return node;
    }

    pub fn equality(self: *Parser, token: Token) *Node {
        var node = self.relational(token);

        while (true) {
            if (self.tokens[self.index].kind == .Eq) {
                self.index += 1;
                node = Node.new_binary(.EQ, node, self.relational(self.tokens[self.index]));
                continue;
            }

            if (self.tokens[self.index].kind == .Ne) {
                self.index += 1;
                node = Node.new_binary(.NE, node, self.relational(self.tokens[self.index]));
                continue;
            }

            return node;
        }
    }

    pub fn relational(self: *Parser, token: Token) *Node {
        var node = self.add(token);

        while (true) {
            if (self.tokens[self.index].kind == .Lt) {
                self.index += 1;
                node = Node.new_binary(.LT, node, self.add(self.tokens[self.index]));
                continue;
            }

            if (self.tokens[self.index].kind == .Le) {
                self.index += 1;
                node = Node.new_binary(.LE, node, self.add(self.tokens[self.index]));
                continue;
            }

            if (self.tokens[self.index].kind == .Gt) {
                self.index += 1;
                node = Node.new_binary(.GT, node, self.add(self.tokens[self.index]));
                continue;
            }

            if (self.tokens[self.index].kind == .Ge) {
                self.index += 1;
                node = Node.new_binary(.GE, node, self.add(self.tokens[self.index]));
                continue;
            }

            return node;
        }
    }

    pub fn add(self: *Parser, token: Token) *Node {
        var node = self.mul(token);

        while (true) {
            if (self.tokens[self.index].kind == .Plus) {
                self.index += 1;
                node = Node.new_binary(.ADD, node, self.mul(self.tokens[self.index]));
                continue;
            }

            if (self.tokens[self.index].kind == .Minus) {
                self.index += 1;
                node = Node.new_binary(.SUB, node, self.mul(self.tokens[self.index]));
                continue;
            }

            return node;
        }

        @panic("uh oh");
    }

    pub fn mul(self: *Parser, token: Token) *Node {
        var node = self.unary(token);

        while (true) {
            if (self.tokens[self.index].kind == .Mul) {
                self.index += 1;
                node = Node.new_binary(.MUL, node, self.unary(self.tokens[self.index]));
                continue;
            }

            if (self.tokens[self.index].kind == .Div) {
                self.index += 1;
                node = Node.new_binary(.DIV, node, self.unary(self.tokens[self.index]));
                continue;
            }

            return node;
        }

        @panic("uh oh");
    }

    pub fn unary(self: *Parser, token: Token) *Node {
        if (token.kind == .Plus) {
            self.index += 1;
            return self.primary(self.tokens[self.index]);
        }

        if (token.kind == .Minus) {
            self.index += 1;
            return Node.new_unary(.NEG, self.unary(self.tokens[self.index]));
        }

        return self.primary(token);
    }

    pub fn primary(self: *Parser, token: Token) *Node {
        if (token.kind == .LeftParen) {
            self.index += 1;
            const node = self.add(self.tokens[self.index]);
            self.skip(.RightParen);
            return node;
        }

        if (token.kind == .Variable) {
            var object = self.find_var(token);
            self.index += 1;
            if (object) |obj| {
                return Node.new_variable(obj);
            } else {
                const obj = Node.new_lvar(&self.locals, self.source[token.start..token.end]);
                return Node.new_variable(obj);
            }
        }

        if (token.kind == .Number) {
            const node = Node.new_num(stringToInt(self.source[token.start..token.end]));
            self.index += 1;
            return node;
        }

        std.log.err("Found: {}", .{token.kind});
        @panic("wrong usage of primary");
    }

    pub fn skip(self: *Parser, op: TokenImport.Kind) void {
        if (self.tokens[self.index].kind != op) {
            std.log.err("Found: {}", .{self.tokens[self.index].kind});
            @panic("SKIP: found wrong operator");
        }
        self.index += 1;
    }
};

pub const Node = struct {
    kind: NodeKind,
    ast: Ast,

    variable: *Object,
    value: usize,
    name: u8,

    pub fn new_node(kind: NodeKind) *Node {
        const node = allocator.create(Node) catch {
            @panic("failed to allocate node");
        };
        node.kind = kind;

        node.ast = .invalid;

        return node;
    }

    pub fn new_num(num: usize) *Node {
        const node = new_node(.NUM);
        node.value = num;

        node.ast = .invalid;

        return node;
    }

    pub fn new_binary(kind: NodeKind, lhs: *Node, rhs: *Node) *Node {
        const node = new_node(kind);

        node.ast = Ast.new(.binary, .{
            .lhs = lhs,
            .rhs = rhs,
        });

        return node;
    }

    pub fn new_unary(kind: NodeKind, lhs: *Node) *Node {
        const node = new_node(kind);

        node.ast = Ast.new(.binary, .{
            .lhs = lhs,
            .rhs = undefined,
        });

        return node;
    }

    pub fn new_variable(variable: *Object) *Node {
        const node = new_node(.VAR);
        node.variable = variable;

        node.ast = .invalid;

        return node;
    }

    pub fn new_lvar(locals: *std.ArrayList(*Object), name: []const u8) *Object {
        var object = allocator.create(Object) catch {
            @panic("failed to allocate object");
        };
        // TODO: I don't like this const cast.
        object.name = name;
        object.offset = 1;

        locals.append(object) catch {
            @panic("failed to append object");
        };

        return object;
    }
};

pub const NodeKind = enum {
    // Operators
    ADD,
    SUB,
    MUL,
    DIV,

    // Literals
    NUM,
    VAR,
    ASSIGN,

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

pub const Object = struct {
    name: []const u8,
    offset: isize, // Offset from RBP
};

pub const Function = struct {
    body: []*Node,
    locals: []*Object,
    stack_size: usize,
};
