---
tags:
  - type/cheatsheet
  - area/dev-tools
created: 2026-05-04
status: active
---

# Zig 0.15 → 0.16 Migration Reference

> **Purpose**: Code-level migration guide for moving existing Zig projects from 0.15.x to 0.16.0 ("Juicy Main"), released April 2026.
>
> **Status**: Companion to [[ZIG_RECENT_API_CHANGES]]. Kept separate while transition is in progress; will be merged into the main reference once all projects are on 0.16.
>
> **Adoption strategy (Peter)**: Hold on upgrading until **0.16.1** is released, to let initial regressions shake out. Until then, this doc is a "what to expect" reference, not a "do this now" mandate. As we actually migrate projects, we should add **firsthand notes** to this doc — gotchas the release notes didn't warn us about, error messages whose translation isn't obvious, things that broke in unexpected ways. Look for the 🔥 marker in section bodies for those entries (see "Firsthand notes" below).
>
> **Caveat**: Some code snippets below are illustrative reconstructions from the release notes — verify exact symbol names against the official docs or your compiler's error messages before relying on them. The *direction* of every change is correct; the spelling occasionally is not.
>
> **Sources**:
> - [Zig 0.16.0 Release Notes](https://ziglang.org/download/0.16.0/release-notes.html)
> - [Zig 0.16 Release Notes (Hacker News discussion)](https://news.ycombinator.com/item?id=47767194)
> - [Simon Willison: "Juicy Main"](https://simonwillison.net/2026/Apr/15/juicy-main/)
> - [bytecode.news: Zig 0.16 Released](https://www.bytecode.news/posts/2026/04/zig-0-16-released-major-changes-included)

---

## TL;DR — The Big Three

1. **I/O is now an interface (`std.Io`)** that you thread through the program. `std.fs` largely moves to `std.Io.Dir` / `std.Io.File`. Most file/process/sync APIs grow an `io` parameter.
2. **`main()` accepts a `std.process.Init`** ("Juicy Main") that hands you a pre-built allocator, `io`, args, and environ — kill your boilerplate.
3. **Type reification via `@Type(.{...})` is replaced** by dedicated builtins (`@Int`, `@Struct`, `@Enum`, `@Union`, `@Pointer`, `@Fn`, `@Tuple`).

Everything else (`std.posix` shrinkage, packed-type tightening, vector indexing, build-system C translation) flows from these three.

---

## 🔥 Firsthand notes

Real things that bit us during migrations. Add as we hit them.

### 🔥 nixpkgs `nixos-unstable` already ships Zig 0.16 (2026-05-04)

**What happened**: scaffolding the `jpegz` flake (project targets Zig 0.15.2 per Peter's "wait for 0.16.1" adoption strategy). The flake used `pkgs.zig` from `github:NixOS/nixpkgs/nixos-unstable`. The build failed with:

```
build.zig:23:18: error: no field or member function named 'addStaticLibrary' in 'Build'
/nix/store/.../zig-0.16.0/lib/zig/std/Build.zig:1:1: note: struct declared here
```

The `0.16.0` in the store path is the giveaway — nixpkgs unstable has *already* jumped to 0.16 (locked nixpkgs `lastModified` 2026-05-02-ish), even though the official adoption posture is "wait for 0.16.1".

**Why this is sneaky**: `addStaticLibrary` was *also* removed in late 0.15.x (see [[ZIG_RECENT_API_CHANGES]] §"Build static lib") — same error message either way. Easy to misdiagnose as "I need to update my code for 0.15" when actually you've been silently upgraded to 0.16 by your nixpkgs channel.

**Fix**: pin Zig explicitly via [`mitchellh/zig-overlay`](https://github.com/mitchellh/zig-overlay). It exposes every release as a named attr (`packages.${system}."0.15.2"`, `"0.14.1"`, etc.) and is updated nightly. Pattern:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  zig-overlay = {
    url = "github:mitchellh/zig-overlay";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
# in outputs:
zigPkg = zig-overlay.packages.${system}."0.15.2";
```

**Lesson**: any project that has a documented Zig version target should pin via `zig-overlay`. Don't trust `pkgs.zig` to stay on a particular major.

---

## Table of Contents

1. [I/O Interface (the headline change)](#1-io-interface-the-headline-change)
2. [Juicy Main (`process.Init`)](#2-juicy-main-processinit)
3. [Filesystem: `std.fs` → `std.Io.Dir` / `std.Io.File`](#3-filesystem-stdfs--stdiodir--stdiofile)
4. [Process Spawning & Exec](#4-process-spawning--exec)
5. [Sync Primitives Move to `std.Io`](#5-sync-primitives-move-to-stdio)
6. [Type Reification Builtins](#6-type-reification-builtins)
7. [Packed Types: Tighter Rules](#7-packed-types-tighter-rules)
8. [Explicit Backing Types in Extern Contexts](#8-explicit-backing-types-in-extern-contexts)
9. [Vector Index Restrictions](#9-vector-index-restrictions)
10. [Float ↔ Int Coercion Relaxed](#10-float--int-coercion-relaxed)
11. [`std.posix` Shrinkage](#11-stdposix-shrinkage)
12. [Random/Entropy via `Io`](#12-randomentropy-via-io)
13. [Allocator Changes](#13-allocator-changes)
14. [Build System: C Translation](#14-build-system-c-translation)
15. [Removed I/O Types](#15-removed-io-types)
16. [Signal Handling](#16-signal-handling)
17. [Migration Strategy / Order of Operations](#17-migration-strategy--order-of-operations)
18. [Quick Reference Table](#18-quick-reference-table)

---

## 1. I/O Interface (the headline change)

In 0.16, **I/O is dependency-injected**. You construct an `Io` implementation once and pass it down to anything that touches files, sockets, processes, threads, timers, or the clock. The blocking/threaded implementation (`std.Io.Threaded`) is the drop-in replacement for 0.15's implicit-global behavior.

### Setting up `Io`

```zig
// Single-threaded program — simplest setup
var threaded: std.Io.Threaded = .init_single_threaded;
const io = threaded.io();

// Multi-threaded program
var threaded = try std.Io.Threaded.init(allocator, .{ .thread_count = 4 });
defer threaded.deinit();
const io = threaded.io();
```

If your `main` accepts `std.process.Init` (see §2), you don't need to construct this yourself — `init.io` is already the threaded implementation.

### Reading a file

```zig
// OLD (0.15)
const file = try std.fs.cwd().openFile("data.txt", .{});
defer file.close();
const bytes = try file.readToEndAlloc(allocator, 1 << 20);

// NEW (0.16)
const file = try std.Io.Dir.cwd().openFile(io, "data.txt", .{});
defer file.close(io);
const bytes = try file.readToEndAlloc(io, allocator, 1 << 20);
```

### Writing to stdout

```zig
// OLD (0.15)
var buf: [4096]u8 = undefined;
var w = std.fs.File.stdout().writer(&buf);
const stdout = &w.interface;
try stdout.print("hello {s}\n", .{name});
try stdout.flush();

// NEW (0.16) — io parameter on writer construction
var buf: [4096]u8 = undefined;
var w = std.Io.File.stdout().writer(io, &buf);
const stdout = &w.interface;
try stdout.print("hello {s}\n", .{name});
try stdout.flush(io);
```

### Threading `io` through your code

Treat `io: std.Io` like `allocator: std.mem.Allocator` — accept it as a parameter on every function that does I/O. Don't stash it in a global.

```zig
fn loadConfig(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    return try file.readToEndAlloc(io, allocator, 1 << 16);
}
```

---

## 2. Juicy Main (`process.Init`)

Adding a single parameter to `main` gives you a pre-built `gpa`, `arena`, `io`, args, and environ map. This is the recommended entry point in 0.16.

```zig
// OLD (0.15) — manual setup
pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_w.interface;

    // ... actual work ...
    try stdout.flush();
}

// NEW (0.16) — Juicy Main
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;             // general-purpose allocator
    const arena = init.arena;         // arena, freed at process exit
    const io = init.io;               // default Io (threaded)
    const args = try init.minimal.args.toSlice(arena.allocator());
    const env = init.environ_map;     // std.process.EnvMap

    _ = gpa;
    _ = args;
    _ = env;
    _ = io;
}
```

You can still write `pub fn main() !void` — the old form keeps working. But for any non-trivial program, accept `std.process.Init` and skip the boilerplate.

> **Note**: `std.os.argv` and `std.os.environ` globals are gone. Get args/env from `init` instead.

---

## 3. Filesystem: `std.fs` → `std.Io.Dir` / `std.Io.File`

The `std.fs` module is largely a thin shim over the new I/O-aware types. New code should use `std.Io.Dir` and `std.Io.File` directly.

```zig
// OLD (0.15)
var dir = try std.fs.cwd().openDir("subdir", .{});
defer dir.close();
try std.fs.cwd().makeDir("newdir");
const file = try std.fs.openFileAbsolute("/tmp/x", .{});

// NEW (0.16)
var dir = try std.Io.Dir.cwd().openDir(io, "subdir", .{});
defer dir.close(io);
try std.Io.Dir.cwd().createDir(io, "newdir");          // makeDir → createDir
const file = try std.Io.Dir.openFileAbsolute(io, "/tmp/x", .{});
```

### Stat, perms, paths

```zig
// OLD (0.15)
const stat = try file.stat();
const perm = std.fs.File.default_mode;

// NEW (0.16)
const stat = try file.stat(io);
const perm = std.Io.File.Permissions.default_file;
```

### Removed *Z / *W variants

Most null-terminated (`*Z`) and wide-char (`*W`) variants of filesystem calls are gone. Use the regular slice-taking calls; if you genuinely need the syscall-level form, drop to `std.posix.system`.

---

## 4. Process Spawning & Exec

```zig
// OLD (0.15)
var child = std.process.Child.init(&.{ "ls", "-la" }, allocator);
child.stdout_behavior = .Pipe;
try child.spawn();
const term = try child.wait();

// NEW (0.16)
var child = try std.process.spawn(io, .{
    .argv = &.{ "ls", "-la" },
    .stdout = .pipe,
});
const term = try child.wait(io);
```

### Replacing the current process (execv)

```zig
// OLD (0.15)
return std.process.execv(allocator, &.{ "/bin/sh", "-c", cmd });

// NEW (0.16)
return std.process.replace(io, .{ .argv = &.{ "/bin/sh", "-c", cmd } });
```

---

## 5. Sync Primitives Move to `std.Io`

Locking primitives are now `Io`-aware so they cooperate with future async backends (io_uring, GCD).

```zig
// OLD (0.15)
var mu = std.Thread.Mutex{};
mu.lock();
defer mu.unlock();

var ev = std.Thread.ResetEvent{};
ev.set();
ev.wait();

// NEW (0.16)
var mu: std.Io.Mutex = .{};
try mu.lock(io);
defer mu.unlock(io);

var ev: std.Io.Event = .{};
ev.set();
try ev.wait(io);
```

Also affected: `std.Thread.Semaphore` → `std.Io.Semaphore`, `std.Thread.RwLock` → `std.Io.RwLock`. **`std.once` is removed** — hand-roll a guarded init or restructure to avoid it.

---

## 6. Type Reification Builtins

`@Type(.{...})` with massive struct literals is replaced by purpose-built builtins. The old form still compiles in many cases but error messages and idioms now favor the new builtins.

```zig
// OLD (0.15)
const U10 = @Type(.{ .int = .{ .signedness = .unsigned, .bits = 10 } });
const Pair = @Type(.{ .@"struct" = .{
    .layout = .auto,
    .fields = &.{ /* ...verbose... */ },
    .decls = &.{},
    .is_tuple = true,
} });

// NEW (0.16)
const U10 = @Int(.unsigned, 10);
const Pair = @Tuple(&.{ u32, f64 });

// Other new builtins:
const P = @Pointer(.one, .{ .@"const" = true }, u32, null);
const F = @Fn(&.{ f64 }, &.{ .{} }, u32, .{});
const S = @Struct(.auto, null, &.{ "x", "y" }, &.{ u32, u32 }, &@splat(.{}));
const E = @Enum(u32, .exhaustive, &.{ "foo", "bar" }, &.{ 0, 1 });
const N = @Union(.auto, TagType, &.{ "a", "b" }, &.{ i64, f64 }, &@splat(.{}));
```

---

## 7. Packed Types: Tighter Rules

### No pointers in packed types

```zig
// OLD (0.15) — allowed
const S = packed struct {
    flags: u32,
    target: *u32,
};

// NEW (0.16) — store as integer, convert at use site
const S = packed struct {
    flags: u32,
    target: usize,  // use @ptrFromInt / @intFromPtr
};
```

### Packed unions need an explicit backing type

```zig
// OLD (0.15)
const U = packed union {
    a: u8,
    b: u16,
};

// NEW (0.16) — backing type required to disambiguate layout
const U = packed union(u16) {
    a: packed struct(u16) { v: u8, _pad: u8 = 0 },
    b: u16,
};
```

---

## 8. Explicit Backing Types in Extern Contexts

The ABI of an enum/packed struct/packed union can no longer be inferred implicitly when the type crosses an `extern` or `export` boundary. You must spell out the integer backing.

```zig
// OLD (0.15) — implicit backing inferred
const Op = enum { read, write, sync };
export var current_op: Op = .read;

// NEW (0.16) — explicit
const Op = enum(u8) { read, write, sync };
export var current_op: Op = .read;
```

Same rule applies to `packed struct(uN) { ... }` and `packed union(uN) { ... }` when used in extern signatures.

> **Why**: `u8` and `i8` can have different ABIs in some contexts; relying on implicit choice was a footgun. Be explicit.

---

## 9. Vector Index Restrictions

Runtime indexing into a `@Vector(...)` is no longer allowed. Coerce to an array first.

```zig
// OLD (0.15)
const v: @Vector(4, i32) = .{ 1, 2, 3, 4 };
for (0..4) |i| {
    sum += v[i];  // runtime index on vector — gone in 0.16
}

// NEW (0.16)
const v: @Vector(4, i32) = .{ 1, 2, 3, 4 };
const arr: [4]i32 = v;
for (arr) |x| sum += x;
```

Compile-time indexing (`v[0]`, `v[comptime_known]`) still works.

---

## 10. Float ↔ Int Coercion Relaxed

Small integers that fit in the float's mantissa now coerce implicitly. Larger ones still need `@floatFromInt`.

```zig
const small: u24 = 12345;
const f: f32 = small;            // OK in 0.16 (24 bits ≤ f32 mantissa of 24)

const big: u25 = 12345;
const g: f32 = @floatFromInt(big);  // still required
```

Float → int conversion via rounding builtins skips the `@intFromFloat` step:

```zig
// OLD (0.15)
const n: u8 = @intFromFloat(@round(x));

// NEW (0.16)
const n: u8 = @round(x);   // @trunc / @floor / @ceil also do the conversion
```

---

## 11. `std.posix` Shrinkage

`std.posix` was a medium-level abstraction. In 0.16 most of it is gone — go **higher** (use `std.Io`) or **lower** (use `std.posix.system` for raw syscalls).

| Removed from `std.posix` | Replacement |
|---|---|
| `getrandom` | `io.random(buf)` (or `io.randomSecure` for fresh entropy) |
| `mmap` / `munmap` | `std.posix.system.mmap` directly |
| `prctl` / `fcntl` / `ioctl` | `std.posix.system.*` directly |
| Most blocking I/O wrappers | `std.Io.File` / `std.Io.Dir` |

---

## 12. Random/Entropy via `Io`

```zig
// OLD (0.15)
var buf: [32]u8 = undefined;
std.crypto.random.bytes(&buf);

// NEW (0.16) — pseudo-random from io
var buf: [32]u8 = undefined;
io.random(&buf);

// NEW (0.16) — cryptographically fresh, may fail
io.randomSecure(&buf) catch |err| switch (err) {
    error.EntropyUnavailable => return err,
};
```

---

## 13. Allocator Changes

- `std.heap.ArenaAllocator` is now **lock-free and thread-safe** out of the box.
- `std.heap.ThreadSafeAllocator` (the wrapper) is **removed** — you don't need it; the underlying allocators are MT-safe.

```zig
// OLD (0.15) — wrap for multi-threaded use
var tsa = std.heap.ThreadSafeAllocator{ .child_allocator = backing };
const allocator = tsa.allocator();

// NEW (0.16) — just use it
const allocator = backing;  // already safe
```

`ArrayList` keeps the unmanaged-by-default behavior introduced in 0.15 — see [[ZIG_RECENT_API_CHANGES]] §1.

---

## 14. Build System: C Translation

`@cImport` in source files is **deprecated** in favor of `b.addTranslateC` in `build.zig`.

```zig
// OLD (0.15) — in source
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("math.h");
});

// NEW (0.16) — in build.zig
const translate_c = b.addTranslateC(.{
    .root_source_file = b.path("src/c_imports.h"),
    .target = target,
    .optimize = optimize,
});
translate_c.linkSystemLibrary("m", .{});

const exe = b.addExecutable(.{
    .name = "myapp",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = translate_c.createModule() },
        },
    }),
});
```

Then in `main.zig`:

```zig
const c = @import("c");  // not @cImport anymore
```

`c_imports.h` is just a header that `#include`s everything you want exposed.

