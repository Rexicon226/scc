//! The build process management system.
//! A centrilized system for managing data flow during compilation.
//! Will parallelize as much as possible.
//!
//! Also handles many smaller utilities,
//!
//! - Arg Parsing
//! - Memory Management
//! - File IO

const std = @import("std");
const Allocator = std.mem.Allocator;

// Imports
const Tokenizer = @import("Token.zig");
const Parser = @import("Parser.zig");
const Sema = @import("Sema.zig");

// TODO: Automatically switch to the correct backend
// depending on a cli flag.
const CodeGen = @import("backend/x86_64/codegen.zig");

// Util
const AstPrinter = @import("util/ast_printer.zig").Printer;

const Manager = @This();

// The base allocator from which everything stems.
allocator: Allocator,

arguments: Args = Args{},

build_options: BuildOptions = BuildOptions{},

progress: std.Progress,

// Internals

// The entire manager uses one large arena allocator
// to easily manage the memory.
var arena: std.heap.ArenaAllocator = undefined;

/// Creates a new manager.
pub fn init(allocator: Allocator) !Manager {
    const progress: std.Progress = .{ .dont_print_on_dumb = true };

    arena = std.heap.ArenaAllocator.init(allocator);

    const _allocator = arena.allocator();

    return .{
        .allocator = _allocator,
        .progress = progress,
    };
}

/// Parses the command line arguments.
pub fn process_args(manager: *Manager) !void {
    var args = try std.process.argsAlloc(manager.allocator);

    if (args.len < 2) {
        std.log.err("Need at least one argument after \"scc\"\n", .{});
        usage();
        std.os.exit(1);
    }

    // Skip the first argument, which is the binary name.
    args = args[1..];

    var cursor: u32 = 0;
    while (cursor < args.len) : (cursor += 1) {
        const arg = args[cursor];

        if ((isEqual(arg, "--help")) or isEqual(arg, "-h")) {
            usage();
            manager.deinit();
            std.os.exit(0);
        }

        if (std.mem.eql(u8, arg, "--cli")) {
            manager.arguments.is_cli = true;

            if (args.len == cursor + 1) {
                std.log.err("No CLI input\n", .{});
                usage();
                manager.deinit();
                std.os.exit(1);
            }

            if (std.mem.startsWith(u8, args[cursor + 1], "--")) {
                std.log.err("No CLI input after --cli\n", .{});
                usage();
                manager.deinit();
                std.os.exit(1);
            }

            manager.arguments.cli_input = args[cursor + 1];
            cursor += 1;
            continue;
        }

        if (isEqual(arg, "--bench")) {
            @panic("Benchmarking is not yet implemented");
        }

        if (isEqual(arg, "--use-ir")) {
            manager.arguments.use_ir = true;
            continue;
        }

        if (!manager.arguments.is_cli) {
            @panic("File input not yet implemented, must use the --cli flag");
        } else {
            // --cli specific flags:

            if (isEqual(arg, "--ast")) {
                manager.arguments.print_ast = true;
                continue;
            }
        }

        std.log.err("Unknown flag: {s}\n", .{arg});
        usage();
        manager.deinit();
        std.os.exit(1);
    }
}

pub fn calculate(manager: *Manager) !void {
    if (manager.build_options.model == .linear) {
        return;
    }

    @panic("Parallel build model not yet implemented");
}

pub fn build(manager: *Manager) !void {
    const source = if (manager.arguments.is_cli) manager.arguments.cli_input else unreachable;

    // Progress
    var progress: std.Progress = .{ .dont_print_on_dumb = true };
    const main_progress_node = progress.start("", 0);
    defer main_progress_node.end();

    // Parse the source.
    var tokenizer = try Tokenizer.init(
        source,
        manager.allocator,
        main_progress_node,
    );
    try tokenizer.generate();
    const tokens = try tokenizer.tokens.toOwnedSlice();

    var parser = Parser.init(
        source,
        tokens,
        manager.allocator,
        main_progress_node,
    );

    // This is the node of the "main" function in the source.
    // NOTE: Currently there are no functions so the source is assumed to,
    // simply be the contents of the main function.
    const function = try parser.parse();

    // Print AST if user wanted.
    if (manager.arguments.print_ast) {
        var ast_printer = AstPrinter.init(manager.allocator);
        try ast_printer.print(function.body);
    }

    if (manager.arguments.use_ir) {

        // Sema uses a temporary child Arena
        var sema_arena = std.heap.ArenaAllocator.init(manager.allocator);

        // Create a new Sema instance
        var sema = try Sema.init(sema_arena.allocator());
        try sema.generate(function.body);

        const bytes_used = sema_arena.state.end_index;

        sema.print();
        std.debug.print("Arena Size: {} bytes\n", .{bytes_used});

        // Free the sema arena.
        sema_arena.deinit();

        // Nothing is really compatible yet with the new backend...
        std.os.exit(0);
    }

    // Emit the assembly.
    var codegen = try CodeGen.init(
        manager.allocator,
        main_progress_node,
    );

    try codegen.generate(function);
}

pub fn deinit(_: *Manager) void {

    // Free the arena.
    arena.deinit();
}

const Args = struct {
    /// The `--cli` flag, which allows the user to superseed
    /// any sort of file input. And instead use the CLI input.
    is_cli: bool = false,
    cli_input: [:0]const u8 = "",

    /// Embed the benchmark into the binary.
    is_bench: bool = false,

    /// Print the AST.
    print_ast: bool = false,

    // Experimental Flags

    use_ir: bool = false,
};

/// Tells the compiler what build graph model to use.
const BuildOptions = struct {
    model: BuildModel = .linear,
};

const BuildModel = enum {
    /// Simply builds the steps one by one. No parallelization.
    /// CPU is not required to have threading, nor more than one core.
    linear,
};

fn usage() void {
    const stdout = std.io.getStdOut().writer();

    const usage_string =
        \\ 
        \\ Usage:
        \\ scc <file> [options]
        \\
        \\ Options:
        \\  --cli <code> [options]  Run code as CLI
        \\               Cli Options:
        \\               --ast         Print AST (will cause the process to exit after rendering AST)
        \\
        \\  --bench       Run pre-set benchmark (only for testing purposes)
        \\                Must have been compiled with -Denable-bench=true                     
        \\
        \\  --help, -h    Print this message
        \\
        \\  Extremely Experimental Flags:
        \\  
        \\  --use-ir      Will use the IR mid-step for attempted optimization.
        \\
    ;
    stdout.print(usage_string, .{}) catch |err| std.debug.panic("Failed to print usage: {}\n", .{err});
}

fn isEqual(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
