const std = @import("std");
const zon = @import("build.zig.zon");

/// Targets built by `zig build release`. Zig cross-compiles all of them from
/// any host, no extra toolchains needed.
const release_targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .aarch64, .os_tag = .windows },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);

    // The reusable library: argument parser and command logic.
    const mod = b.addModule("zcli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = addExe(b, mod, options, target, optimize);
    b.installArtifact(exe);

    // zig build run -- <args>
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    // zig build test
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod })).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);

    // zig build release: small, optimized binaries for every platform in zig-out/release/<target>/
    const release_step = b.step("release", "Cross-compile release binaries for all platforms");
    for (release_targets) |query| {
        const resolved = b.resolveTargetQuery(query);
        const release_mod = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = resolved,
        });
        const release_exe = addExe(b, release_mod, options, resolved, .ReleaseSmall);
        release_exe.root_module.strip = true;
        const install = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("release/{s}", .{query.zigTriple(b.allocator) catch @panic("OOM")}) } },
        });
        release_step.dependOn(&install.step);
    }
}

fn addExe(
    b: *std.Build,
    mod: *std.Build.Module,
    options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zcli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcli", .module = mod },
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });
}
