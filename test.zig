pub fn main() !void {
    @call(.always_inline, foo, .{});
}

fn foo() void {
    foo();
}
