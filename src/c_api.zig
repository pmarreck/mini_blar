//! C FFI surface for mini_blar.
//!
//! Re-exports the archive operations from mini_blar.zig under the
//! `blar_*` symbol prefix. Scoped to mini_blar's profile: FILE/DIR
//! entries, xxhash64 only, no compression, no encryption, no codec
//! expansion.

const std = @import("std");
const blip = @import("blip");
const mb = @import("mini_blar");

const Allocator = std.mem.Allocator;
const ALLOC = std.heap.c_allocator;

// ── Error codes ──────────────────────────────────────────────────────────
pub const BLAR_OK: i32 = 0;
pub const BLAR_ERR_INVALID: i32 = -1;
pub const BLAR_ERR_BOUNDS: i32 = -2;
pub const BLAR_ERR_NOT_FOUND: i32 = -3;
pub const BLAR_ERR_HASH_MISMATCH: i32 = -4;
pub const BLAR_ERR_ALLOC: i32 = -5;
pub const BLAR_ERR_INVALID_MAGIC: i32 = -6;
pub const BLAR_ERR_IO: i32 = -7;

export fn blar_error_string(code: i32) [*:0]const u8 {
    return switch (code) {
        BLAR_OK => "ok",
        BLAR_ERR_INVALID => "invalid argument",
        BLAR_ERR_BOUNDS => "out of bounds",
        BLAR_ERR_NOT_FOUND => "not found",
        BLAR_ERR_HASH_MISMATCH => "hash mismatch",
        BLAR_ERR_ALLOC => "allocation failed",
        BLAR_ERR_INVALID_MAGIC => "invalid archive magic",
        BLAR_ERR_IO => "I/O error",
        else => "unknown error",
    };
}

fn errorToCode(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => BLAR_ERR_ALLOC,
        error.IndexOutOfBounds, error.BoundsCheck => BLAR_ERR_BOUNDS,
        error.HashMismatch => BLAR_ERR_HASH_MISMATCH,
        error.NotFound, error.MissingRequiredKey => BLAR_ERR_NOT_FOUND,
        error.InvalidMagic => BLAR_ERR_INVALID_MAGIC,
        else => BLAR_ERR_INVALID,
    };
}

// ── Flags ─────────────────────────────────────────────────────────────────
pub const BLAR_ARCHIVE_ABSOLUTE_PATHS: u32 = 1 << 0;

// Container type IDs (matches BLAR spec)
pub const BLAR_TYPE_FILE: u8 = 5;
pub const BLAR_TYPE_DIR: u8 = 7;

// ── Input structs (ABI: matches what the C CLI populates) ─────────────────
pub const blar_xattr_entry = extern struct {
    name: [*]const u8,
    name_len: usize,
    value: [*]const u8,
    value_len: usize,
};

pub const blar_archive_entry = extern struct {
    path: [*]const u8,
    path_len: usize,
    content: [*]const u8,
    content_len: usize,
    is_dir: i32,

    mode: u16,
    _pad0: u16 = 0,
    mtime_ns: i64,
    ctime_ns: i64,
    birthtime_ns: i64,
    uid: u32,
    gid: u32,
    owner: ?[*]const u8,
    owner_len: usize,
    groupname: ?[*]const u8,
    groupname_len: usize,

    xattrs: ?[*]const blar_xattr_entry,
    xattr_count: usize,
    resource_fork: ?[*]const u8,
    resource_fork_len: usize,
};

// ── Free helpers (the Zig core mallocs returns; C calls these) ────────────
export fn blar_free(buf: ?[*]u8, len: usize) void {
    if (buf) |p| ALLOC.free(p[0..len]);
}

export fn blar_free_content(buf: ?[*]const u8, len: usize) void {
    if (buf) |p| {
        const slice: []u8 = @constCast(p[0..len]);
        ALLOC.free(slice);
    }
}

