// The Error Manager for SCC
// Kindly "inspired" by https://github.com/buzz-language/buzz

const std = @import("std");

const TokenImport = @import("token.zig");

const Token = TokenImport.Token;
const TokenType = TokenImport.Kind;
const Line = TokenImport.Line;

const Self = @This();
const assert = std.debug.assert;

// TODO: A function that inputs a line, column, and source,
// and outputs the character number

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
    location: Line,
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
    error_type: Error,
    items: []ReportItem,
    options: ReportOptions = .{},

    allocator: std.mem.Allocator,
    source_range: []const u8,

    pub inline fn reportStderr(self: *Report, source: [:0]const u8) !void {
        return self.report(std.io.getStdErr().writer(), source);
    }

    pub fn lessThanReport(_: void, lhs: ReportItem, rhs: ReportItem) bool {
        return lhs.location.column < rhs.location.column;
    }

    pub fn greaterThanReport(_: void, lhs: ReportItem, rhs: ReportItem) bool {
        return lhs.location.column > rhs.location.column;
    }

    pub fn report(
        self: *Report,
        out: anytype,
        source: [:0]const u8,
    ) !void {
        _ = source;
        assert(self.items.len > 0);

        const main_item = self.items[0];

        try out.print(
            "{d}:{d}: \x1b[{d}m[{s}{d}] {s}\x1b[0m\n",
            .{
                main_item.location.line,
                main_item.location.column,
                main_item.kind.color(),
                main_item.kind.prefix(),
                @intFromEnum(self.error_type),
                main_item.message,
            },
        );

        // Print the source code at that area.
        const slice = self.source_range;
        try out.print("    \x1b[2m─\x1b[0m \x1b[4m{s}\x1b[0m\n", .{slice});

        // Calculate stuff
        if (self.items.len > 1) {
            var up_dash = std.ArrayList(u8).init(self.allocator);
            // Max amount it will take.
            try up_dash.ensureTotalCapacity(self.source_range.len);

            var items = self.items[1..];
            var reverse_items: []ReportItem = try self.allocator.alloc(ReportItem, self.items.len - 1);
            @memcpy(reverse_items, items);

            // Sort the items by the column.
            std.sort.insertion(ReportItem, items, void{}, lessThanReport);
            std.sort.insertion(ReportItem, reverse_items, void{}, greaterThanReport);

            var item_index: usize = 0;
            var depth: usize = 0;
            var on: usize = 1;
            // Go through each line, printing how many brackets we need,
            // With the spacing they need.
            for (items) |item| {
                try up_dash.appendSlice("      ");

                for (1..(slice.len - depth) + 1) |i| {
                    if (i == items[item_index].location.column) {
                        if (i == reverse_items[on - 1].location.column) {
                            try up_dash.appendSlice("╰── ");
                            try up_dash.appendSlice(item.message);
                        } else {
                            try up_dash.append('|');
                        }

                        item_index += 1;
                    } else {
                        try up_dash.append(' ');
                    }
                }

                // Calculate the gap between the last index, and the second to last.
                if (on < items.len) {
                    const gap = items[items.len - on].location.column - items[items.len - (on + 1)].location.column;
                    depth += gap;
                }

                item_index = 0;
                on += 1;
                try up_dash.append('\n');
            }

            // Print the dashes.
            try out.print("{s}\n", .{up_dash.items});
        }
    }
};

// Draw the next item, with a line connecting to the source code, at the same column.
//  if (self.items.len > 1) {
//             for (self.items[1..]) |item| {
//                 const side_offset = 4 + item.location.column;
//                 const spaces = try self.allocator.alloc(u8, side_offset);
//                 @memset(spaces, ' ');
//                 defer self.allocator.free(spaces);

//

//                 try out.print(
//                     "{s}\x1b[{d}m╰───── {s}\x1b[0m\n",
//                     .{
//                         spaces,
//                         item.kind.color(),
//                         item.message,
//                     },
//                 );
//             }
//         }

pub const ErrorManager = struct {
    source: [:0]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: [:0]const u8) ErrorManager {
        return .{
            .source = source,
            .allocator = allocator,
        };
    }

    pub fn panic(
        self: *ErrorManager,
        error_type: Error,
        reports: *[]ReportItem,
        source_range: []const u8,
    ) noreturn {
        var error_report = Report{
            .error_type = error_type,
            .items = reports.*,
            .allocator = self.allocator,
            .source_range = source_range,
        };

        error_report.reportStderr(
            self.source,
        ) catch @panic("Unable to report error");

        std.os.exit(1);
    }
};
