const std = @import("std");
const Io = std.Io;
const zcli = @import("zcli");
const build_options = @import("build_options");

const cli = zcli.cli;
const count = zcli.count;
const greet = zcli.greet;

const name = "zcli";

/// Add a command: write a module in `src/commands/` with `Options`, `usage`,
/// `summary` and a `run` function, then list it here and in `dispatch`.
const Command = enum { greet, count };

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = Io.File.stderr().writerStreaming(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    const color = init.environ_map.get("NO_COLOR") == null and
        (Io.File.stderr().isTty(io) catch false);
    const out: Output = .{ .stdout = stdout, .stderr = stderr, .color = color };

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        try writeUsage(stderr);
        return 2;
    }

    const first = args[1];
    if (eql(first, "-h") or eql(first, "--help") or eql(first, "help")) {
        try writeUsage(stdout);
        return 0;
    }
    if (eql(first, "-V") or eql(first, "--version") or eql(first, "version")) {
        try stdout.print("{s} {s}\n", .{ name, build_options.version });
        return 0;
    }

    const command = std.meta.stringToEnum(Command, first) orelse {
        try out.fail("unknown command '{s}'", .{first});
        try stderr.print("Run '{s} --help' to see all commands.\n", .{name});
        return 2;
    };

    return dispatch(command, arena, io, out, args[2..]);
}

fn dispatch(command: Command, arena: std.mem.Allocator, io: Io, out: Output, args: []const []const u8) !u8 {
    switch (command) {
        inline else => |tag| {
            const Module = switch (tag) {
                .greet => greet,
                .count => count,
            };

            var diag: cli.Diagnostic = .{};
            const parsed = cli.parse(Module.Options, arena, args, &diag) catch |err| {
                try out.failPrefix();
                try diag.report(err, out.stderr);
                try out.stderr.print("Run '{s} {s} --help' for usage.\n", .{ name, @tagName(tag) });
                return 2;
            };

            if (parsed.help) {
                try out.stdout.print("{s}\n\nUsage: {s} {s}\n\n", .{ Module.summary, name, Module.usage });
                try cli.writeOptions(Module.Options, out.stdout);
                return 0;
            }

            return switch (tag) {
                .greet => {
                    try greet.run(out.stdout, parsed.options, parsed.positionals);
                    return 0;
                },
                .count => runCount(io, out, parsed.options, parsed.positionals),
            };
        },
    }
}

fn runCount(io: Io, out: Output, options: count.Options, paths: []const []const u8) !u8 {
    var buffer: [64 * 1024]u8 = undefined;

    if (paths.len == 0) {
        var stdin = Io.File.stdin().readerStreaming(io, &buffer);
        const counts = try count.countReader(&stdin.interface);
        try count.writeCounts(out.stdout, options, counts, null);
        return 0;
    }

    var total: count.Counts = .{};
    var status: u8 = 0;
    for (paths) |path| {
        const file = Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
            try out.fail("{s}: {s}", .{ path, @errorName(err) });
            status = 1;
            continue;
        };
        defer file.close(io);

        var reader = file.reader(io, &buffer);
        const counts = try count.countReader(&reader.interface);
        try count.writeCounts(out.stdout, options, counts, path);
        total.add(counts);
    }
    if (paths.len > 1) try count.writeCounts(out.stdout, options, total, "total");
    return status;
}

fn writeUsage(w: *Io.Writer) Io.Writer.Error!void {
    try w.print(
        \\{s} {s}: a starter CLI written in Zig
        \\
        \\Usage: {s} <command> [options]
        \\
        \\Commands:
        \\
    , .{ name, build_options.version, name });
    inline for (.{ greet, count }) |Module| {
        const cmd = comptime Module.usage[0..std.mem.indexOfScalar(u8, Module.usage, ' ').?];
        try w.print("  {s}", .{cmd});
        try w.splatByteAll(' ', 10 - cmd.len);
        try w.print("{s}\n", .{Module.summary});
    }
    try w.print(
        \\
        \\Global options:
        \\  -h, --help      Show help (also works after a command)
        \\  -V, --version   Show version
        \\
    , .{});
}

const Output = struct {
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    color: bool,

    fn failPrefix(o: Output) Io.Writer.Error!void {
        try o.stderr.writeAll(if (o.color) "\x1b[1;31merror:\x1b[0m " else "error: ");
    }

    fn fail(o: Output, comptime fmt: []const u8, args: anytype) Io.Writer.Error!void {
        try o.failPrefix();
        try o.stderr.print(fmt ++ "\n", args);
    }
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
