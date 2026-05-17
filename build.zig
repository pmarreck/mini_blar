const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Optimization mode (default: ReleaseFast)",
    ) orelse .ReleaseFast;

    const blip_dep = b.dependency("blip", .{
        .target = target,
        .optimize = optimize,
    });

    // build_options — mini_blar's profile pins enable_compression=false.
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_compression", false);

    // mini_blar Zig module — depends on BLIP's `blip` module
    const mini_blar_module = b.addModule("mini_blar", .{
        .root_source_file = b.path("src/mini_blar.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "blip", .module = blip_dep.module("blip") },
        },
    });
    mini_blar_module.addOptions("build_options", build_options);

    // C FFI surface (libmini_blar.a) — re-exports `blar_archive_*` for the C CLI.
    // link_libc is required on Linux because c_api.zig uses std.heap.c_allocator.
    const ffi_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "blip", .module = blip_dep.module("blip") },
            .{ .name = "mini_blar", .module = mini_blar_module },
        },
    });
    ffi_module.addOptions("build_options", build_options);
    const static_lib = b.addLibrary(.{
        .name = "mini_blar",
        .linkage = .static,
        .root_module = ffi_module,
    });
    b.installArtifact(static_lib);

    // miniblar C CLI — its own pure-C module that links libmini_blar + libblip.
    const cli_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    cli_module.addCSourceFile(.{
        .file = b.path("src/miniblar.c"),
        .flags = &.{ "-std=c11", "-D_GNU_SOURCE" },
    });
    cli_module.addIncludePath(b.path("src"));
    cli_module.addIncludePath(blip_dep.path("src"));

    const miniblar = b.addExecutable(.{
        .name = "miniblar",
        .root_module = cli_module,
    });
    miniblar.root_module.linkLibrary(static_lib);
    miniblar.root_module.linkLibrary(blip_dep.artifact("blip"));
    b.installArtifact(miniblar);

    // ── Tests ────────────────────────────────────────────────────────────
    const tests = b.addTest(.{
        .root_module = mini_blar_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
