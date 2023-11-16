const std = @import("std");
const TokenImport = @import("token.zig");
const ParserImport = @import("parser.zig");

const Token = TokenImport.Token;
const Kind = TokenImport.Kind;

const Node = ParserImport.Node;
const Function = ParserImport.Function;

pub var allocator: std.mem.Allocator = undefined;
pub var file: std.fs.File = undefined;

pub fn print(comptime format: []const u8, args: anytype) void {
    const stdout = file.writer();
    stdout.print(format, args) catch @panic("failed to write");
}

fn setupOutputFile(output_file: []const u8) !void {
    file = try std.fs.cwd().createFile(output_file, .{});
}

fn setupPrint() void {
    file = std.io.getStdOut();
}

/// Top-level options for the parser behavior
pub const ParserOptions = struct {
    /// If true, the parser will emit to `stdout`instead of the given file.
    print: bool = false,
};

pub fn parse(
    source: [:0]const u8,
    output_file: []const u8,
    options: ?ParserOptions,
    _allocator: std.mem.Allocator,
) !void {
    allocator = _allocator;

    if (options) |o| {
        if (o.print) {
            setupPrint();
        }
    } else {
        try setupOutputFile(output_file);
    }

    var tokenizer = TokenImport.Tokenizer.init(source, allocator);
    try tokenizer.tokens.ensureTotalCapacity(source.len);

    try tokenizer.generate();

    const tokens = try tokenizer.tokens.toOwnedSlice();

    var parser = ParserImport.Parser.init(source, tokens, allocator);
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

    // TODO: This can be omitted in certian cases
    // unknown yet which specific cases
    print("  mov %rbp, %rsp\n", .{});
    print("  pop %rbp\n", .{});
    print("  ret\n", .{});

    // Make sure stack is empty
    std.debug.assert(depth == 0);
}

/// Stack depth
var depth: usize = 0;

/// Pushes the value of rax onto the stack
fn push() void {
    print("  push %rax\n", .{});
    depth += 1;
}

/// Pops the value of `reg` from the stack
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

/// Aligns `n` to the closest (to n) multiple of `al`
///
/// e.g. `align_to(5, 4) == 8`
fn align_to(n: usize, al: usize) usize {
    return (n + al - 1) / al * al;
}

/// Pre-calculates and assigns the offset of each
/// local variable in `prog`
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
        @panic("invalid node");
    }

    // Control Flow
    {
        switch (node.kind) {
            .IF => {
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
            },

            .FOR => {
                counter += 1;
                if (node.hasInit) emit(node.init);

                print(".L.begin.{d}:\n", .{counter});

                if (node.hasCond) {
                    emit(node.cond);
                    print("  cmp $0, %rax\n", .{});
                    print("  je  .L.end.{d}\n", .{counter});
                }
                emit(node.then);

                if (node.hasInc) emit(node.inc);

                print("  jmp .L.begin.{d}\n", .{counter});
                print(".L.end.{d}:\n", .{counter});
                return;
            },

            .BLOCK => {
                {
                    if (node.body.len == 0) return;

                    for (node.body) |n| {
                        emit(n);
                    }

                    return;
                }
            },

            .RETURN => {
                {
                    emit(node.ast.binary.lhs);
                    print("  jmp .L.return\n", .{});
                    return;
                }
            },

            .STATEMENT => {
                {
                    switch (node.ast) {
                        .binary => |b| {
                            emit(b.lhs);
                            emit(b.rhs);
                        },
                        else => {},
                    }
                    return;
                }
            },

            else => {},
        }
    }

    // Variables
    {
        switch (node.kind) {
            .NUM => {
                print("  mov ${d}, %rax\n", .{node.value});
                return;
            },

            .VAR => {
                gen_addr(node);
                print("  mov (%rax), %rax\n", .{});
                return;
            },

            .ASSIGN => {
                gen_addr(node.ast.binary.lhs);
                push();
                emit(node.ast.binary.rhs);
                pop("%rdi");
                print("  mov %rax, (%rdi)\n", .{});
                return;
            },

            .DEREF => {
                emit(node.ast.binary.lhs);
                print("  mov (%rax), %rax\n", .{});
                return;
            },

            .ADDR => {
                gen_addr(node.ast.binary.lhs);
                return;
            },

            else => {},
        }
    }

    switch (node.ast) {
        .binary => {
            emit(node.ast.binary.rhs);
            push();
            emit(node.ast.binary.lhs);
            pop("%rdi");
        },
        .invalid => {},
    }

    // Operations
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

            switch (node.kind) {
                .EQ => print("  sete %al\n", .{}),
                .NE => print("  setne %al\n", .{}),
                .LT => print("  setl %al\n", .{}),
                .LE => print("  setle %al\n", .{}),
                .GT => print("  setg %al\n", .{}),
                .GE => print("  setge %al\n", .{}),
                else => {},
            }

            print("  movzb %al, %rax\n", .{});
        },

        else => {
            std.log.err("found: {}\n", .{node});
            @panic("uh oh");
        },
    }
}
