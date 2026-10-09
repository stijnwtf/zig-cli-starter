//! A tiny, dependency-free argument parser driven by comptime reflection.
//!
//! Describe your options as a plain struct. Every field becomes a `--flag`
//! (underscores turn into dashes), its default value becomes the flag's
//! default, and the parser plus the `--help` text are generated at compile
//! time:
//!
//!     const Options = struct {
//!         times: u8 = 1,
//!         shout: bool = false,
//!         name: ?[]const u8 = null,
//!
//!         pub const short = .{ .times = 'n', .shout = 's' };
//!         pub const help = .{ .times = "How often to repeat", .shout = "Use capitals" };
//!     };
//!
//! Supported field types: `bool`, integers, floats, enums, `[]const u8`,
//! and optionals of those. Fields without a default are required.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Error = error{
    UnknownFlag,
    MissingValue,
    InvalidValue,
    MissingRequired,
    UnexpectedValue,
} || Allocator.Error;

/// Filled in when `parse` fails, so the caller can print a precise message.
pub const Diagnostic = struct {
    arg: []const u8 = "",
    flag: []const u8 = "",

    pub fn report(d: Diagnostic, err: Error, w: *Io.Writer) Io.Writer.Error!void {
        switch (err) {
            error.UnknownFlag => try w.print("unknown option '{s}'\n", .{d.arg}),
            error.MissingValue => try w.print("option '--{s}' needs a value\n", .{d.flag}),
            error.InvalidValue => try w.print("invalid value '{s}' for '--{s}'\n", .{ d.arg, d.flag }),
            error.MissingRequired => try w.print("missing required option '--{s}'\n", .{d.flag}),
            error.UnexpectedValue => try w.print("option '--{s}' does not take a value\n", .{d.flag}),
            error.OutOfMemory => try w.writeAll("out of memory\n"),
        }
    }
};

pub fn Parsed(comptime Options: type) type {
    return struct {
        options: Options,
        /// Arguments that are not flags, in order. Everything after `--` lands here too.
        positionals: []const []const u8,
        /// `-h` or `--help` was passed.
        help: bool,
    };
}

/// Parse `args` (without the program and command name) into `Options`.
/// `positionals` is allocated with `gpa`; an arena is the easiest choice.
pub fn parse(
    comptime Options: type,
    gpa: Allocator,
    args: []const []const u8,
    diag: *Diagnostic,
) Error!Parsed(Options) {
    const info = @typeInfo(Options).@"struct";

    var options: Options = undefined;
    var seen: [info.field_names.len]bool = @splat(false);
    var positionals: std.ArrayList([]const u8) = .empty;
    var help = false;

    inline for (info.field_names, info.field_types, info.field_attrs) |name, T, attrs| {
        if (attrs.defaultValue(T)) |default| @field(options, name) = default;
    }

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--")) {
            try positionals.appendSlice(gpa, args[i + 1 ..]);
            break;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            help = true;
            continue;
        }

        // Split `--name=value` and resolve `-x` short aliases to a field name.
        var key: []const u8 = undefined;
        var inline_value: ?[]const u8 = null;
        if (std.mem.startsWith(u8, arg, "--")) {
            const body = arg[2..];
            if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
                key = body[0..eq];
                inline_value = body[eq + 1 ..];
            } else key = body;
        } else if (arg.len == 2 and arg[0] == '-' and arg[1] != '-') {
            key = shortToFlag(Options, arg[1]) orelse {
                diag.* = .{ .arg = arg };
                return error.UnknownFlag;
            };
        } else {
            try positionals.append(gpa, arg);
            continue;
        }

        const matched = inline for (info.field_names, info.field_types, 0..) |name, T, field_index| {
            if (std.mem.eql(u8, key, comptime flagName(name))) {
                diag.flag = comptime flagName(name);
                seen[field_index] = true;
                if (Unwrapped(T) == bool) {
                    if (inline_value) |v| {
                        @field(options, name) = parseBool(v) orelse {
                            diag.arg = v;
                            return error.InvalidValue;
                        };
                    } else @field(options, name) = true;
                } else {
                    const value = inline_value orelse blk: {
                        i += 1;
                        if (i >= args.len) return error.MissingValue;
                        break :blk args[i];
                    };
                    diag.arg = value;
                    @field(options, name) = try parseValue(T, value);
                }
                break true;
            }
        } else false;

        if (!matched) {
            diag.* = .{ .arg = arg };
            return error.UnknownFlag;
        }
    }

    if (!help) {
        inline for (info.field_names, info.field_types, info.field_attrs, 0..) |name, T, attrs, field_index| {
            if (attrs.defaultValue(T) == null and !seen[field_index]) {
                diag.flag = comptime flagName(name);
                return error.MissingRequired;
            }
        }
    }

    return .{
        .options = options,
        .positionals = try positionals.toOwnedSlice(gpa),
        .help = help,
    };
}

