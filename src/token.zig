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
    LeftBracket, // {
    RightBracket, // }

    Assign, // =

    // Keywords
    Return, // return
    If, // if
    Else, // else
    For, // for

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

            // Keywords
            if (c == 'r') {
                const slice = buffer[self.index + 1 .. self.index + 7];
                if (std.mem.eql(u8, slice, "eturn ")) {
                    try self.tokens.append(
                        try Token.new_token(
                            .Return,
                            self.index,
                            self.index + 7,
                        ),
                    );

                    self.index += 7;
                    continue;
                }
            }

            if (c == 'i') {
                const slice = buffer[self.index + 1 .. self.index + 3];
                if (std.mem.eql(u8, slice, "f ")) {
                    try self.tokens.append(
                        try Token.new_token(
                            .If,
                            self.index,
                            self.index + 3,
                        ),
                    );

                    self.index += 3;
                    continue;
                }
            }

            if (c == 'e') {
                const slice = buffer[self.index + 1 .. self.index + 5];
                if (std.mem.eql(u8, slice, "lse ")) {
                    try self.tokens.append(
                        try Token.new_token(
                            .Else,
                            self.index,
                            self.index + 5,
                        ),
                    );

                    self.index += 5;
                    continue;
                }
            }

            if (c == 'f') {
                const slice = buffer[self.index + 1 .. self.index + 4];
                if (std.mem.eql(u8, slice, "or ")) {
                    try self.tokens.append(
                        try Token.new_token(
                            .For,
                            self.index,
                            self.index + 4,
                        ),
                    );

                    self.index += 4;
                    continue;
                }
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

                while (std.ascii.isAlphanumeric(buffer[self.index])) {
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

            // Operators
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

            if (c == '{') {
                try self.tokens.append(
                    try Token.new_token(
                        .LeftBracket,
                        self.index,
                        self.index + 1,
                    ),
                );

                self.index += 1;
                continue;
            }

            if (c == '}') {
                try self.tokens.append(
                    try Token.new_token(
                        .RightBracket,
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
