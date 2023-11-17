// File controls all io operations

const std = @import("std");

pub const WriterOptions = struct {
    file: ?[]const u8,
};

/// A writer
pub const Writer = struct {
    /// Allocator used for writing.
    allocator: std.mem.Allocator,

    /// Holds emitted bytes until the end.
    buffer: std.ArrayList(u8),

    /// Is this the target a file?
    isFile: bool,
    /// Target file.
    file: std.fs.File,

    options: WriterOptions = .{
        .file = null,
    },

    pub fn init(
        allocator: std.mem.Allocator,
        options: WriterOptions,
    ) !Writer {
        var isFile: bool = false;
        var file: std.fs.File = undefined;
        if (options.file) |_file| {
            isFile = true;
            file = try std.fs.cwd().createFile(_file, .{});
        }

        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .isFile = isFile,
            .file = file,
        };
    }

    pub fn print(self: *Writer, comptime str: []const u8) void {
        self.buffer.appendSlice(str) catch @panic("failed to append to buffer");
    }

    pub fn printArg(self: *Writer, comptime str: []const u8, arg: anytype) void {
        std.fmt.format(self.buffer.writer(), str, arg) catch @panic("failed to format print arg");
    }

    pub fn dump(self: *Writer) !void {
        const stdout = std.io.getStdOut();
        try stdout.writeAll(self.buffer.items);
    }

    pub fn output(self: *Writer) !void {
        if (self.isFile) {
            try self.file.writeAll(self.buffer.items);
        } else {
            // TODO: only use dump for debugging
            try self.dump();
        }
    }
};
