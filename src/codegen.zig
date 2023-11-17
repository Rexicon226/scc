const std = @import("std");
const TokenImport = @import("token.zig");
const ParserImport = @import("parser.zig");

const Writer = @import("io.zig").Writer;

const Token = TokenImport.Token;
const Tokenizer = TokenImport.Tokenizer;
const Kind = TokenImport.Kind;

const Node = ParserImport.Node;
const Function = ParserImport.Function;
const Parser = ParserImport.Parser;

var allocator: std.mem.Allocator = undefined;
var writer: Writer = undefined;

/// Writes the buffer to the output (file/stdout)
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
    // Setup
    {
        allocator = _allocator;

        const _writer = try Writer.init(allocator, .{
            .file = if (options) |o| if (!o.print) output_file else null else output_file,
        });
        writer = _writer;
    }

    var tokenizer = try Tokenizer.init(source, allocator);
    try tokenizer.generate();
    const tokens = try tokenizer.tokens.toOwnedSlice();

    var parser = Parser.init(source, tokens, allocator);
    const function = try parser.parse();

    // Pre-calculate the offsets we need
    assign_lvar_offsets(function);

    // Entry point
    writer.print("  .globl main\n");
    writer.print("main:\n");

    // Prologue
    writer.print("  push %rbp\n");
    writer.print("  mov %rsp, %rbp\n");
    writer.printArg("  sub ${d}, %rsp\n", .{function.stack_size});

    // Emit code
    for (function.body) |node| {
        emit(node);
    }

    // Epilogue
    writer.print(".L.return:\n");

    // TODO: This can be omitted in certian cases
    // unknown yet which specific cases
    writer.print("  mov %rbp, %rsp\n");
    writer.print("  pop %rbp\n");
    writer.print("  ret\n");

    // Make sure stack is empty
    std.debug.assert(depth == 0);

    // Output
    try writer.output();
}

/// Stack depth
var depth: usize = 0;

/// Pushes the value of rax onto the stack
fn push() void {
    writer.print("  push %rax\n");
    depth += 1;
}

/// Pops the value of `reg` from the stack
fn pop(reg: []const u8) void {
    writer.printArg("  pop {s}\n", .{reg});
    depth -= 1;
}

fn gen_addr(node: *Node) void {
    if (node.kind == .VAR) {
        writer.printArg("  lea {d}(%rbp), %rax\n", .{node.variable.offset});
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
    // writer.print("Node: {}\n", .{node});

    if (node.kind == .INVALID) {
        @panic("invalid node");
    }

    // Control Flow
    {
        switch (node.kind) {
            .IF => {
                counter += 1;
                emit(node.cond);
                writer.print("  cmp $0, %rax\n");
                writer.printArg("  je  .L.else.{d}\n", .{counter});
                emit(node.then);
                writer.printArg("  jmp .L.end.{d}\n", .{counter});
                writer.printArg(".L.else.{d}:\n", .{counter});

                if (node.hasElse) {
                    emit(node.els);
                }

                writer.printArg(".L.end.{d}:\n", .{counter});
                return;
            },

            .FOR => {
                counter += 1;
                if (node.hasInit) emit(node.init);

                writer.printArg(".L.begin.{d}:\n", .{counter});

                if (node.hasCond) {
                    emit(node.cond);
                    writer.print("  cmp $0, %rax\n");
                    writer.printArg("  je  .L.end.{d}\n", .{counter});
                }
                emit(node.then);

                if (node.hasInc) emit(node.inc);

                writer.printArg("  jmp .L.begin.{d}\n", .{counter});
                writer.printArg(".L.end.{d}:\n", .{counter});
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
                    writer.print("  jmp .L.return\n");
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
                writer.printArg("  mov ${d}, %rax\n", .{node.value});
                return;
            },

            .VAR => {
                gen_addr(node);
                writer.print("  mov (%rax), %rax\n");
                return;
            },

            .ASSIGN => {
                gen_addr(node.ast.binary.lhs);
                push();
                emit(node.ast.binary.rhs);
                pop("%rdi");
                writer.print("  mov %rax, (%rdi)\n");
                return;
            },

            .DEREF => {
                emit(node.ast.binary.lhs);
                writer.print("  mov (%rax), %rax\n");
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
            writer.print("  add %rdi, %rax\n");
        },

        .SUB => {
            writer.print("  sub %rdi, %rax\n");
        },

        .MUL => {
            writer.print("  imul %rdi, %rax\n");
        },

        .DIV => {
            writer.print("  cqo\n");
            writer.print("  idiv %rdi\n");
        },

        .NEG => {
            writer.print("  neg %rax\n");
        },

        .EQ, .NE, .LT, .LE, .GT, .GE => {
            writer.print("  cmp %rdi, %rax\n");

            switch (node.kind) {
                .EQ => writer.print("  sete %al\n"),
                .NE => writer.print("  setne %al\n"),
                .LT => writer.print("  setl %al\n"),
                .LE => writer.print("  setle %al\n"),
                .GT => writer.print("  setg %al\n"),
                .GE => writer.print("  setge %al\n"),
                else => {},
            }

            writer.print("  movzb %al, %rax\n");
        },

        else => {
            std.log.err("found: {}\n", .{node});
            @panic("uh oh");
        },
    }
}
