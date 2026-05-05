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

    // mini_blar Zig module — depends on BLIP's `blip` module
    const mini_blar_module = b.createModule(.{
        .root_source_file = b.path("src/mini_blar.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "blip", .module = blip_dep.module("blip") },
        },
    });

    // miniblar C CLI — links against BLIP's static lib + Zig core
    const miniblar = b.addExecutable(.{
        .name = "miniblar",
        .root_module = mini_blar_module,
    });
    miniblar.linkLibrary(blip_dep.artifact("blip"));
    miniblar.addIncludePath(blip_dep.path("src"));
    miniblar.addCSourceFile(.{
        .file = b.path("src/miniblar.c"),
        .flags = &.{ "-std=c11", "-D_GNU_SOURCE" },
    });
    miniblar.linkLibC();

    if (comptime @import("builtin").mode == .Debug) {
        // Announce debug builds early in main()
    }

    b.installArtifact(miniblar);

    // ── Tests ────────────────────────────────────────────────────────────
    const tests = b.addTest(.{
        .root_module = mini_blar_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
