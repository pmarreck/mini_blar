//! No-op compression module for mini_blar.
//!
//! mini_blar's profile forbids compression entirely. This stub satisfies
//! mini_blar.zig's type system without pulling in the heavy compression
//! dependencies (z7z, bzip2z, lz4, zstdz).

const std = @import("std");
const blip = @import("blip");
const ct = blip.container_types;

// Superset of what the real compression module's catch arms reference, so
// the type checker accepts mini_blar.zig's existing switch (e) blocks
// even though the stub never actually returns these at runtime.
pub const CompressionError = error{
    UnsupportedCompression,
    OutOfMemory,
    CompressionFailed,
};

pub const CompressProgressFn = ?*const fn (u64, u64, ?*anyopaque) callconv(.c) void;

pub fn isCompressed(_: []const u8) bool {
    return false;
}

pub fn compressContainer(
    _: std.mem.Allocator,
    _: ct.CompressionId,
    _: []const u8,
    _: CompressProgressFn,
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: u8,
) CompressionError![]u8 {
    return error.UnsupportedCompression;
}

pub fn decompressContainer(
    _: std.mem.Allocator,
    _: []const u8,
) CompressionError![]u8 {
    return error.UnsupportedCompression;
}
