const std = @import("std");
const Io = std.Io;

pub const Options = struct {
    times: u8 = 1,
    shout: bool = false,
    greeting: []const u8 = "Hello",

    pub const short = .{ .times = 'n', .shout = 's', .greeting = 'g' };
    pub const help = .{
        .times = "How many times to greet",
        .shout = "SHOUT IT",
        .greeting = "The greeting to use",
    };
};

pub const usage = "greet [options] [name...]";
pub const summary = "Greet one or more people";

pub fn run(w: *Io.Writer, options: Options, names: []const []const u8) Io.Writer.Error!void {
    const default_names: []const []const u8 = &.{"world"};
    const targets = if (names.len == 0) default_names else names;

    for (0..options.times) |_| {
        for (targets) |name| {
            try writeMaybeUpper(w, options.greeting, options.shout);
            try w.writeAll(", ");
            try writeMaybeUpper(w, name, options.shout);
            try w.writeAll(if (options.shout) "!\n" else ".\n");
        }
    }
}

fn writeMaybeUpper(w: *Io.Writer, s: []const u8, upper: bool) Io.Writer.Error!void {
    if (!upper) return w.writeAll(s);
    for (s) |c| try w.writeByte(std.ascii.toUpper(c));
}

test "greets the world by default" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try run(&w, .{}, &.{});
    try std.testing.expectEqualStrings("Hello, world.\n", w.buffered());
}

test "shouts repeatedly at several people" {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try run(&w, .{ .times = 2, .shout = true, .greeting = "hi" }, &.{ "ada", "zig" });
    try std.testing.expectEqualStrings("HI, ADA!\nHI, ZIG!\nHI, ADA!\nHI, ZIG!\n", w.buffered());
}
