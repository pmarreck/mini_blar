# Code Minimap — mini_blar

mini_blar's source is intentionally tiny: one Zig module, one C CLI, and a
shared C header for cross-cutting helpers.

## src/mini_blar.zig

High-level archive API. Composes BLIP's generic containers into the specific
FILE/DIR shapes the BLAR spec defines, plus a Merkle hash over the top-level
archive.

- `FileEntry` — struct: path, content, metadata (mode, mtime, owner, xattrs)
- `DirEntry` — struct: path, xh64, metadata
- `ArchiveEntry` — union(enum) { file, dir }
- `createArchive(alloc, files) ![]u8` — flat FILE-only archive
- `createFullArchive(alloc, entries) ![]u8` — archive with FILE + DIR entries
- `computeMerkleHash(child_hashes) [8]u8` — xxHash64 of concatenated child hashes
- `ArchiveReader` — zero-copy reader: init, verifyMagic, fileCount, fileAt,
  findFile, entryCount, entryAt, entryTypeAt, verifyHash

## src/miniblar.c

C CLI. Calls through the BLIP C FFI for all archive work. Constrained to the
mini_blar profile — rejects compression/encryption/expansion attributes if it
encounters them in input.

Commands: `create` / `list` / `extract` / `verify` / `info` / `cat`. Tar-style
shorthand also supported: `cf` / `tf` / `xf` / `Vf` / `If` / `pf`.

## src/blar_common.h

Shared C utilities for filesystem and CLI work — kept as a header to remain
trivially embeddable into the C CLI.

- `read_file`, `write_file` — file I/O helpers
- `mkdirp`, `ensure_parent_dir` — recursive directory creation
- `progress_t`, `progress_init/update/finish` — interactive progress bar
- `parse_tar_flags` — tar-style flag parsing (`cf`/`tf`/`xf`/`Vf`/`If`/`pf`)
- `default_output_name` — generate default `<basename>.blar` output path
- `normalize_path` — strip leading `./` and `/` from paths

## tests/miniblar_test.sh

Integration tests for the miniblar CLI. Covers flat archives, binary
roundtrips, metadata fidelity, hash verification, and rejection of
out-of-profile input.

## External dependency: BLIP

mini_blar consumes [BLIP](https://github.com/pmarreck/BLIP) via
`build.zig.zon`. The relevant BLIP-provided symbols mini_blar uses:

- `blip_encode` / `blip_decode` / `blip_xxhash64` (C FFI)
- `blip.container_mod` — the LP envelope mechanic
- `blip.array_mod` / `blip.dict_mod` — generic ARRAY/DICT containers
- `blip.leaf` — UTF8/DATA leaf containers