/// Write an aligned options table for `Options`, used by `--help`.
pub fn writeOptions(comptime Options: type, w: *Io.Writer) Io.Writer.Error!void {
    const info = @typeInfo(Options).@"struct";

    try w.writeAll("Options:\n");
    inline for (info.field_names, info.field_types, info.field_attrs) |name, T, attrs| {
        const short: ?u8 = if (@hasDecl(Options, "short") and @hasField(@TypeOf(Options.short), name))
            @field(Options.short, name)
        else
            null;
        const description: []const u8 = if (@hasDecl(Options, "help") and @hasField(@TypeOf(Options.help), name))
            @field(Options.help, name)
        else
            "";

        if (short) |s| try w.print("  -{c}, ", .{s}) else try w.writeAll("      ");
        const flag = comptime flagName(name) ++ valueHint(T);
        try w.print("--{s}", .{flag});
        try w.splatByteAll(' ', 24 -| flag.len);
        try w.writeAll(description);
        if (attrs.defaultValue(T)) |default| {
            if (comptime Unwrapped(T) != bool and @typeInfo(T) != .optional) {
                try w.writeAll(" (default: ");
                try writeValue(T, default, w);
                try w.writeAll(")");
            }
        } else try w.writeAll(" (required)");
        try w.writeByte('\n');
    }
    try w.writeAll("  -h, --help                    Show this help\n");
}

// HELPERS ---------------------------------------------------------------------

fn flagName(comptime name: []const u8) []const u8 {
    comptime {
        var out: [name.len]u8 = undefined;
        for (name, 0..) |c, idx| out[idx] = if (c == '_') '-' else c;
        const final = out;
        return &final;
    }
}

fn shortToFlag(comptime Options: type, c: u8) ?[]const u8 {
    if (!@hasDecl(Options, "short")) return null;
    const shorts = Options.short;
    inline for (@typeInfo(@TypeOf(shorts)).@"struct".field_names) |name| {
        if (@field(shorts, name) == c) return comptime flagName(name);
    }
    return null;
}

fn Unwrapped(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |o| o.child,
        else => T,
    };
}

fn valueHint(comptime T: type) []const u8 {
    const U = Unwrapped(T);
    return switch (@typeInfo(U)) {
        .bool => "",
        .int => " <int>",
        .float => " <num>",
        .@"enum" => " <" ++ enumChoices(U) ++ ">",
        else => " <str>",
    };
}

fn enumChoices(comptime E: type) []const u8 {
    comptime {
        var out: []const u8 = "";
        for (@typeInfo(E).@"enum".field_names, 0..) |name, idx| {
            out = out ++ (if (idx == 0) "" else "|") ++ name;
        }
        return out;
    }
}

fn parseBool(s: []const u8) ?bool {
    if (std.mem.eql(u8, s, "true")) return true;
    if (std.mem.eql(u8, s, "false")) return false;
    return null;
}

