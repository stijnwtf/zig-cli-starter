<div align="center">
  <h1>⚡ zig-cli-starter</h1>
  <p><strong>A batteries-included template for command-line tools in Zig 0.17.</strong><br/>
  Subcommands, a comptime argument parser, tests, and one-tag releases for 6 platforms. Zero dependencies.</p>

  <p>
    <a href="https://github.com/stijnwtf/zig-cli-starter/actions/workflows/ci.yml"><img src="https://github.com/stijnwtf/zig-cli-starter/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
    <a href="https://ziglang.org/download/"><img src="https://img.shields.io/badge/zig-0.17.0-f7a41d" alt="Zig 0.17.0" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/stijnwtf/zig-cli-starter" alt="MIT license" /></a>
    <a href="https://github.com/stijnwtf/zig-cli-starter/stargazers"><img src="https://img.shields.io/github/stars/stijnwtf/zig-cli-starter?style=social" alt="GitHub stars" /></a>
  </p>
</div>

```console
$ zcli greet Ada Linus --shout -n 2
HELLO, ADA!
HELLO, LINUS!
HELLO, ADA!
HELLO, LINUS!

$ zcli count build.zig src/main.zig
      79     312    3016 build.zig
     162     588    5311 src/main.zig
     241     900    8327 total
```

## Why

Zig changes fast. Every release reshuffles the standard library (0.17 brought the new `std.Io` interface, `std.process.Init` and reworked reflection), so most CLI templates you find no longer compile. This one targets **Zig 0.17.0** and is kept up to date by CI.

## What's inside

| | |
| --- | --- |
| 🧠 **Comptime argument parser** | Describe options as a plain struct. Flags, short aliases, defaults, enums, required fields and `--help` text are generated at compile time. ~300 lines, no dependencies. |
| 🧩 **Subcommands** | `greet` and `count` as examples: one file per command in `src/commands/`. |
| 🌊 **Modern `std.Io`** | Buffered streaming writers, readers that work on files *and* stdin with constant memory. |
| 🎨 **Friendly errors** | Precise messages (`invalid value 'lots' for '--times'`), red `error:` on a TTY, respects `NO_COLOR`, proper exit codes. |
| 🧪 **Tests** | Every module has unit tests, run with `zig build test`. Commands write to any `*Io.Writer`, so they're tested against in-memory buffers. |
| 📦 **Cross-compilation** | `zig build release` produces stripped binaries (~150 KB) for Linux, macOS and Windows on x86_64 and arm64, from any machine. |
| 🚀 **One-tag releases** | Push `v1.2.3` and GitHub Actions builds, packages, checksums and publishes a GitHub Release. |
| 🤖 **CI** | `zig fmt` check and tests on Linux, macOS and Windows. |

## Quick start

Click **[Use this template](https://github.com/stijnwtf/zig-cli-starter/generate)**, or:

```bash
git clone https://github.com/stijnwtf/zig-cli-starter my-tool
cd my-tool
zig build run -- greet --help
```

Requires [Zig 0.17.0](https://ziglang.org/download/) (`brew install zig`, or use [zvm](https://github.com/tristanisham/zvm) / [anyzig](https://github.com/marler8997/anyzig)).

## Commands

| Command | Does |
| --- | --- |
| `zig build` | Debug build to `zig-out/bin/zcli` |
| `zig build run -- <args>` | Build and run |
| `zig build test` | Run all unit tests |
| `zig build -Doptimize=ReleaseFast` | Optimized build for your machine |
| `zig build release` | Cross-compile all 6 targets into `zig-out/release/` |
| `zig fmt src build.zig` | Format |

## The argument parser

```zig
pub const Options = struct {
    times: u8 = 1,                       // --times <int>, default 1
    shout: bool = false,                 // --shout
    greeting: []const u8 = "Hello",      // --greeting <str>
    style: enum { plain, fancy } = .plain, // --style <plain|fancy>
    output: ?[]const u8 = null,          // optional
    path: []const u8,                    // no default: required

    pub const short = .{ .times = 'n', .shout = 's' };
    pub const help = .{ .times = "How many times to greet", .shout = "SHOUT IT" };
};

var diag: cli.Diagnostic = .{};
const parsed = try cli.parse(Options, arena, args, &diag);
// parsed.options.times, parsed.positionals, parsed.help
```

Supports `--flag value`, `--flag=value`, `-n 3`, `--dry-run` for `dry_run`, `--` to stop parsing, and `--help` anywhere. Failures fill in `diag` so you can print exactly what was wrong.

## Project structure

```
build.zig           build, test, run and release steps
build.zig.zon       package name and version (shown by --version)
src/
├── main.zig        entry point: dispatch, I/O setup, errors, exit codes
├── root.zig        library root, reusable from other Zig projects
├── cli.zig         comptime argument parser
└── commands/
    ├── greet.zig
    └── count.zig
```

## Make it yours

1. Rename `zcli` in `build.zig`, `build.zig.zon` and `src/main.zig` (the `name` constant).
2. Run `zig build`. Zig will tell you the new `fingerprint` to put in `build.zig.zon`.
3. Add a command: create `src/commands/foo.zig` with `Options`, `usage`, `summary` and a `run` function, then add it to the `Command` enum and `dispatch` in `src/main.zig`. The compiler points out every place you missed.

## Releasing

```bash
# bump .version in build.zig.zon to 0.2.0, commit, then:
git tag v0.2.0
git push origin v0.2.0
```

The release workflow checks the tag matches `build.zig.zon`, runs the tests and publishes `.tar.gz` / `.zip` archives plus `checksums.txt`.

## Contributing

Issues and PRs welcome, especially when a new Zig release breaks something. Run `zig fmt --check src build.zig && zig build test` first.

If this saved you from fighting the build system, a ⭐️ helps other people find it.

## License

[MIT](LICENSE)
