const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");

const Manager = @import("Manager.zig");

const tracer = @import("tracer");
pub const tracer_impl = if (build_options.trace) tracer.chrome else tracer.none;

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 16 }){};

const allocator = alloc: {
    if (builtin.mode == .Debug) {
        break :alloc gpa.allocator();
    } else if (builtin.link_libc) {
        break :alloc std.heap.c_allocator;
    } else {
        break :alloc gpa.allocator();
    }
};

const benchmark = if (build_options.@"enable-bench") @embedFile("./bench/bench.c");

// Ensure allowed arch
comptime {
    switch (builtin.cpu.arch) {
        .x86_64 => {},
        else => @compileError("Unsupported architecture"),
    }
}

pub fn main() !u8 {
    defer _ = gpa.deinit();

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

    // Create a new build manager.
    var manager = try Manager.init(allocator);

    // Parse the command line.
    try manager.process_args();

    // Calculate the build graph.
    try manager.calculate();

    // Build the graph.
    try manager.build();

    // Cleanup
    manager.deinit();

    return 0;
}
