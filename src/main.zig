const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");

const tracer = @import("tracer");
pub const tracer_impl = if (build_options.trace) tracer.chrome else tracer.none;

const ParserImport = @import("parser.zig");
const CodeGen = @import("codegen.zig");
const ErrorManager = @import("error.zig").ErrorManager;

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};

var arena = std.heap.ArenaAllocator.init(alloc: {
    if (builtin.mode == .Debug) {
        break :alloc gpa.allocator();
    } else if (builtin.link_libc) {
        break :alloc std.heap.c_allocator;
    } else {
        break :alloc gpa.allocator();
    }
});
const allocator = arena.allocator();

const benchmark = if (build_options.@"enable-bench") @embedFile("./bench/bench.c");

// Ensure allowed arch
comptime {
    switch (builtin.cpu.arch) {
        .x86_64 => {},
        else => @compileError("Unsupported architecture"),
    }
}

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
        \\               --ast         Print AST
        \\
        \\  --bench       Run pre-set benchmark (only for testing purposes)
        \\                Must have been compiled with -Denable-bench=true                
        \\
        \\  --help, -h    Print this message
        \\
    ;
    stdout.print(usage_string, .{}) catch @panic("failed to print usage");
}

pub fn main() !u8 {
    defer _ = gpa.deinit();
    defer arena.deinit();

    if (comptime build_options.trace) {
        std.log.info("Tracing enabled", .{});
        try tracer.init();
        try tracer.init_thread();
    }

    defer {
        if (comptime build_options.trace) {
            tracer.deinit();
            tracer.deinit_thread();
        }
    }

    const t = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
    defer if (comptime build_options.trace) t.end();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("Need at least one argument after \"scc\"\n", .{});
        usage();
        return 1;
    }

    var source_buf: ?[:0]const u8 = null;
    var output_file: []const u8 = "";

    var options: CodeGen.ParserOptions = .{};

    var i: usize = 1; // Skip over "scc"
    while (i < args.len) : (i += 1) {
        const t_ = if (comptime build_options.trace) tracer.trace(@src(), "", .{});
        defer if (comptime build_options.trace) t_.end();

        const arg = args[i];

        // Flags
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                usage();
                return 0;
            } else if (std.mem.eql(u8, arg, "--cli")) {
                source_buf = args[i + 1];
                i += 1;
                options.print = true;
            } else if (std.mem.eql(u8, arg, "--ast")) {
                options.printAst = true;
            } else if (std.mem.eql(u8, arg, "--bench")) {
                if (!build_options.@"enable-bench") {
                    std.log.err(
                        \\Benchmarking is disabled
                        \\Please recompile with -Denable-bench=true to enable benchmarking
                    , .{});
                    return 1;
                }

                source_buf = benchmark;
                options.print = true;
            } else {
                std.log.err("Unknown flag: {s}\n", .{arg});
                usage();
                return 1;
            }
        } else {
            // Assuming it's a file, i.e "scc file.c"

            const file = args[1];
            var source = try std.fs.cwd().openFile(file, .{});
            defer source.close();
            const source_size = (try source.stat()).size;

            // max 2 ^ 32 - 1 bytes
            if (source_size > std.math.maxInt(u32) - 1) {
                std.log.err("File too big\n", .{});
                return 1;
            }

            source_buf = try source.readToEndAllocOptions(allocator, source_size, null, 4, 0);

            var outputFile = std.mem.splitSequence(u8, file, ".c");
            const outputFileName = outputFile.next().?;
            output_file = try std.fmt.allocPrint(allocator, "{s}.s", .{outputFileName});
        }
    }

    if (source_buf) |s| {
        try CodeGen.parse(
            s,
            output_file,
            options,
            allocator,
        );

        return 0;
    } else {
        std.log.err("No source\n", .{});
        usage();
        return 1;
    }

    return 0;
}