---

## 15. Removed I/O Types

These were already on the way out in 0.15; they're **fully gone** in 0.16:

- `std.io.GenericReader`
- `std.io.AnyReader`
- `std.io.FixedBufferStream`
- `std.io.CountingReader`

Use `std.Io.Reader` / `std.Io.Writer` interfaces directly, or build small structs that present those interfaces.

---

## 16. Signal Handling

POSIX signal handling via `std.posix.Sigaction` still works the same as in 0.15 (see [[ZIG_RECENT_API_CHANGES]] §11) — `std.posix.system` is preserved for the syscall-level pieces. Anything you wrote against `posix.Sigaction` in 0.15 should keep compiling.

The only nuance: write-from-signal-handler uses `std.posix.system.write` (raw syscall) since `std.posix.write` may have been pruned. Check first; fall back to `system.write` if your code stops compiling.

---

## 17. Migration Strategy / Order of Operations

Suggested sequence when porting an existing 0.15 project:

1. **Bump compiler & rebuild** to see the error wall. Don't fix yet — read everything.
2. **Add Juicy Main first.** Replace your `main()` boilerplate with `pub fn main(init: std.process.Init) !void`. This gives you a canonical `io` to thread.
3. **Plumb `io` downward.** Add `io: std.Io` parameter to every function that does I/O, mirroring how `allocator` flows.
4. **Migrate filesystem calls** (`std.fs.*` → `std.Io.Dir.*` / `std.Io.File.*`). Most errors will be "missing first arg" — that's `io`.
5. **Migrate process & sync calls** (`std.process.Child` → `std.process.spawn`, `Thread.Mutex` → `Io.Mutex`, etc.).
6. **Fix type-system errors** (explicit enum backings, vector indexing, packed-type pointers).
7. **Move `@cImport` to `addTranslateC` in `build.zig`** — last, since it's the most invasive structural change.
8. **Run tests.** A successful build is not a successful migration; the I/O semantics differ subtly under `Io.Threaded`.
9. **Benchmark before & after.** Capture a baseline on 0.15 *before* you start the migration (commit the numbers), then re-run the same benchmarks on 0.16 with `Io.Threaded`. The 0.16 release tightened several codegen paths and the new I/O design can win or lose depending on workload — you want hard numbers, not vibes. If you have the [[zig-microbenchmarks]] skill set up on a project, that's the easiest way; otherwise even a simple `hyperfine` against a representative workload is enough to spot regressions or wins. Save the comparison in the project's perf log.

