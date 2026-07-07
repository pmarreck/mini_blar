# Code Minimap — mini_blar

mini_blar's source is intentionally tiny: one Zig core, one C-FFI surface,
one C CLI, and a shared C header for cross-cutting helpers.

## src/mini_blar.zig

High-level archive API. Composes BLIP's generic containers into the specific
FILE/DIR shapes the BLAR spec defines, plus a Merkle hash over the top-level
archive.

- `FileEntry` — struct: path, content, metadata (mode, mtime, owner, xattrs)
- `DirEntry` — struct: path, xh64, metadata
- `ArchiveEntry` — union(enum) { file, dir }
- `createArchive(alloc, files) ![]u8` — flat FILE-only archive
- `createFullArchive(alloc, entries, ...) ![]u8` — archive with FILE + DIR entries
- `computeMerkleHash(child_hashes) [8]u8` — xxHash64 of concatenated child hashes
- `ArchiveReader` — zero-copy reader. Methods include:
  - `init` / `verifyMagic` / `verifyChecksum`
  - `entryCount` / `fileCount`
  - `entryTypeAt` / `entryPathAt` / `fileContentAt`
  - `findFile` / `verifyFileAt` / `verifyMerkleAt`
  - `entryMetadataAt` (returns flat `EntryMetadata` for the C FFI)

## src/c_api.zig

C FFI surface (`libmini_blar.a`). Re-exports archive operations as
`blar_archive_*` extern functions plus error-code/flag constants and the
`blar_archive_entry` / `blar_xattr_entry` ABI structs.

- `blar_archive_create_full` / `blar_archive_file_count` / `blar_archive_entry_count`
- `blar_archive_file_path` / `blar_archive_file_content` / `blar_archive_file_content_by_path`
- `blar_archive_file_verify` / `blar_archive_verify`
- `blar_archive_entry_type` / `blar_archive_entry_metadata`
- `blar_free` / `blar_free_content`
- `blar_error_string`

## src/blar.h

C header for the FFI — the public API surface for any C consumer.

## src/compression_stub.zig

No-op compression module — the default (`-Denable_compression=false`).
Signature twin of `compression_zstd.zig` (same fn signatures + error set) so
`mini_blar.zig`'s catch/switch arms compile identically in both modes; always
returns `error.UnsupportedCompression`, links zero codecs.

## src/compression_zstd.zig

zstd-only compression module, selected by `-Denable_compression=true` via the
comptime switch in `mini_blar.zig`. Ported from blar's `compression.zig` zstd
arms (streaming ZSTD_compressStream2 with 4 MB progress chunks; single-shot
below that). `compressContainer` wraps compressed bytes in an LP DATA
container with `COMP=zstd`, `DECOMP_LEN`, and `CSUM=xxhash64` over stored
bytes (verify-before-decompress); `decompressContainer` mirrors it. Any
non-zstd comp_id → `error.UnsupportedCompression`. Level is comptime from
`-Dzstd_level` (default 19). Depends on vendored `zstdz` (zig-pkg/), pinned
≥0a478bb for the `-Dcpu=baseline` ISA fix. MT policy: inputs ≥
`MT_INPUT_THRESHOLD` (8 MB) always take zstd's MT path with
`min(num_threads, MT_MAX_WORKERS=8)` workers and pinned `MT_JOB_SIZE`
(8 MB); smaller inputs always single-thread. Path is size-selected (never
thread-selected) so bytes are independent of num_threads — test-enforced.

## src/miniblar.c

Minimal C CLI — calls through `blar.h` for all archive work.
Commands: `create` / `list` / `extract` / `verify` / `info` / `cat`.
Tar-style shorthand also supported: `cf` / `tf` / `xf` / `Vf` / `If` / `pf`
(with or without leading hyphen). `-o` flag accepted in any position;
`.mblar` extension auto-appended; directory inputs explicitly rejected
(use blar for directory support).

## src/blar_common.h

Shared C utilities — file I/O (`read_file`/`write_file`), `mkdirp`,
`ensure_parent_dir`, POSIX metadata helpers (`fill_entry_metadata`,
`get_mtime_ns`, `get_birthtime_ns`, `get_owner_name`, `get_group_name`),
extended-attribute reader (`read_file_xattrs`/`free_file_xattrs`),
tar-style flag parsing (`parse_tar_flags`), default output name
(`default_output_name`), and `normalize_path_inplace`. Header-only so it
embeds trivially into the C CLI.

## tests/miniblar_test.sh

Integration tests for the miniblar CLI. 25 checks covering flat
archives, binary roundtrips, tar-style flags, `-o` positioning, extension
auto-append, directory rejection, corruption detection, and `cat` with
normalized paths.

## External dependency: BLIP

mini_blar consumes [BLIP](https://github.com/pmarreck/BLIP) via
`build.zig.zon` (tag `v3.0.0`) and as a Nix flake input. The BLIP-provided
symbols mini_blar uses:

- The `blip` Zig module: `container_mod` / `array_mod` / `dict_mod` /
  `leaf_mod` / `container_types`
- `libblip.a` for the BLIP-side C symbols the CLI links against
