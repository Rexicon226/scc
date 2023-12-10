const std = @import("std");

const Self = @This();

name: []const u8,
start: i128,
end: i128,

pub noinline fn new(name: []const u8) !Self {
    // Start the timer.

    return Self{
        .name = name,
        .start = get_time_ns(),
        .end = 0,
    };
}

pub noinline fn stop(self: *Self) void {
    // Stop the timer.

    self.end = get_time_ns();
}

pub fn print(self: *Self) void {
    // Print the timer's name and duration.

    const duration = self.end - self.start;
    std.debug.print("Timer: {s}; Duration: {d} ns\n", .{ self.name, duration });
}

inline fn get_time_ns() i128 {
    return std.time.nanoTimestamp();
}
