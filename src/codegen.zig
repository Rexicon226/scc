const std = @import("std");
const TokenImport = @import("token.zig");
const ParserImport = @import("parser.zig");

const Token = TokenImport.Token;
const Kind = TokenImport.Kind;

const Node = ParserImport.Node;
const Function = ParserImport.Function;

pub var allocator: std.mem.Allocator = undefined;

const print = std.debug.print;

pub fn parse(source: [:0]const u8) !void {
    var tokenizer = TokenImport.Tokenizer.init(source, allocator);
    try tokenizer.tokens.ensureTotalCapacity(source.len);

    try tokenizer.generate();

    const tokens = try tokenizer.tokens.toOwnedSlice();

    var parser = ParserImport.Parser.init(source, tokens);
    const function = try parser.parse();

    assign_lvar_offsets(function);

    print("  .globl main\n", .{});
    print("main:\n", .{});

    print("  push %rbp\n", .{});
    print("  mov %rsp, %rbp\n", .{});
    print("  sub ${d}, %rsp\n", .{function.stack_size});

    for (function.body) |node| {
        emit(node);
    }

    print(".L.return:\n", .{});
    print("  mov %rbp, %rsp\n", .{});
    print("  pop %rbp\n", .{});
    print("  ret\n", .{});
    std.debug.assert(depth == 0);
}

var depth: usize = 0;

fn push() void {
    print("  push %rax\n", .{});
    depth += 1;
}

fn pop(reg: []const u8) void {
    print("  pop {s}\n", .{reg});
    depth -= 1;
}

fn gen_addr(node: *Node) void {
    if (node.kind == .VAR) {
        print("  lea {d}(%rbp), %rax\n", .{node.variable.offset});
        return;
    }

    std.log.err("found: {}\n", .{node});
    @panic("not an lvalue");
}

fn align_to(n: usize, al: usize) usize {
    return (n + al - 1) / al * al;
}

fn assign_lvar_offsets(prog: *Function) void {
    var offset: isize = 0;

    for (prog.locals) |*local| {
        offset += 8;
        local.*.offset = -offset;
    }

    prog.stack_size = align_to(@intCast(offset), 16);
}

var counter: usize = 0;

fn emit(node: *Node) void {
    // print("Node: {}\n", .{node});

    if (node.kind == .INVALID) {
        return;
    }

    if (node.kind == .IF) {
        counter += 1;
        emit(node.cond);
        print("  cmp $0, %rax\n", .{});
        print("  je  .L.else.{d}\n", .{counter});
        emit(node.then);
        print("  jmp .L.end.{d}\n", .{counter});
        print(".L.else.{d}:\n", .{counter});

        if (node.hasElse) {
            emit(node.els);
        }

        print(".L.end.{d}:\n", .{counter});
        return;
    }

    if (node.kind == .FOR) {
        counter += 1;
        emit(node.init);
        print(".L.begin.{d}:\n", .{counter});

        if (node.hasCond) {
            emit(node.cond);
            print("  cmp $0, %rax\n", .{});
            print("  je  .L.end.{d}\n", .{counter});
        }
        emit(node.then);

        if (node.hasInc) {
            emit(node.inc);
        }

        print("  jmp .L.begin.{d}\n", .{counter});
        print(".L.end.{d}:\n", .{counter});
        return;
    }

    if (node.kind == .BLOCK) {
        // if (node.body.len == 0) return;

        for (node.body) |n| {
            emit(n);
        }
        return;
    }

    if (node.kind == .RETURN) {
        emit(node.ast.binary.lhs);
        print("  jmp .L.return\n", .{});
        return;
    }

    if (node.kind == .STATEMENT) {
        switch (node.ast) {
            .binary => |b| {
                emit(b.lhs);
                emit(b.rhs);
            },
            else => {},
        }
        return;
    }

    if (node.kind == .NUM) {
        print("  mov ${d}, %rax\n", .{node.value});

        return;
    }

    if (node.kind == .VAR) {
        gen_addr(node);
        print("  mov (%rax), %rax\n", .{});
        return;
    }

    if (node.kind == .ASSIGN) {
        gen_addr(node.ast.binary.lhs);
        push();
        emit(node.ast.binary.rhs);
        pop("%rdi");
        print("  mov %rax, (%rdi)\n", .{});
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

        .EQ, .NE, .LT, .LE, .GT, .GE => {
            print("  cmp %rdi, %rax\n", .{});

            if (node.kind == .EQ) {
                print("  sete %al\n", .{});
            } else if (node.kind == .NE) {
                print("  setne %al\n", .{});
            } else if (node.kind == .LT) {
                print("  setl %al\n", .{});
            } else if (node.kind == .LE) {
                print("  setle %al\n", .{});
            } else if (node.kind == .GT) {
                print("  setg %al\n", .{});
            } else if (node.kind == .GE) {
                print("  setge %al\n", .{});
            }

            print("  movzb %al, %rax\n", .{});
        },

        else => {
            std.log.err("found: {}\n", .{node});
            @panic("uh oh");
        },
    }
}