fn parseValue(comptime T: type, s: []const u8) Error!T {
    const U = Unwrapped(T);
    return switch (@typeInfo(U)) {
        .int => std.fmt.parseInt(U, s, 10) catch error.InvalidValue,
        .float => std.fmt.parseFloat(U, s) catch error.InvalidValue,
        .@"enum" => std.meta.stringToEnum(U, s) orelse error.InvalidValue,
        .pointer => s,
        else => @compileError("unsupported option type: " ++ @typeName(T)),
    };
}

fn writeValue(comptime T: type, value: T, w: *Io.Writer) Io.Writer.Error!void {
    switch (@typeInfo(T)) {
        .@"enum" => try w.writeAll(@tagName(value)),
        .pointer => try w.print("\"{s}\"", .{value}),
        else => try w.print("{any}", .{value}),
    }
}

// TESTS -----------------------------------------------------------------------

const testing = std.testing;

const TestOptions = struct {
    times: u8 = 1,
    shout: bool = false,
    dry_run: bool = false,
    style: enum { plain, fancy } = .plain,
    name: ?[]const u8 = null,

    pub const short = .{ .times = 'n', .shout = 's' };
    pub const help = .{ .times = "Repeat count", .shout = "Use capitals" };
};

fn parseTest(args: []const []const u8) !Parsed(TestOptions) {
    var diag: Diagnostic = .{};
    return parse(TestOptions, testing.allocator, args, &diag);
}

test "defaults" {
    const p = try parseTest(&.{});
    defer testing.allocator.free(p.positionals);
    try testing.expectEqual(1, p.options.times);
    try testing.expectEqual(false, p.options.shout);
    try testing.expectEqual(null, p.options.name);
}

test "long, short, inline and dashed flags" {
    const p = try parseTest(&.{ "--times", "3", "-s", "--name=Zig", "--dry-run", "--style", "fancy", "file.txt" });
    defer testing.allocator.free(p.positionals);
    try testing.expectEqual(3, p.options.times);
    try testing.expect(p.options.shout);
    try testing.expect(p.options.dry_run);
    try testing.expectEqual(.fancy, p.options.style);
    try testing.expectEqualStrings("Zig", p.options.name.?);
    try testing.expectEqual(1, p.positionals.len);
    try testing.expectEqualStrings("file.txt", p.positionals[0]);
}

test "double dash stops flag parsing" {
    const p = try parseTest(&.{ "--", "--shout", "-n" });
    defer testing.allocator.free(p.positionals);
    try testing.expect(!p.options.shout);
    try testing.expectEqual(2, p.positionals.len);
}

test "errors carry a diagnostic" {
    var diag: Diagnostic = .{};
    try testing.expectError(error.UnknownFlag, parse(TestOptions, testing.allocator, &.{"--nope"}, &diag));
    try testing.expectEqualStrings("--nope", diag.arg);

    try testing.expectError(error.InvalidValue, parse(TestOptions, testing.allocator, &.{ "-n", "lots" }, &diag));
    try testing.expectEqualStrings("lots", diag.arg);

    try testing.expectError(error.MissingValue, parse(TestOptions, testing.allocator, &.{"--times"}, &diag));
    try testing.expectError(error.InvalidValue, parse(TestOptions, testing.allocator, &.{ "--style", "weird" }, &diag));
}

test "required fields" {
    const Required = struct { path: []const u8 };
    var diag: Diagnostic = .{};
    try testing.expectError(error.MissingRequired, parse(Required, testing.allocator, &.{}, &diag));
    try testing.expectEqualStrings("path", diag.flag);
}

test "help output lists every option" {
    var buf: [1024]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeOptions(TestOptions, &w);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "-n, --times <int>") != null);
    try testing.expect(std.mem.indexOf(u8, out, "--dry-run") != null);
    try testing.expect(std.mem.indexOf(u8, out, "<plain|fancy>") != null);
    try testing.expect(std.mem.indexOf(u8, out, "(default: 1)") != null);
}
