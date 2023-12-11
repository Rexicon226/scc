const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("options");
const tracer = if (build_options.trace) @import("tracer");

const TokenImport = @import("token.zig");
const ParserImport = @import("parser.zig");

const Writer = @import("util/io.zig").Writer;

const AstPrinter = @import("util/ast_printer.zig").Printer;

const Token = TokenImport.Token;
const Tokenizer = TokenImport.Tokenizer;
const Kind = TokenImport.Kind;

const Node = ParserImport.Node;
const Function = ParserImport.Function;
const Parser = ParserImport.Parser;

var allocator: std.mem.Allocator = undefined;
var writer: Writer = undefined;

/// Top-level options for the parser behavior
pub const ParserOptions = struct {
    /// If true, the parser will emit to `stdout`instead of the given file.
    print: bool = false,

    /// A debug mode, that will print the ast tree before emitting code.
    printAst: bool = false,
};

pub fn parse(
    source: [:0]const u8,
    output_file: []const u8,
    options: ?ParserOptions,
    _allocator: std.mem.Allocator,
) !void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    var printAst: bool = false;
    if (options) |o| printAst = o.printAst;

    // Setup
    {
        allocator = _allocator;

        const _writer = try Writer.init(allocator, .{
            .file = if (options) |o| if (!o.print) output_file else null else output_file,
        });
        writer = _writer;
    }

    // Progress
    var progress: std.Progress = .{ .dont_print_on_dumb = true };
    const main_progress_node = progress.start("", 0);
    defer main_progress_node.end();

    var tokenizer = try Tokenizer.init(
        source,
        allocator,
        main_progress_node,
    );
    try tokenizer.generate();
    const tokens = try tokenizer.tokens.toOwnedSlice();

    var parser = Parser.init(
        source,
        tokens,
        allocator,
        main_progress_node,
    );
    const function = try parser.parse();

    if (printAst) {
        var ast_printer = AstPrinter.init(allocator);
        try ast_printer.print(function.body);
    }

    // Pre-calculate the offsets we need
    assign_lvar_offsets(function);

    // Ensure we're compiling on x86_64
    // NOTE(SeedyROM): The architecture should be a cli option probably,
    // not the same as the OS it's built on.
    switch (builtin.cpu.arch) {
        .x86_64 => {},
        else => {
            std.log.err("Unsupported architecture: {}\n", .{builtin.cpu.arch});
            @panic("Unsupported architecture");
        },
    }

    // Entry point depends on OS
    switch (builtin.os.tag) {
        .linux => {
            writer.print("\t.globl main\n");
            writer.print("main:\n");
        },
        .macos => {
            writer.print("\t.globl _main\n");
            writer.print("_main:\n");
        },
        else => {
            std.log.err("Unsupported OS: {}\n", .{builtin.os});
            @panic("Unsupported OS for codegen");
        },
    }

    // Prologue
    writer.print("  push %rbp\n");
    writer.print("  mov %rsp, %rbp\n");
    writer.printArg("  sub ${d}, %rsp\n", .{function.stack_size});

    // Emit code
    const emit_prog = progress.start("Emitting Block", function.body.len);

    for (function.body) |body| {
        statement(body);

        emit_prog.completeOne();
    }

    emit_prog.end();

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
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    writer.print("  push %rax\n");
    depth += 1;
}

/// Pops the value of `reg` from the stack
fn pop(reg: []const u8) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    writer.printArg("  pop {s}\n", .{reg});
    depth -= 1;
}

fn gen_addr(node: *Node) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    switch (node.kind) {
        .VAR => {
            writer.printArg("  lea {d}(%rbp), %rax\n", .{node.variable.offset});
            return;
        },

        .DEREF => {
            expression(node.ast.unary.op);
            return;
        },

        else => {
            std.log.err("found: {}\n", .{node});
            @panic("not an lvalue");
        },
    }
}

/// Aligns `n` to the closest (to n) multiple of `al`
///
/// e.g. `align_to(5, 4) == 8`
fn align_to(n: usize, al: usize) usize {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    return (n + al - 1) / al * al;
}

/// Pre-calculates and assigns the offset of each
/// local variable in `prog`
fn assign_lvar_offsets(prog: *Function) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    var offset: isize = 0;

    for (prog.locals) |local| {
        offset += 8;
        local.offset = -offset;
    }

    prog.stack_size = align_to(@intCast(offset), 16);
}

var counter: usize = 0;

fn expression(node: *Node) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    switch (node.kind) {
        .NUM => {
            writer.printArg("  mov ${d}, %rax\n", .{node.value});
            return;
        },

        .NEG => {
            expression(node.ast.unary.op);
            writer.print("  neg %rax\n");
            return;
        },

        .VAR => {
            gen_addr(node);
            writer.print("  mov (%rax), %rax\n");
            return;
        },

        .DEREF => {
            expression(node.ast.unary.op);
            writer.print("  mov (%rax), %rax\n");
            return;
        },

        .ADDR => {
            gen_addr(node.ast.unary.op);
            return;
        },

        .ASSIGN => {
            gen_addr(node.ast.binary.lhs);
            push();
            expression(node.ast.binary.rhs);
            pop("%rdi");
            writer.print("  mov %rax, (%rdi)\n");
            return;
        },
        else => {},
    }

    expression(node.ast.binary.rhs);
    push();
    expression(node.ast.binary.lhs);
    pop("%rdi");

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
            @panic("invalid token passed into expression gen");
        },
    }
}

fn statement(node: *Node) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    switch (node.kind) {
        .IF => {
            counter += 1;
            expression(node.cond);
            writer.print("  cmp $0, %rax\n");
            writer.printArg("  je  .L.else.{d}\n", .{counter});
            statement(node.then);
            writer.printArg("  jmp .L.end.{d}\n", .{counter});
            writer.printArg(".L.else.{d}:\n", .{counter});

            if (node.hasElse) {
                statement(node.els);
            }

            writer.printArg(".L.end.{d}:\n", .{counter});
            return;
        },

        .FOR => {
            counter += 1;
            if (node.hasInit) statement(node.init);

            writer.printArg(".L.begin.{d}:\n", .{counter});

            if (node.hasCond) {
                expression(node.cond);
                writer.print("  cmp $0, %rax\n");
                writer.printArg("  je  .L.end.{d}\n", .{counter});
            }
            statement(node.then);

            if (node.hasInc) expression(node.inc);

            writer.printArg("  jmp .L.begin.{d}\n", .{counter});
            writer.printArg(".L.end.{d}:\n", .{counter});
            return;
        },

        .BLOCK => {
            if (!node.hasBody) return;

            for (node.body) |n| {
                statement(n);
            }

            return;
        },

        .RETURN => {
            expression(node.ast.unary.op);
            writer.print("  jmp .L.return\n");
            return;
        },

        .STATEMENT => {
            expression(node.ast.unary.op);
            return;
        },

        else => {
            std.log.err("found: {}\n", .{node});
            @panic("invalid token passed into statement gen");
        },
    }
}
