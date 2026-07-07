//! zstd-only compression module for mini_blar.
//!
//! Selected via -Denable_compression=true (see mini_blar.zig's comptime
//! switch). Implements the BLIP-container-aware compress/decompress path for
//! comp_id = .zstd only — any other comp_id is error.UnsupportedCompression.
//! Keeping a single codec (vs blar's four) means no runtime dispatch and the
//! stub build stays truly minimal via DCE.
//!
//! Ported from blar's compression.zig zstd arms, with two profile deltas:
//! the wrapper LP's checksum is xxhash64 (mini_blar's only checksum — blar
//! uses blake3_128), and the compression level is a comptime build option
//! (-Dzstd_level, default 19) instead of blar's hardcoded 3: consumers like
//! validate_gui's launcher compress once at build time and decompress on
//! every launch, so we bias hard for ratio.

const std = @import("std");
const Allocator = std.mem.Allocator;
const blip = @import("blip");
const ct = blip.container_types;
const container = blip.container_mod;
const csum_mod = blip.checksum_mod;
const zstd = @import("zstd").c;
const build_options = @import("build_options");
const testing = std.testing;

const ContainerError = container.ContainerError;

/// zstd compression level, baked in at build time (-Dzstd_level).
const ZSTD_LEVEL: u8 = build_options.zstd_level;

/// Streaming chunk size for progress reporting on large inputs.
const CHUNK_SIZE: usize = 4 * 1024 * 1024;

pub const CompressionError = error{
    UnsupportedCompression,
    OutOfMemory,
    CompressionFailed,
    DecompressionFailed,
};

/// Progress callback for compression: (bytes_done, bytes_total, user_ctx).
pub const CompressProgressFn = ?*const fn (u64, u64, ?*anyopaque) callconv(.c) void;

/// Phase callback: (label_ptr, label_len, user_ctx).
pub const PhaseFn = ?*const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void;

/// Quick check if buffer starts with a compressed LP container.
pub fn isCompressed(buf: []const u8) bool {
    const view = container.parseLPHeader(buf) catch return false;
    return view.comp_id != null;
}

/// Compress raw bytes with zstd at the build-configured level.
/// Streams in 4 MB chunks so progress_fn gets called on large inputs.
/// num_threads: 0=auto, 1=single-threaded, N=request N zstd workers.
/// Caller owns returned memory.
fn compress(
    allocator: Allocator,
    data: []const u8,
    progress_fn: CompressProgressFn,
    progress_ctx: ?*anyopaque,
    num_threads: u8,
) (Allocator.Error || CompressionError)![]u8 {
    const bound = zstd.ZSTD_compressBound(data.len);
    if (zstd.ZSTD_isError(bound) != 0) return error.CompressionFailed;

    const dest_buf = try allocator.alloc(u8, bound);
    errdefer allocator.free(dest_buf);

    const cctx = zstd.ZSTD_createCCtx() orelse return error.CompressionFailed;
    defer _ = zstd.ZSTD_freeCCtx(cctx);

    _ = zstd.ZSTD_CCtx_setParameter(cctx, zstd.ZSTD_c_compressionLevel, ZSTD_LEVEL);
    if (num_threads != 1) {
        const resolved: c_int = if (num_threads == 0)
            @intCast(std.Thread.getCpuCount() catch 1)
        else
            @intCast(num_threads);
        // Best-effort: a no-op if libzstd was built without ZSTD_MULTITHREAD.
        _ = zstd.ZSTD_CCtx_setParameter(cctx, zstd.ZSTD_c_nbWorkers, resolved);
    }

    if (data.len <= CHUNK_SIZE) {
        // Small data: single-shot via CCtx
        const csize = zstd.ZSTD_compress2(cctx, dest_buf.ptr, bound, data.ptr, data.len);
        if (zstd.ZSTD_isError(csize) != 0) return error.CompressionFailed;
        if (progress_fn) |cb| cb(data.len, data.len, progress_ctx);
        return allocator.realloc(dest_buf, csize) catch dest_buf[0..csize];
    }

    var out_buf = zstd.ZSTD_outBuffer{ .dst = dest_buf.ptr, .size = dest_buf.len, .pos = 0 };
    var src_offset: usize = 0;

    while (src_offset < data.len) {
        const remaining = data.len - src_offset;
        const this_chunk = @min(remaining, CHUNK_SIZE);
        const is_last = (src_offset + this_chunk >= data.len);

        var in_buf = zstd.ZSTD_inBuffer{ .src = data.ptr + src_offset, .size = this_chunk, .pos = 0 };
        const directive: c_uint = if (is_last) zstd.ZSTD_e_end else zstd.ZSTD_e_continue;

        while (true) {
            const ret = zstd.ZSTD_compressStream2(cctx, &out_buf, &in_buf, directive);
            if (zstd.ZSTD_isError(ret) != 0) return error.CompressionFailed;
            if (is_last) {
                if (ret == 0) break; // fully flushed
            } else {
                if (in_buf.pos >= in_buf.size) break;
            }
        }

        src_offset += this_chunk;
        if (progress_fn) |cb| cb(src_offset, data.len, progress_ctx);
    }

    return allocator.realloc(dest_buf, out_buf.pos) catch dest_buf[0..out_buf.pos];
}