// ── Build ArchiveEntry from C struct ──────────────────────────────────────
fn buildFileEntry(arena: Allocator, ce: *const blar_archive_entry) !mb.FileEntry {
    var fe: mb.FileEntry = .{
        .path = ce.path[0..ce.path_len],
        .content = ce.content[0..ce.content_len],
        .mode = ce.mode,
        .mtime_ns = ce.mtime_ns,
        .ctime_ns = ce.ctime_ns,
        .birthtime_ns = ce.birthtime_ns,
        .uid = ce.uid,
        .gid = ce.gid,
        .username = if (ce.owner) |p| p[0..ce.owner_len] else &.{},
        .groupname = if (ce.groupname) |p| p[0..ce.groupname_len] else &.{},
        .resource_fork = if (ce.resource_fork) |p| p[0..ce.resource_fork_len] else &.{},
    };
    if (ce.xattrs) |xa_ptr| {
        const xa_slice = xa_ptr[0..ce.xattr_count];
        const out_xa = try arena.alloc(mb.XattrEntry, xa_slice.len);
        for (xa_slice, 0..) |x, i| {
            out_xa[i] = .{
                .name = x.name[0..x.name_len],
                .value = x.value[0..x.value_len],
            };
        }
        fe.xattrs = out_xa;
    }
    return fe;
}

fn buildDirEntry(_: Allocator, ce: *const blar_archive_entry) !mb.DirEntry {
    return .{
        .path = ce.path[0..ce.path_len],
        .xh64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
        .mode = ce.mode,
        .mtime_ns = ce.mtime_ns,
        .ctime_ns = ce.ctime_ns,
        .birthtime_ns = ce.birthtime_ns,
        .uid = ce.uid,
        .gid = ce.gid,
        .username = if (ce.owner) |p| p[0..ce.owner_len] else &.{},
        .groupname = if (ce.groupname) |p| p[0..ce.groupname_len] else &.{},
    };
}

// ── Public C API ──────────────────────────────────────────────────────────

export fn blar_archive_create_full(
    entries_ptr: [*]const blar_archive_entry,
    entry_count: usize,
    flags: u32,
    _: u32, // reserved (compression id; mini_blar profile = 0)
    num_threads: u8,
    progress_fn: mb.ProgressFn,
    phase_fn: mb.PhaseFn,
    progress_ctx: ?*anyopaque,
    out_buf: *?[*]u8,
    out_len: *usize,
) i32 {
    _ = flags;
    var arena_state = std.heap.ArenaAllocator.init(ALLOC);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const c_entries = entries_ptr[0..entry_count];
    const ar_entries = arena.alloc(mb.ArchiveEntry, entry_count) catch return BLAR_ERR_ALLOC;
    for (c_entries, 0..) |*ce, i| {
        if (ce.is_dir != 0) {
            ar_entries[i] = .{ .dir = buildDirEntry(arena, ce) catch return BLAR_ERR_ALLOC };
        } else {
            ar_entries[i] = .{ .file = buildFileEntry(arena, ce) catch return BLAR_ERR_ALLOC };
        }
    }

    const buf = mb.createFullArchive(
        ALLOC,
        ar_entries,
        progress_fn,
        phase_fn,
        progress_ctx,
        null,
        num_threads,
    ) catch |e| return errorToCode(e);

    out_buf.* = buf.ptr;
    out_len.* = buf.len;
    return BLAR_OK;
}

export fn blar_archive_file_count(buf: [*]const u8, len: usize, out_count: *u64) i32 {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch |e| return errorToCode(e);
    out_count.* = reader.fileCount() catch |e| return errorToCode(e);
    return BLAR_OK;
}

export fn blar_archive_entry_count(buf: [*]const u8, len: usize, out_count: *u64) i32 {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch |e| return errorToCode(e);
    out_count.* = reader.entryCount() catch |e| return errorToCode(e);
    return BLAR_OK;
}

