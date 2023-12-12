const std = @import("std");
const build_options = @import("options");
const tracer = @import("tracer");

const Tokenizer = @This();

/// Maximium number of characters an identifier can be.
const MAX_CHAR = 10;

buffer: [:0]const u8 = undefined,
index: usize = 0,
tokens: std.ArrayList(Token),

allocator: std.mem.Allocator,
progress: *std.Progress.Node,

line: Line = .{ .start = 0, .end = 0, .line = 1, .column = 1 },

pub fn init(
    source: [:0]const u8,
    allocator: std.mem.Allocator,
    progress: *std.Progress.Node,
) !Tokenizer {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    return Tokenizer{
        .buffer = source,
        .tokens = blk: {
            var tokens = std.ArrayList(Token).init(allocator);
            // In theory every character could be a token
            try tokens.ensureTotalCapacity(source.len);
            break :blk tokens;
        },
        .allocator = allocator,
        .progress = progress,
    };
}

pub inline fn advance(self: *Tokenizer, amount: usize) void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    self.index += amount;
    self.line.column += amount;
}

pub fn generate(self: *Tokenizer) !void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    const buffer = self.buffer;

    if (self.index >= buffer.len) {
        @panic("empty buffer");
    }

    var pre_lines = std.mem.splitSequence(u8, buffer, "\n");
    var current_line: []const u8 = pre_lines.next().?;
    var current_line_offset: usize = 0;

    self.line = .{
        .start = current_line_offset,
        .end = current_line_offset + current_line.len,
        .line = 1,
        .column = 1,
    };

    var char_prog = self.progress.start("Tokenizing", buffer.len);
    char_prog.activate();
    defer char_prog.end();

    while (self.index < buffer.len) {
        const t_ = tracer.trace(@src(), "", .{});

        defer {
            t_.end();

            char_prog.setCompletedItems(self.index);
            char_prog.context.maybeRefresh();
        }

        const c = buffer[self.index];

        // Space
        if (c == ' ') {
            self.advance(1);
            continue;
        }

        // Comment
        // Check the first character of the line, and the next character is a '/'
        if (c == '/' and self.line.column == 1 and self.index + 1 < buffer.len) {
            if (buffer[self.index + 1] == '/') {
                // Skip the rest of the line
                while (self.index < buffer.len and buffer[self.index] != '\n') {
                    self.advance(1);
                }

                continue;
            }
        }

        // Newline
        if (c == '\n') {
            self.line.column = 1;
            self.index += 1;

            current_line = pre_lines.next().?;
            current_line_offset = self.index;

            self.line = .{
                .start = current_line_offset,
                .end = current_line_offset + current_line.len,
                .line = self.line.line + 1,
                .column = 1,
            };

            continue;
        }

        // Keywords
        {
            const is_keyword: bool = keyword: {
                inline for (Keywords.kvs) |entry| {
                    const t__ = tracer.trace(@src(), "", .{});
                    defer t__.end();

                    const key_len = entry.key.len;
                    if (buffer[self.index..].len > key_len) {
                        const potential_keyword = buffer[self.index .. self.index + key_len];
                        const exists = Keywords.get(potential_keyword);

                        if (exists) |kind| {
                            try self.tokens.append(
                                try Token.new_token(
                                    kind,
                                    self.index,
                                    self.index + key_len,
                                    self.line,
                                ),
                            );

                            self.advance(key_len);
                            break :keyword true;
                        }
                    }
                }
                break :keyword false;
            };

            if (is_keyword) continue;
        }

        // Number
        if (std.ascii.isDigit(c)) {
            const start = self.index;
            while (std.ascii.isDigit(buffer[self.index])) {
                self.advance(1);

                if (self.index - start > MAX_CHAR) {
                    @panic("number token too long");
                }
            }

            try self.tokens.append(
                try Token.new_token(
                    .Number,
                    start,
                    self.index,
                    self.line,
                ),
            );

            continue;
        }

        // Variable
        if (std.ascii.isAlphabetic(c)) {
            const start = self.index;

            while (std.ascii.isAlphanumeric(buffer[self.index])) {
                self.advance(1);

                if (self.index - start > MAX_CHAR) {
                    @panic("indentifier token too long");
                }
            }

            try self.tokens.append(
                try Token.new_token(
                    .Variable,
                    start,
                    self.index,
                    self.line,
                ),
            );

            continue;
        }

        // Operators
        if (c == '+') {
            try self.tokens.append(
                try Token.new_token(
                    .Plus,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '-') {
            try self.tokens.append(
                try Token.new_token(
                    .Minus,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '*') {
            try self.tokens.append(
                try Token.new_token(
                    .Mul,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '/') {
            try self.tokens.append(
                try Token.new_token(
                    .Div,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '(') {
            try self.tokens.append(
                try Token.new_token(
                    .LeftParen,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == ')') {
            try self.tokens.append(
                try Token.new_token(
                    .RightParen,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '{') {
            try self.tokens.append(
                try Token.new_token(
                    .LeftBracket,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '}') {
            try self.tokens.append(
                try Token.new_token(
                    .RightBracket,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == ';') {
            try self.tokens.append(
                try Token.new_token(
                    .SemiColon,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == ',') {
            try self.tokens.append(
                try Token.new_token(
                    .Comma,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '&') {
            try self.tokens.append(try Token.new_token(
                .Address,
                self.index,
                self.index + 1,
                self.line,
            ));

            self.advance(1);
            continue;
        }

        if (c == '=') {
            if (self.index + 1 < buffer.len and buffer[self.index + 1] == '=') {
                try self.tokens.append(
                    try Token.new_token(
                        .Eq,
                        self.index,
                        self.index + 2,
                        self.line,
                    ),
                );

                self.advance(2);
                continue;
            }

            try self.tokens.append(
                try Token.new_token(
                    .Assign,
                    self.index,
                    self.index + 1,
                    self.line,
                ),
            );

            self.advance(1);
            continue;
        }

        if (c == '>') {
            if (self.index + 1 < buffer.len) {
                if (buffer[self.index + 1] == '=') {
                    try self.tokens.append(
                        try Token.new_token(
                            .Ge,
                            self.index,
                            self.index + 2,
                            self.line,
                        ),
                    );

                    self.advance(2);
                    continue;
                }

                try self.tokens.append(
                    try Token.new_token(
                        .Gt,
                        self.index,
                        self.index + 1,
                        self.line,
                    ),
                );

                self.advance(1);
                continue;
            }
        }

        if (c == '<') {
            if (self.index + 1 < buffer.len) {
                if (buffer[self.index + 1] == '=') {
                    try self.tokens.append(
                        try Token.new_token(
                            .Le,
                            self.index,
                            self.index + 2,
                            self.line,
                        ),
                    );

                    self.advance(2);
                    continue;
                }

                try self.tokens.append(
                    try Token.new_token(
                        .Lt,
                        self.index,
                        self.index + 1,
                        self.line,
                    ),
                );

                self.advance(1);
                continue;
            }
        }

        if (c == '!') {
            if (self.index + 1 < buffer.len and buffer[self.index + 1] == '=') {
                try self.tokens.append(
                    try Token.new_token(
                        .Ne,
                        self.index,
                        self.index + 2,
                        self.line,
                    ),
                );

                self.advance(2);
                continue;
            }
        }

        std.log.err("invalid character: {c}", .{c});
        @panic("tokenizer");
    }
}

pub const Kind = enum {
    // Operators
    Plus, // +
    Minus, // -
    Mul, // *
    Div, // /

    // Literals
    Number,
    Variable,

    // Punctuation
    LeftParen, // (
    RightParen, // )
    LeftBracket, // {
    RightBracket, // }
    SemiColon, // ;
    Comma, // ,

    // Pointers
    Assign, // =
    Address, // &

    // Keywords
    Return, // return
    If, // if
    Else, // else
    For, // for
    While, // while

    // Types
    Int, // int

    // Equality
    Eq, // ==
    Ne, // !=
    Lt, // <
    Le, // <=
    Gt, // >
    Ge, // >=
};

// Spaces after keywords are very important!!!
const Keywords = std.ComptimeStringMap(Kind, .{
    // Keywords
    .{ "return ", .Return },
    .{ "if ", .If },
    .{ "else ", .Else },
    .{ "for ", .For },
    .{ "while", .While },

    // Types
    .{ "int ", .Int },
});

/// Source Position Information
pub const Line = struct {
    /// The start index of the line that the token is on
    ///
    /// (starts from 1)
    start: usize,
    /// The end index of the line that the token is on
    ///
    /// (starts from 1)
    end: usize,

    // Normal
    /// The line number that the token is on
    ///
    /// (starts from 1)
    line: usize,
    /// The column number that the token is on
    ///
    /// (starts from 1)
    column: usize,
};

/// The Generic Token
pub const Token = struct {
    /// The kind of token
    kind: Kind,

    start: usize,
    end: usize,

    // Metadata
    line: Line,
    file: []const u8 = "no file yet dummy",

    pub fn new_token(
        kind: Kind,
        start: usize,
        end: usize,
        line: Line,
    ) !Token {
        const t = tracer.trace(@src(), "", .{});
        defer t.end();

        return .{
            .kind = kind,
            .start = start,
            .end = end,
            .line = line,
        };
    }

    pub fn get_ident(self: Token, source: [:0]const u8) []const u8 {
        const t = tracer.trace(@src(), "", .{});
        defer t.end();

        if (self.kind != .Variable) {
            @panic("not a variable token");
        }

        return source[self.start..self.end];
    }
};
