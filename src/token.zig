const std = @import("std");
const build_options = @import("options");
const tracer = if (build_options.trace) @import("tracer");

pub inline fn handler() void {
    if (!build_options.trace) return;
    const t = tracer.trace(@src());
    defer t.end();
}

/// Maximium number of characters an identifier can be.
const MAX_CHAR = 10;

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

    // Pointers
    Assign, // =
    Address, // &

    // Keywords
    Return, // return
    If, // if
    Else, // else
    For, // for
    While, // while

    // Equality
    Eq, // ==
    Ne, // !=
    Lt, // <
    Le, // <=
    Gt, // >
    Ge, // >=
};

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
    column: usize,
    file: []const u8 = "no file yet dummy",

    pub fn new_token(
        kind: Kind,
        start: usize,
        end: usize,
        line: Line,
        column: usize,
    ) !Token {
        handler();

        return .{
            .kind = kind,
            .start = start,
            .end = end,
            .line = line,
            .column = column,
        };
    }
};

pub const Tokenizer = struct {
    buffer: [:0]const u8 = undefined,
    index: usize = 0,
    tokens: std.ArrayList(Token),

    allocator: std.mem.Allocator,

    line: Line = .{ .start = 0, .end = 0, .line = 1, .column = 1 },

    pub fn init(source: [:0]const u8, allocator: std.mem.Allocator) !Tokenizer {
        handler();

        return Tokenizer{
            .buffer = source,
            .tokens = blk: {
                var tokens = std.ArrayList(Token).init(allocator);
                // I mean, in theory every character could be a token
                try tokens.ensureTotalCapacity(source.len);
                break :blk tokens;
            },
            .allocator = allocator,
        };
    }

    pub inline fn advance(self: *Tokenizer, amount: usize) void {
        handler();

        self.index += amount;
        self.line.column += amount;
    }

    pub fn generate(self: *Tokenizer) !void {
        handler();

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

        while (self.index < buffer.len) {
            handler();

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
                if (c == 'r') {
                    if (buffer[self.index..].len > 7) {
                        const slice = buffer[self.index + 1 .. self.index + 7];
                        if (std.mem.eql(u8, slice, "eturn ")) {
                            try self.tokens.append(
                                try Token.new_token(
                                    .Return,
                                    self.index,
                                    self.index + 7,
                                    self.line,
                                    self.line.column,
                                ),
                            );

                            self.advance(7);
                            continue;
                        }
                    }
                }

                if (c == 'i') {
                    if (buffer[self.index..].len > 3) {
                        const slice = buffer[self.index + 1 .. self.index + 3];
                        if (std.mem.eql(u8, slice, "f ")) {
                            try self.tokens.append(
                                try Token.new_token(
                                    .If,
                                    self.index,
                                    self.index + 3,
                                    self.line,
                                    self.line.column,
                                ),
                            );

                            self.advance(3);
                            continue;
                        }
                    }
                }

                if (c == 'e') {
                    if (buffer[self.index..].len > 5) {
                        const slice = buffer[self.index + 1 .. self.index + 5];
                        if (std.mem.eql(u8, slice, "lse ")) {
                            try self.tokens.append(
                                try Token.new_token(
                                    .Else,
                                    self.index,
                                    self.index + 5,
                                    self.line,
                                    self.line.column,
                                ),
                            );

                            self.advance(5);
                            continue;
                        }
                    }
                }

                if (c == 'f') {
                    if (buffer[self.index..].len > 4) {
                        const slice = buffer[self.index + 1 .. self.index + 4];
                        if (std.mem.eql(u8, slice, "or ")) {
                            try self.tokens.append(
                                try Token.new_token(
                                    .For,
                                    self.index,
                                    self.index + 4,
                                    self.line,
                                    self.line.column,
                                ),
                            );

                            self.advance(4);
                            continue;
                        }
                    }
                }

                if (c == 'w') {
                    if (buffer[self.index..].len > 5) {
                        const slice = buffer[self.index + 1 .. self.index + 5];
                        if (std.mem.eql(u8, slice, "hile")) {
                            try self.tokens.append(
                                try Token.new_token(
                                    .While,
                                    self.index,
                                    self.index + 5,
                                    self.line,
                                    self.line.column,
                                ),
                            );

                            self.advance(5);
                            continue;
                        }
                    }
                }
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                        self.line.column,
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
                    self.line.column,
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
                            self.line.column,
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
                        self.line.column,
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
                                self.line.column,
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
                            self.line.column,
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
                                self.line.column,
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
                            self.line.column,
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
                            self.line.column,
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
};