Don't try to do all of this at once. Get to a successful build with `Io.Threaded` (which mimics 0.15 behavior), commit, then think about whether any of the new async backends (`Io.Evented`, io_uring, GCD) make sense for your project.

---

## 18. Quick Reference Table

| 0.15 | 0.16 |
|---|---|
| `pub fn main() !void` + manual setup | `pub fn main(init: std.process.Init) !void` |
| `std.fs.cwd().openFile(path, .{})` | `std.Io.Dir.cwd().openFile(io, path, .{})` |
| `file.close()` | `file.close(io)` |
| `file.readToEndAlloc(alloc, max)` | `file.readToEndAlloc(io, alloc, max)` |
| `file.stat()` | `file.stat(io)` |
| `std.fs.cwd().makeDir("x")` | `std.Io.Dir.cwd().createDir(io, "x")` |
| `std.fs.File.stdout().writer(&buf)` | `std.Io.File.stdout().writer(io, &buf)` |
| `std.process.Child.init(...).spawn()` | `std.process.spawn(io, .{...})` |
| `std.process.execv(alloc, argv)` | `std.process.replace(io, .{ .argv = argv })` |
| `std.process.argsAlloc(alloc)` | `init.minimal.args.toSlice(arena.allocator())` |
| `std.os.argv` / `std.os.environ` | `init.minimal.args` / `init.environ_map` |
| `std.Thread.Mutex{}` | `std.Io.Mutex{}` + `lock(io)` / `unlock(io)` |
| `std.Thread.ResetEvent{}` | `std.Io.Event{}` + `wait(io)` |
| `std.crypto.random.bytes(&buf)` | `io.random(&buf)` / `io.randomSecure(&buf)` |
| `std.heap.ThreadSafeAllocator` | (removed — base allocators are MT-safe) |
| `@Type(.{ .int = .{...} })` | `@Int(.unsigned, N)` |
| `@Type(.{ .@"struct" = .{...} })` | `@Struct(...)` / `@Tuple(...)` |
| `enum { a, b }` (in extern) | `enum(u8) { a, b }` |
| `packed union { ... }` | `packed union(uN) { ... }` |
| `*T` field in packed struct | `usize` field + `@ptrFromInt`/`@intFromPtr` |
| Runtime `vec[i]` | `const arr: [N]T = vec; arr[i]` |
| `@cImport({ @cInclude("h.h"); })` | `b.addTranslateC(...)` in `build.zig` |
| `std.io.GenericReader` / `AnyReader` / `FixedBufferStream` | (removed — use `std.Io.Reader`) |
| `std.posix.getrandom(...)` | `io.random(...)` or `std.posix.system.getrandom(...)` |
| `std.once` | (removed — hand-roll) |

---

## Common Pitfalls

1. **Forgetting `io` on `close`/`flush`.** The compiler error is usually "expected 1 argument, found 0" at the call site. Add `io`.
2. **Stashing `io` in a global.** Don't. Pass it as a parameter, the same way you pass `allocator`. Globals defeat the whole point of the dependency injection.
3. **Mixing `std.fs` and `std.Io.Dir` in the same program.** They're not interchangeable; pick one (use `std.Io.Dir` for new code).
4. **Assuming `Io.Threaded` is async.** It's the blocking-with-threads implementation — semantically identical to 0.15. Real async backends (`Io.Evented` with io_uring or GCD) are opt-in.
5. **Implicit enum/packed backings in `extern` signatures.** You'll get an ABI-determination error. Add the explicit `(uN)` backing.
6. **Lingering `@cImport` in source.** Move it to `build.zig`. Source-level `@cImport` may still work but is on its way out.

---

*Last updated: 2026-05-04*
*Zig version: 0.16.0 ("Juicy Main")*

## See Also
- [[ZIG_RECENT_API_CHANGES]] — current 0.15.x reference (still applicable for projects not yet migrated)
- [[jj_cheatsheet]]
- [[RULES]]
