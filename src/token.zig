const std = @import("std");

const MAX_TOKENS = 10;

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
    Assign, // =

    // Compare
    Eq, // ==
    Ne, // !=
    Lt, // <
    Le, // <=
    Gt, // >
    Ge, // >=

    SemiColon, // ;
};

pub const Token = struct {
    kind: Kind,

    start: usize,
    end: usize,

    pub fn new_token(
        kind: Kind,
        start: usize,
        end: usize,
    ) !Token {
        return .{
            .kind = kind,
            .start = start,
            .end = end,
        };
    }
};

pub const Tokenizer = struct {
    buffer: [:0]const u8 = undefined,
    index: usize = 0,
    tokens: std.ArrayList(Token),

    allocator: std.mem.Allocator,

    pub fn init(source: [:0]const u8, allocator: std.mem.Allocator) Tokenizer {
        return Tokenizer{
            .buffer = source,
            .tokens = std.ArrayList(Token).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn generate(self: *Tokenizer) !void {
        const buffer = self.buffer;

        if (self.index >= buffer.len) {
            @panic("empty buffer");
        }

        while (self.index < buffer.len) {
            const c = buffer[self.index];

            // Space
            if (c == ' ') {
                self.index += 1;
                continue;
            }

            // Number
            if (std.ascii.isDigit(c)) {
                const start = self.index;
                while (std.ascii.isDigit(buffer[self.index])) {
                    self.index += 1;

                    if (self.index - start > MAX_TOKENS) {
                        @panic("token too long");
                    }
                }

                try self.tokens.append(
                    try Token.new_token(
                        .Number,
                        start,
                        self.index,
                    ),
                );

                continue;
            }

            // Variable
            if (std.ascii.isAlphabetic(c)) {
                const start = self.index;
                while (std.ascii.isAlphabetic(buffer[self.index])) {
                    self.index += 1;

                    if (self.index - start > MAX_TOKENS) {
                        @panic("token too long");
                    }
                }

                try self.tokens.append(
                    try Token.new_token(
                        .Variable,
                        start,
                        self.index,
                    ),
                );

                continue;
            }

            if (c == '+') {
                try self.tokens.append(
                    try Token.new_token(
                        .Plus,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '-') {
                try self.tokens.append(
                    try Token.new_token(
                        .Minus,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '*') {
                try self.tokens.append(
                    try Token.new_token(
                        .Mul,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '/') {
                try self.tokens.append(
                    try Token.new_token(
                        .Div,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '(') {
                try self.tokens.append(
                    try Token.new_token(
                        .LeftParen,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == ')') {
                try self.tokens.append(
                    try Token.new_token(
                        .RightParen,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == ';') {
                try self.tokens.append(
                    try Token.new_token(
                        .SemiColon,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '=') {
                if (self.index + 1 < buffer.len and buffer[self.index + 1] == '=') {
                    try self.tokens.append(
                        try Token.new_token(
                            .Eq,
                            self.index,
                            self.index + 2,
                        ),
                    );

                    self.index += 2;
                    continue;
                }

                try self.tokens.append(
                    try Token.new_token(
                        .Assign,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
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
                            ),
                        );

                        self.index += 2;
                        continue;
                    }

                    try self.tokens.append(
                        try Token.new_token(
                            .Gt,
                            self.index,
                            self.index + 1,
                        ),
                    );

                    self.index += 1;
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
                            ),
                        );

                        self.index += 2;
                        continue;
                    }

                    try self.tokens.append(
                        try Token.new_token(
                            .Lt,
                            self.index,
                            self.index + 1,
                        ),
                    );

                    self.index += 1;
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
                        ),
                    );

                    self.index += 2;
                    continue;
                }
            }

            @panic("invalid character");
        }
    }
};
