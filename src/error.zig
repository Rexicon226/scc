// The Error Manager for SCC
// Kindly stolen from https://github.com/buzz-language/buzz

const std = @import("std");

const TokenImport = @import("token.zig");
const Token = TokenImport.Token;
const TokenType = TokenImport.Kind;

const Self = @This();
const assert = std.debug.assert;

pub const Error = enum(u8) {
    missing_token = 0,
};

pub const ReportKind = enum {
    @"error",
    warning,
    hint,

    pub fn color(self: ReportKind) u8 {
        return switch (self) {
            .@"error" => 31,
            .warning => 33,
            .hint => 35,
        };
    }

    pub fn name(self: ReportKind) []const u8 {
        return switch (self) {
            .@"error" => "Error",
            .warning => "Warning",
            .hint => "Note",
        };
    }

    pub fn nameLower(self: ReportKind) []const u8 {
        return switch (self) {
            .@"error" => " error",
            .warning => " warning",
            .hint => " note",
        };
    }

    pub fn prefix(self: ReportKind) []const u8 {
        return switch (self) {
            .@"error" => "E",
            .warning => "W",
            .hint => "H",
        };
    }
};

pub const ReportItem = struct {
    location: Token,
    kind: ReportKind = .@"error",
    message: []const u8,

    pub const SortContext = struct {};

    pub fn lessThan(_: SortContext, lhs: ReportItem, rhs: ReportItem) bool {
        return lhs.location.line < rhs.location.line or (lhs.location.line == rhs.location.line and lhs.location.column < rhs.location.column);
    }
};

pub const ReportOptions = struct {
    surrounding_lines: usize = 2,
    and_stop: bool = false,
};

pub const Report = struct {
    message: []const u8,
    error_type: Error,
    items: []const ReportItem,
    options: ReportOptions = .{},

    pub inline fn reportStderr(self: *Report) !void {
        return self.report(std.io.getStdErr().writer());
    }

    pub fn report(self: *Report, out: anytype) !void {
        assert(self.items.len > 0);

        const colorterm = std.os.getenv("COLORTERM");
        const true_color = if (colorterm) |ct|
            std.mem.eql(u8, ct, "24bit") or std.mem.eql(u8, ct, "truecolor")
        else
            false;
        _ = true_color;

        // Print main error message
        const main_item = self.items[0];

        // Use color codes, than reset
        try out.print(
            "\n{d}:{d}: \x1b[{d}m[{s}{d}] {s}\x1b[0m\n",
            .{
                main_item.location.line,
                main_item.location.column,
                main_item.kind.color(),
                main_item.kind.prefix(),
                @intFromEnum(self.error_type),
                main_item.message,
            },
        );

        // Print out other reports, that are meant to add information to the error
        for (self.items[1..]) |item| {
            _ = item;
        }
    }
};

pub const ErrorManager = struct {
    source: [:0]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: [:0]const u8) ErrorManager {
        return .{
            .source = source,
            .allocator = allocator,
        };
    }

    pub fn panic(self: *ErrorManager, error_type: Error, message: []const u8, reports: *[]ReportItem) void {
        _ = self;
        var error_report = Report{
            .message = message,
            .error_type = error_type,
            .items = reports.*,
        };

        error_report.reportStderr() catch @panic("Unable to report error");

        std.os.exit(1);
    }
};
