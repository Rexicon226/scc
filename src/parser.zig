const std = @import("std");
const TokenImport = @import("token.zig");

const Token = TokenImport.Token;
const Kind = TokenImport.Kind;

const ErrorManager = @import("error.zig").ErrorManager;
const ReportItem = @import("error.zig").ReportItem;

pub fn stringToInt(source: []const u8) usize {
    return std.fmt.parseInt(usize, source, 10) catch {
        std.log.err("Failed to parse int: {s}\n", .{source});
        std.os.exit(1);
    };
}

pub const Parser = struct {
    source: [:0]const u8,
    tokens: []Token,
    index: usize,

    locals: std.ArrayList(*Object),

    allocator: std.mem.Allocator,
    errorManager: ErrorManager,

    pub fn init(
        source: [:0]const u8,
        tokens: []Token,
        allocator: std.mem.Allocator,
    ) Parser {
        return Parser{
            .source = source,
            .tokens = tokens,
            .index = 0,
            .locals = std.ArrayList(*Object).init(allocator),
            .allocator = allocator,
            .errorManager = ErrorManager.init(allocator, source),
        };
    }

    pub fn find_var(self: *Parser, tok: Token) ?*Object {
        for (self.locals.items) |local| {
            if (std.mem.eql(
                u8,
                local.name,
                self.source[tok.start..tok.end],
            )) {
                return local;
            }
        }
        return null;
    }

    pub fn parse(self: *Parser) !*Function {
        var function = try self.allocator.create(Function);

        var statements = std.ArrayList(*Node).init(self.allocator);

        // Tokens
        // for (self.tokens) |token| {
        //     std.debug.print("Token: {}\n", .{token});
        // }

        while (self.index < self.tokens.len) {
            const node = self.statement(self.tokens[self.index]);
            try statements.append(node);
        }

        function.body = statements.items;
        function.locals = self.locals.items;

        return function;
    }

    fn print_current(self: *Parser) void {
        std.debug.print("Current: {}\n", .{self.tokens[self.index]});
    }

    pub fn statement(self: *Parser, token: Token) *Node {
        if (token.kind == .Return) {
            self.skip(.Return);
            const node = Node.new_unary(
                .RETURN,
                self.expression(
                    self.tokens[self.index],
                ),
                self.allocator,
            );
            self.skip(.SemiColon);
            return node;
        }

        if (token.kind == .If) {
            const node = Node.new_node(.IF, self.allocator);
            self.skip(.If);

            self.skip(.LeftParen);
            node.cond = self.expression(self.tokens[self.index]);
            self.skip(.RightParen);
            node.then = self.statement(self.tokens[self.index]);
            if (self.tokens[self.index].kind == .Else) {
                self.skip(.Else);
                node.els = self.statement(self.tokens[self.index]);
                node.hasElse = true;
            }
            return node;
        }

        if (token.kind == .For) {
            const node = Node.new_node(
                .FOR,
                self.allocator,
            );
            self.skip(.For);
            self.skip(.LeftParen);

            node.init = self.expr_stmt(self.tokens[self.index]);

            if (!(self.tokens[self.index].kind == .SemiColon)) {
                node.cond = self.expression(self.tokens[self.index]);
                node.hasCond = true;
            }
            self.skip(.SemiColon);

            if (!(self.tokens[self.index].kind == .RightParen)) {
                node.inc = self.expression(self.tokens[self.index]);
                node.hasInc = true;
            }
            self.skip(.RightParen);

            node.then = self.statement(self.tokens[self.index]);
            return node;
        }

        if (token.kind == .While) {
            const node = Node.new_node(
                .FOR,
                self.allocator,
            );
            self.skip(.While);
            self.skip(.LeftParen);

            node.cond = self.expression(self.tokens[self.index]);
            node.hasCond = true;

            self.skip(.RightParen);

            node.then = self.statement(self.tokens[self.index]);
            return node;
        }

        if (token.kind == .LeftBracket) {
            self.skip(.LeftBracket);
            const node = self.compound_statement();
            self.skip(.RightBracket);
            return node;
        }

        return self.expression(token);
    }

    pub fn compound_statement(self: *Parser) *Node {
        var body = std.ArrayListUnmanaged(*Node){};

        while (self.tokens[self.index].kind != .RightBracket) {
            const node = self.statement(self.tokens[self.index]);

            body.append(self.allocator, node) catch {
                @panic("failed to append node");
            };

            if (self.index >= self.tokens.len) {
                const token = self.tokens[self.index - 1];
                var reports = std.ArrayList(ReportItem).init(self.allocator);

                reports.append(ReportItem{
                    .kind = .warning,
                    .location = self.tokens[self.index - 1].line,
                    .message = "no bracket at end of file",
                }) catch @panic("failed to allocate report");

                self.errorManager.panic(
                    .no_end,
                    &reports.items,
                    self.source[token.line.start..token.line.end],
                );
            }
        }

        const node = Node.new_node(
            .BLOCK,
            self.allocator,
        );
        node.body = body.items;
        return node;
    }

    pub fn expression(self: *Parser, token: Token) *Node {
        if (token.kind == .SemiColon) {
            self.skip(.SemiColon);
            return Node.new_node(
                .STATEMENT,
                self.allocator,
            );
        }

        return self.assign(token);
    }

    pub fn expr_stmt(self: *Parser, token: Token) *Node {
        if (token.kind == .SemiColon) {
            self.skip(.SemiColon);
            return Node.new_node(
                .STATEMENT,
                self.allocator,
            );
        }

        const node = self.assign(token);
        self.skip(.SemiColon);
        return node;
    }

    pub fn assign(self: *Parser, token: Token) *Node {
        var node = self.equality(token);

        if (self.tokens[self.index].kind == .Assign) {
            self.skip(.Assign);
            node = Node.new_binary(
                .ASSIGN,
                node,
                self.assign(self.tokens[self.index]),
                self.allocator,
            );
        }

        return node;
    }

    pub fn equality(self: *Parser, token: Token) *Node {
        var node = self.relational(token);

        while (true) {
            if (self.tokens[self.index].kind == .Eq) {
                self.skip(.Eq);
                node = Node.new_binary(
                    .EQ,
                    node,
                    self.relational(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            if (self.tokens[self.index].kind == .Ne) {
                self.skip(.Ne);
                node = Node.new_binary(
                    .NE,
                    node,
                    self.relational(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            return node;
        }
    }

    pub fn relational(self: *Parser, token: Token) *Node {
        var node = self.add(token);

        while (true) {
            if (self.tokens[self.index].kind == .Lt) {
                self.skip(.Lt);
                node = Node.new_binary(
                    .LT,
                    node,
                    self.add(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            if (self.tokens[self.index].kind == .Le) {
                self.skip(.Le);
                node = Node.new_binary(
                    .LE,
                    node,
                    self.add(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            if (self.tokens[self.index].kind == .Gt) {
                self.skip(.Gt);
                node = Node.new_binary(
                    .GT,
                    node,
                    self.add(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            if (self.tokens[self.index].kind == .Ge) {
                self.skip(.Ge);
                node = Node.new_binary(
                    .GE,
                    node,
                    self.add(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            return node;
        }
    }

    pub fn add(self: *Parser, token: Token) *Node {
        var node = self.mul(token);

        while (true) {
            if (self.tokens[self.index].kind == .Plus) {
                self.skip(.Plus);
                node = Node.new_binary(
                    .ADD,
                    node,
                    self.mul(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            if (self.tokens[self.index].kind == .Minus) {
                self.skip(.Minus);
                node = Node.new_binary(
                    .SUB,
                    node,
                    self.mul(self.tokens[self.index]),
                    self.allocator,
                );
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
                self.skip(.Mul);
                node = Node.new_binary(
                    .MUL,
                    node,
                    self.unary(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            if (self.tokens[self.index].kind == .Div) {
                self.skip(.Div);
                node = Node.new_binary(
                    .DIV,
                    node,
                    self.unary(self.tokens[self.index]),
                    self.allocator,
                );
                continue;
            }

            return node;
        }

        @panic("uh oh");
    }

    pub fn unary(self: *Parser, token: Token) *Node {
        if (token.kind == .Plus) {
            self.skip(.Plus);
            return self.unary(self.tokens[self.index]);
        }

        if (token.kind == .Minus) {
            self.skip(.Minus);
            return Node.new_unary(
                .NEG,
                self.unary(self.tokens[self.index]),
                self.allocator,
            );
        }

        // Pointers
        if (token.kind == .Address) {
            self.skip(.Address);
            return Node.new_unary(
                .ADDR,
                self.unary(self.tokens[self.index]),
                self.allocator,
            );
        }

        if (token.kind == .Mul) {
            self.skip(.Mul);
            return Node.new_unary(
                .DEREF,
                self.unary(self.tokens[self.index]),
                self.allocator,
            );
        }

        return self.primary(token);
    }

    pub fn primary(self: *Parser, token: Token) *Node {
        if (token.kind == .LeftParen) {
            self.skip(.LeftParen);
            const node = self.add(self.tokens[self.index]);
            self.skip(.RightParen);
            return node;
        }

        if (token.kind == .Variable) {
            var object = self.find_var(token);
            self.skip(.Variable);

            if (object) |obj| {
                return Node.new_variable(
                    obj,
                    self.allocator,
                );
            } else {
                const obj = Node.new_lvar(
                    &self.locals,
                    self.source[token.start..token.end],
                    self.allocator,
                );
                return Node.new_variable(
                    obj,
                    self.allocator,
                );
            }
        }

        if (token.kind == .Number) {
            const node = Node.new_num(
                stringToInt(self.source[token.start..token.end]),
                self.allocator,
            );
            self.skip(.Number);
            return node;
        }

        std.log.err("Found: {}", .{token.kind});

        var reports = std.ArrayList(ReportItem).init(self.allocator);

        reports.append(ReportItem{
            .kind = .@"error",
            .location = token.line,
            .message = std.fmt.allocPrint(self.allocator, "Found a {}", .{token.kind}) catch @panic("failed to allocate report print"),
        }) catch @panic("failed to allocate report");

        self.errorManager.panic(
            .missing_token,
            &reports.items,
            self.source[token.line.start..token.line.end],
        );
    }

    pub fn skip(self: *Parser, op: TokenImport.Kind) void {
        const token = self.tokens[self.index];
        if (token.kind != op) {
            var reports = std.ArrayList(ReportItem).init(self.allocator);

            reports.append(ReportItem{
                .kind = .@"error",
                .location = token.line,
                .message = std.fmt.allocPrint(self.allocator, "should be a {}", .{op}) catch @panic("failed to allocate report print"),
            }) catch @panic("failed to allocate report");

            reports.append(ReportItem{
                .kind = .warning,
                .location = self.tokens[self.index - 1].line,
                .message = std.fmt.allocPrint(self.allocator, "expects a {} after it", .{op}) catch @panic("failed to allocate report print"),
            }) catch @panic("failed to allocate report");

            self.errorManager.panic(
                .missing_token,
                &reports.items,
                self.source[token.line.start..token.line.end],
            );
        }
        self.index += 1;
    }
};

pub const Node = struct {
    kind: NodeKind,
    ast: Ast,

    body: []*Node,

    variable: *Object,
    value: usize,
    name: u8,

    // if
    cond: *Node,
    then: *Node,
    els: *Node,
    hasElse: bool = false,
    hasCond: bool = false,

    // for
    init: *Node,
    hasInit: bool = false,
    inc: *Node,
    hasInc: bool = false,

    pub fn new_node(
        kind: NodeKind,
        allocator: std.mem.Allocator,
    ) *Node {
        const node = allocator.create(Node) catch {
            @panic("failed to allocate node {}" ++ @typeName(@TypeOf(kind)));
        };
        node.kind = kind;

        node.ast = .invalid;

        return node;
    }

    pub fn new_num(
        num: usize,
        allocator: std.mem.Allocator,
    ) *Node {
        const node = new_node(.NUM, allocator);
        node.value = num;

        node.ast = .invalid;

        return node;
    }

    pub fn new_binary(
        kind: NodeKind,
        lhs: *Node,
        rhs: *Node,
        allocator: std.mem.Allocator,
    ) *Node {
        const node = new_node(kind, allocator);

        node.ast = Ast.new(.binary, .{
            .lhs = lhs,
            .rhs = rhs,
        });

        return node;
    }

    /// Will not eat the semicolon
    pub fn new_unary(
        kind: NodeKind,
        lhs: *Node,
        allocator: std.mem.Allocator,
    ) *Node {
        const node = new_node(kind, allocator);

        node.ast = Ast.new(.binary, .{
            .lhs = lhs,
            .rhs = undefined,
        });

        return node;
    }

    pub fn new_variable(
        variable: *Object,
        allocator: std.mem.Allocator,
    ) *Node {
        const node = new_node(.VAR, allocator);
        node.variable = variable;

        node.ast = .invalid;

        return node;
    }

    pub fn new_lvar(
        locals: *std.ArrayList(*Object),
        name: []const u8,
        allocator: std.mem.Allocator,
    ) *Object {
        var object = allocator.create(Object) catch {
            @panic("failed to allocate object");
        };

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

    // Pointer
    DEREF,
    ADDR,

    // Keywords
    RETURN,
    IF,
    FOR,
    WHILE,

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
    BLOCK,
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
