const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("options");
const tracer = if (build_options.trace) @import("tracer");

const Tokenizer = @import("../../Token.zig");
const Parser = @import("../../Parser.zig");

const Writer = @import("../../util/io.zig").Writer;

const AstPrinter = @import("../../util/ast_printer.zig").Printer;

const Token = Tokenizer.Token;
const Kind = Tokenizer.Kind;

const Node = Parser.Node;
const Function = Parser.Function;

const CodeGen = @This();

writer: Writer,
allocator: std.mem.Allocator,
progress: *std.Progress.Node,

pub fn init(
    allocator: std.mem.Allocator,
    progress: *std.Progress.Node,
) !CodeGen {
    const writer = try Writer.init(allocator, .{ .file = null });

    return .{
        .allocator = allocator,
        .progress = progress,
        .writer = writer,
    };
}

pub fn generate(
    self: *CodeGen,
    function: *Function,
) !void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    // Pre-calculate the offsets we need
    assign_lvar_offsets(function);

    // Ensure we're running on x86_64
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
            self.writer.print("\t.globl main\n");
            self.writer.print("main:\n");
        },
        .macos => {
            self.writer.print("\t.globl _main\n");
            self.writer.print("_main:\n");
        },
        else => {
            std.log.err("Unsupported OS: {}\n", .{builtin.os});
            @panic("Unsupported OS for codegen");
        },
    }

    // Prologue
    self.writer.print("  push %rbp\n");
    self.writer.print("  mov %rsp, %rbp\n");
    self.writer.printArg("  sub ${d}, %rsp\n", .{function.stack_size});

    // Emit code
    // const emit_prog = progress.start("Emitting Block", function.body.len);

    for (function.body) |body| {
        self.statement(body);

        // emit_prog.completeOne();
    }

    // emit_prog.end();

    // Epilogue
    self.writer.print(".L.return:\n");

    // TODO: This can be omitted in certian cases
    // unknown yet which specific cases
    self.writer.print("  mov %rbp, %rsp\n");
    self.writer.print("  pop %rbp\n");
    self.writer.print("  ret\n");

    // Make sure stack is empty
    std.debug.assert(depth == 0);

    // Output
    try self.writer.output();
}

/// Stack depth
var depth: usize = 0;

/// Pushes the value of rax onto the stack
fn push(self: *CodeGen) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    self.writer.print("  push %rax\n");
    depth += 1;
}

/// Pops the value of `reg` from the stack
fn pop(self: *CodeGen, reg: []const u8) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    self.writer.printArg("  pop {s}\n", .{reg});
    depth -= 1;
}

fn gen_addr(self: *CodeGen, node: *Node) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    switch (node.kind) {
        .VAR => {
            self.writer.printArg("  lea {d}(%rbp), %rax\n", .{node.variable.offset});
            return;
        },

        .DEREF => {
            self.expression(node.ast.unary.op);
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

fn expression(self: *CodeGen, node: *Node) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    switch (node.kind) {
        .NUM => {
            self.writer.printArg("  mov ${d}, %rax\n", .{node.value});
            return;
        },

        .NEG => {
            self.expression(node.ast.unary.op);
            self.writer.print("  neg %rax\n");
            return;
        },

        .VAR => {
            self.gen_addr(node);
            self.writer.print("  mov (%rax), %rax\n");
            return;
        },

        .DEREF => {
            self.expression(node.ast.unary.op);
            self.writer.print("  mov (%rax), %rax\n");
            return;
        },

        .ADDR => {
            self.gen_addr(node.ast.unary.op);
            return;
        },

        .ASSIGN => {
            self.gen_addr(node.ast.binary.lhs);
            self.push();
            self.expression(node.ast.binary.rhs);
            self.pop("%rdi");
            self.writer.print("  mov %rax, (%rdi)\n");
            return;
        },
        else => {},
    }

    self.expression(node.ast.binary.rhs);
    self.push();
    self.expression(node.ast.binary.lhs);
    self.pop("%rdi");

    // Operations
    switch (node.kind) {
        .ADD => {
            self.writer.print("  add %rdi, %rax\n");
        },

        .SUB => {
            self.writer.print("  sub %rdi, %rax\n");
        },

        .MUL => {
            self.writer.print("  imul %rdi, %rax\n");
        },

        .DIV => {
            self.writer.print("  cqo\n");
            self.writer.print("  idiv %rdi\n");
        },

        .EQ, .NE, .LT, .LE, .GT, .GE => {
            self.writer.print("  cmp %rdi, %rax\n");

            switch (node.kind) {
                .EQ => self.writer.print("  sete %al\n"),
                .NE => self.writer.print("  setne %al\n"),
                .LT => self.writer.print("  setl %al\n"),
                .LE => self.writer.print("  setle %al\n"),
                .GT => self.writer.print("  setg %al\n"),
                .GE => self.writer.print("  setge %al\n"),
                else => {},
            }

            self.writer.print("  movzb %al, %rax\n");
        },

        else => {
            std.log.err("found: {}\n", .{node});
            @panic("invalid token passed into expression gen");
        },
    }
}

fn statement(self: *CodeGen, node: *Node) void {
    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    switch (node.kind) {
        .IF => {
            counter += 1;
            self.expression(node.cond);
            self.writer.print("  cmp $0, %rax\n");
            self.writer.printArg("  je  .L.else.{d}\n", .{counter});
            self.statement(node.then);
            self.writer.printArg("  jmp .L.end.{d}\n", .{counter});
            self.writer.printArg(".L.else.{d}:\n", .{counter});

            if (node.hasElse) {
                self.statement(node.els);
            }

            self.writer.printArg(".L.end.{d}:\n", .{counter});
            return;
        },

        .FOR => {
            counter += 1;
            if (node.hasInit) self.statement(node.init);

            self.writer.printArg(".L.begin.{d}:\n", .{counter});

            if (node.hasCond) {
                self.expression(node.cond);
                self.writer.print("  cmp $0, %rax\n");
                self.writer.printArg("  je  .L.end.{d}\n", .{counter});
            }
            self.statement(node.then);

            if (node.hasInc) self.expression(node.inc);

            self.writer.printArg("  jmp .L.begin.{d}\n", .{counter});
            self.writer.printArg(".L.end.{d}:\n", .{counter});
            return;
        },

        .BLOCK => {
            if (!node.hasBody) return;

            for (node.body) |n| {
                self.statement(n);
            }

            return;
        },

        .RETURN => {
            self.expression(node.ast.unary.op);
            self.writer.print("  jmp .L.return\n");
            return;
        },

        .STATEMENT => {
            self.expression(node.ast.unary.op);
            return;
        },

        else => {
            std.log.err("found: {}\n", .{node});
            @panic("invalid token passed into statement gen");
        },
    }
}
