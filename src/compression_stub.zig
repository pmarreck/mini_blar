//! No-op compression module for mini_blar.
//!
//! mini_blar's default profile forbids compression entirely. This stub
//! satisfies mini_blar.zig's type system without pulling in any codec
//! dependency (the -Denable_compression=true build swaps in
//! compression_zstd.zig instead — keep both signatures identical).

const std = @import("std");
const blip = @import("blip");
const ct = blip.container_types;
const container = blip.container_mod;

const ContainerError = container.ContainerError;

// Signature twin of compression_zstd.zig: same error set and return types,
// so mini_blar.zig's catch/switch arms compile identically in both modes.
pub const CompressionError = error{
    UnsupportedCompression,
    OutOfMemory,
    CompressionFailed,
    DecompressionFailed,
};

pub const CompressProgressFn = ?*const fn (u64, u64, ?*anyopaque) callconv(.c) void;

/// Phase callback: (label_ptr, label_len, user_ctx).
pub const PhaseFn = ?*const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void;

pub fn isCompressed(_: []const u8) bool {
    return false;
}

pub fn compressContainer(
    _: std.mem.Allocator,
    _: ct.CompressionId,
    _: []const u8,
    _: CompressProgressFn,
    _: PhaseFn,
    _: ?*anyopaque,
    _: u8,
) (std.mem.Allocator.Error || ContainerError || CompressionError)![]u8 {
    return error.UnsupportedCompression;
}

pub fn decompressContainer(
    _: std.mem.Allocator,
    _: []const u8,
) (std.mem.Allocator.Error || ContainerError || CompressionError)![]u8 {
    return error.UnsupportedCompression;
}
