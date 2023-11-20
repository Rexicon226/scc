const std = @import("std");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var foo = try read_lines("input1.txt");
    _ = foo;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

fn read_lines(path: []const u8) !std.fs.File {
    var input_file = std.fs.cwd().openFile(path, .{}) catch std.debug.panic("No file {s} found!", .{path});
    defer input_file.close();

    var reader = input_file.reader();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var out = std.ArrayList(u8).init(gpa.allocator());
    try reader.streamUntilDelimiter(out.writer(), '\n', null);
    // this is blatantly unfinished btw

    return input_file;
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
