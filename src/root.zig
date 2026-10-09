//! Library root. Everything that is not tied to the terminal lives here, so
//! it can be unit tested and reused by other Zig projects via `b.dependency`.

pub const cli = @import("cli.zig");
pub const count = @import("commands/count.zig");
pub const greet = @import("commands/greet.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