/// Decompress zstd bytes; decomp_len is the exact expected output size
/// (from the LP header's DECOMP_LEN attribute). Caller owns returned memory.
fn decompressRaw(allocator: Allocator, data: []const u8, decomp_len: u64) (Allocator.Error || CompressionError)![]u8 {
    const out_buf = try allocator.alloc(u8, @intCast(decomp_len));
    errdefer allocator.free(out_buf);

    const dsize = zstd.ZSTD_decompress(out_buf.ptr, out_buf.len, data.ptr, data.len);
    if (zstd.ZSTD_isError(dsize) != 0 or dsize != @as(usize, @intCast(decomp_len))) {
        return error.DecompressionFailed;
    }
    return out_buf;
}

/// Wrap serialized container bytes in a zstd-compressed LP DATA container.
/// Produces: [BLIP(total)] [TYPE=data] [COMP=zstd] [DECOMP_LEN=N] [CSUM=xxhash64] [VAL: compressed] [XXH64]
/// comp_id must be .zstd — this build links exactly one codec.
/// Caller owns returned memory.
pub fn compressContainer(
    allocator: Allocator,
    comp_id: ct.CompressionId,
    container_bytes: []const u8,
    progress_fn: CompressProgressFn,
    phase_fn: PhaseFn,
    progress_ctx: ?*anyopaque,
    num_threads: u8,
) (Allocator.Error || ContainerError || CompressionError)![]u8 {
    if (comp_id != .zstd) return error.UnsupportedCompression;

    const compressed = try compress(allocator, container_bytes, progress_fn, progress_ctx, num_threads);
    defer allocator.free(compressed);

    // Signal phase change: wrapping compressed data in LP container + checksumming
    if (phase_fn) |cb| {
        const label = "Finalizing";
        cb(label.ptr, label.len, progress_ctx);
    }

    const options: container.LPOptions = .{
        .comp_id = .zstd,
        .decomp_len = container_bytes.len,
        .csum_id = .xxhash64,
    };

    const total = container.computeLPLength(.data, compressed.len, options);
    const buf = try allocator.alloc(u8, @intCast(total));
    errdefer allocator.free(buf);

    const header_len = try container.writeLPHeader(buf, .data, total, options);
    @memcpy(buf[header_len..][0..compressed.len], compressed);

    const csum_len = ct.checksumLength(.xxhash64);
    const csum_result = csum_mod.compute(.xxhash64, buf[0 .. @as(usize, @intCast(total)) - csum_len]);
    @memcpy(buf[@as(usize, @intCast(total)) - csum_len .. @as(usize, @intCast(total))], csum_result[0..csum_len]);

    return buf;
}

/// Decompress an LP container carrying a COMP attribute: verify its checksum,
/// then zstd-decompress the payload back to the inner container bytes.
/// Only comp_id = .zstd is supported. Caller owns returned memory.
pub fn decompressContainer(
    allocator: Allocator,
    buf: []const u8,
) (Allocator.Error || ContainerError || CompressionError)![]u8 {
    const view = try container.parseLPHeader(buf);

    const comp_id = view.comp_id orelse return error.InvalidContainerType;
    if (comp_id != .zstd) return error.UnsupportedCompression;

    // Verify checksum if present (verify-before-decompress: never feed
    // corrupted bytes to the decoder)
    if (view.csum_id) |csum_id| {
        const csum_bytes = view.checksumSlice();
        const csum_len = ct.checksumLength(csum_id);
        const data_to_check = buf[0 .. @as(usize, @intCast(view.total_length)) - csum_len];
        if (!csum_mod.verify(csum_id, data_to_check, csum_bytes)) {
            return error.HashMismatch;
        }
    }

    const decomp_len = view.decomp_len orelse return error.InvalidLength;
    const payload = view.payloadSlice();

    return decompressRaw(allocator, payload, decomp_len);
}

// =============================================================================
// Tests (run only in -Denable_compression=true builds, via mini_blar.zig's
// `test { _ = compression_mod; }` hook)
// =============================================================================

test "zstd compressContainer/decompressContainer round-trip" {
    const allocator = testing.allocator;
    const leaf = blip.leaf_mod;

    const inner = try leaf.serializeData(allocator, "Hello, zstd container!");
    defer allocator.free(inner);

    const compressed = try compressContainer(allocator, .zstd, inner, null, null, null, 1);
    defer allocator.free(compressed);

    const decompressed = try decompressContainer(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, inner, decompressed);
}