/// Path of entry at `idx` (zero-copy: pointer into buf).
export fn blar_archive_file_path(
    buf: [*]const u8,
    len: usize,
    idx: u64,
    out_ptr: *[*]const u8,
    out_len: *usize,
) i32 {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch |e| return errorToCode(e);
    const path = reader.entryPathAt(idx) catch |e| return errorToCode(e);
    out_ptr.* = path.ptr;
    out_len.* = path.len;
    return BLAR_OK;
}

/// Content of file at `idx`. Caller must `blar_free_content` the result.
/// Copies to ALLOC-owned memory so the freed pointer pattern stays uniform.
export fn blar_archive_file_content(
    buf: [*]const u8,
    len: usize,
    idx: u64,
    out_data: *[*]const u8,
    out_len: *usize,
) i32 {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch |e| return errorToCode(e);
    const slice = reader.fileContentAt(idx) catch |e| return errorToCode(e);
    const copy = ALLOC.alloc(u8, slice.len) catch return BLAR_ERR_ALLOC;
    @memcpy(copy, slice);
    out_data.* = copy.ptr;
    out_len.* = copy.len;
    return BLAR_OK;
}

export fn blar_archive_file_content_by_path(
    buf: [*]const u8,
    len: usize,
    path: [*]const u8,
    path_len: usize,
    out_data: *[*]const u8,
    out_len: *usize,
) i32 {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch |e| return errorToCode(e);
    const idx_opt = reader.findFile(path[0..path_len]) catch |e| return errorToCode(e);
    const idx = idx_opt orelse return BLAR_ERR_NOT_FOUND;
    const slice = reader.fileContentAt(idx) catch |e| return errorToCode(e);
    const copy = ALLOC.alloc(u8, slice.len) catch return BLAR_ERR_ALLOC;
    @memcpy(copy, slice);
    out_data.* = copy.ptr;
    out_len.* = copy.len;
    return BLAR_OK;
}

export fn blar_archive_file_verify(buf: [*]const u8, len: usize, idx: u64) i32 {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch |e| return errorToCode(e);
    const ok = reader.verifyFileAt(idx) catch |e| return errorToCode(e);
    return if (ok) BLAR_OK else BLAR_ERR_HASH_MISMATCH;
}

export fn blar_archive_verify(buf: [*]const u8, len: usize) bool {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch return false;
    return reader.verifyChecksum() catch false;
}

export fn blar_archive_entry_type(buf: [*]const u8, len: usize, idx: u64, out_type: *u8) i32 {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch |e| return errorToCode(e);
    const tid = reader.entryTypeAt(idx) catch |e| return errorToCode(e);
    out_type.* = @intFromEnum(tid);
    return BLAR_OK;
}

export fn blar_archive_entry_metadata(
    buf: [*]const u8,
    len: usize,
    idx: u64,
    out_mode: *u16,
    out_mtime_ns: *i64,
    out_owner: *?[*]const u8,
    out_owner_len: *usize,
) void {
    const reader = mb.ArchiveReader.init(buf[0..len]) catch {
        out_mode.* = 0;
        out_mtime_ns.* = 0;
        out_owner.* = null;
        out_owner_len.* = 0;
        return;
    };
    const md = reader.entryMetadataAt(idx) catch {
        out_mode.* = 0;
        out_mtime_ns.* = 0;
        out_owner.* = null;
        out_owner_len.* = 0;
        return;
    };
    out_mode.* = md.mode;
    out_mtime_ns.* = md.mtime_ns;
    if (md.owner.len > 0) {
        out_owner.* = md.owner.ptr;
        out_owner_len.* = md.owner.len;
    } else {
        out_owner.* = null;
        out_owner_len.* = 0;
    }
}

comptime {
    _ = blar_error_string;
    _ = blar_archive_create_full;
    _ = blar_archive_file_count;
    _ = blar_archive_entry_count;
    _ = blar_archive_file_path;
    _ = blar_archive_file_content;
    _ = blar_archive_file_content_by_path;
    _ = blar_archive_file_verify;
    _ = blar_archive_verify;
    _ = blar_archive_entry_type;
    _ = blar_archive_entry_metadata;
    _ = blar_free;
    _ = blar_free_content;
}
