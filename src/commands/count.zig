const std = @import("std");
const Io = std.Io;

pub const Options = struct {
    lines: bool = false,
    words: bool = false,
    bytes: bool = false,

    pub const short = .{ .lines = 'l', .words = 'w', .bytes = 'c' };
    pub const help = .{
        .lines = "Print the line count",
        .words = "Print the word count",
        .bytes = "Print the byte count",
    };
};

pub const usage = "count [options] [file...]";
pub const summary = "Count lines, words and bytes (reads stdin when no files are given)";

pub const Counts = struct {
    lines: u64 = 0,
    words: u64 = 0,
    bytes: u64 = 0,

    pub fn add(a: *Counts, b: Counts) void {
        a.lines += b.lines;
        a.words += b.words;
        a.bytes += b.bytes;
    }
};

/// Streams through `r` in fixed-size chunks, so memory use stays constant no
/// matter how large the input is.
pub fn countReader(r: *Io.Reader) Io.Reader.ShortError!Counts {
    var counts: Counts = .{};
    var in_word = false;
    var chunk: [16 * 1024]u8 = undefined;

    while (true) {
        const n = try r.readSliceShort(&chunk);
        if (n == 0) break;
        counts.bytes += n;
        for (chunk[0..n]) |c| {
            if (c == '\n') counts.lines += 1;
            const space = std.ascii.isWhitespace(c);
            if (!space and !in_word) counts.words += 1;
            in_word = !space;
        }
        if (n < chunk.len) break;
    }
    return counts;
}

pub fn writeCounts(w: *Io.Writer, options: Options, counts: Counts, label: ?[]const u8) Io.Writer.Error!void {
    // No flags means "show everything", like `wc`.
    const all = !options.lines and !options.words and !options.bytes;
    if (all or options.lines) try w.print("{d:>8}", .{counts.lines});
    if (all or options.words) try w.print("{d:>8}", .{counts.words});
    if (all or options.bytes) try w.print("{d:>8}", .{counts.bytes});
    if (label) |l| try w.print(" {s}", .{l});
    try w.writeByte('\n');
}

test "counts lines, words and bytes" {
    var r: Io.Reader = .fixed("hello zig\n  fast\tand small \nend");
    const c = try countReader(&r);
    try std.testing.expectEqual(Counts{ .lines = 2, .words = 6, .bytes = 31 }, c);
}

test "empty input" {
    var r: Io.Reader = .fixed("");
    try std.testing.expectEqual(Counts{}, try countReader(&r));
}

test "output respects selected columns" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeCounts(&w, .{ .lines = true }, .{ .lines = 3, .words = 9, .bytes = 40 }, "a.txt");
    try std.testing.expectEqualStrings("       3 a.txt\n", w.buffered());
}