test "compressContainer LP attributes: comp_id=zstd, csum=xxhash64, decomp_len exact" {
    const allocator = testing.allocator;
    const leaf = blip.leaf_mod;

    const inner = try leaf.serializeData(allocator, "attribute verification");
    defer allocator.free(inner);

    const compressed = try compressContainer(allocator, .zstd, inner, null, null, null, 1);
    defer allocator.free(compressed);

    const view = try container.parseLPHeader(compressed);
    try testing.expectEqual(ct.ContainerTypeId.data, view.type_id);
    try testing.expectEqual(@as(?ct.CompressionId, .zstd), view.comp_id);
    try testing.expectEqual(@as(?u64, inner.len), view.decomp_len);
    try testing.expectEqual(@as(?ct.ChecksumId, .xxhash64), view.csum_id);
    try testing.expect(isCompressed(compressed));
}

test "compressContainer rejects non-zstd comp_ids" {
    const allocator = testing.allocator;
    const rejected = [_]ct.CompressionId{ .lz4, .lzma2, .bzip2 };
    for (rejected) |algo| {
        try testing.expectError(
            error.UnsupportedCompression,
            compressContainer(allocator, algo, "payload", null, null, null, 1),
        );
    }
}

test "decompressContainer rejects non-compressed container" {
    const allocator = testing.allocator;
    const leaf = blip.leaf_mod;

    const plain = try leaf.serializeData(allocator, "not compressed");
    defer allocator.free(plain);

    try testing.expectError(error.InvalidContainerType, decompressContainer(allocator, plain));
}

test "MT path (num_threads>=2) output is deterministic run-to-run" {
    // Upstream guarantee (zstd author, facebook/zstd#2079): for a fixed
    // version + params, MT compression output is byte-identical run to run.
    // This is a regression tripwire for zstdz bumps. Envelope note: at our
    // comptime level the input may fit one internal MT job; the guarantee
    // (and this test) still covers our actual usage.
    const allocator = testing.allocator;
    const leaf = blip.leaf_mod;

    const raw_len: usize = 6 * 1024 * 1024; // > CHUNK_SIZE: exercises streaming path
    const raw = try allocator.alloc(u8, raw_len);
    defer allocator.free(raw);
    for (raw, 0..) |*b, i| b.* = @intCast((i / 512) % 253);

    const inner = try leaf.serializeData(allocator, raw);
    defer allocator.free(inner);

    const c_first = try compressContainer(allocator, .zstd, inner, null, null, null, 8);
    defer allocator.free(c_first);
    const c_second = try compressContainer(allocator, .zstd, inner, null, null, null, 8);
    defer allocator.free(c_second);

    try testing.expectEqualSlices(u8, c_first, c_second);

    // and the MT path round-trips
    const back = try decompressContainer(allocator, c_first);
    defer allocator.free(back);
    try testing.expectEqualSlices(u8, inner, back);
}

test "MT output is thread-count independent (zstd#2079)" {
    // "the nb of compression threads can be anything, from 1 to N, and the
    // outcome will nonetheless remain exactly identical" — Yann Collet.
    // num_threads=0 (auto-detect) must also match: reproducibility across
    // machines with different core counts depends on it.
    const allocator = testing.allocator;
    const leaf = blip.leaf_mod;

    const raw_len: usize = 6 * 1024 * 1024;
    const raw = try allocator.alloc(u8, raw_len);
    defer allocator.free(raw);
    for (raw, 0..) |*b, i| b.* = @intCast((i / 512) % 253);

    const inner = try leaf.serializeData(allocator, raw);
    defer allocator.free(inner);

    const c_2 = try compressContainer(allocator, .zstd, inner, null, null, null, 2);
    defer allocator.free(c_2);
    const c_8 = try compressContainer(allocator, .zstd, inner, null, null, null, 8);
    defer allocator.free(c_8);
    const c_auto = try compressContainer(allocator, .zstd, inner, null, null, null, 0);
    defer allocator.free(c_auto);

    try testing.expectEqualSlices(u8, c_2, c_8);
    try testing.expectEqualSlices(u8, c_2, c_auto);
}

test "decompressContainer verifies checksum and rejects corruption" {
    const allocator = testing.allocator;
    const leaf = blip.leaf_mod;

    const inner = try leaf.serializeData(allocator, "integrity check payload");
    defer allocator.free(inner);

    const compressed = try compressContainer(allocator, .zstd, inner, null, null, null, 1);
    defer allocator.free(compressed);

    // Corrupt a byte in the middle (compressed payload, not header/checksum)
    compressed[compressed.len / 2] ^= 0xFF;

    try testing.expectError(error.HashMismatch, decompressContainer(allocator, compressed));
}
