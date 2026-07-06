# mini_blar — Project Overview

## Goal

Provide a tiny, dependency-light reader/writer for a constrained profile of the
BLAR archive format. Suitable for embedded systems, bootstrap environments
(initramfs, recovery tooling), and any context where pulling in the full blar
toolchain — with libjxl, libflac, AES, codec expansion, and a macOS GUI — is
unjustified.

Every mini_blar archive is a valid blar archive. The reverse is not true: blar
archives that use compression, encryption, segmentation, signatures, or codec
expansion fall outside mini_blar's profile and are rejected by mini_blar's
reader.

## Scope (the constrained subset)

mini_blar archives (default profile):

- Container types: `FILE` (TYPE=5) and `DIR` (TYPE=7) only
- Attributes: `TYPE`, `CSUM`, `VAL` (no `COMP`, `ENC`, `SEG`, `SIG`)
- Checksums: `xxhash64` only (no CRC32, no BLAKE3-128)
- No compression, encryption, container expansion, or signing

**Build-time exception:** `-Denable_compression=true` links exactly one codec
(zstd, via the vendored `zstdz` dep) and permits per-file `COMP=zstd`
containers, checksummed with xxhash64 over the stored bytes. This exists for
the validate_gui single-binary launcher (compress once at build time,
transparently decompress via `fileContentDecompress` on every launch). The
default build keeps the no-op stub — zero codecs linked. Compression level is
a build option (`-Dzstd_level`, default 19).

## Architecture

```
miniblar (C CLI)  ───►  C FFI (BLIP's blip.h)  ───►  BLIP Zig core
                                                     (varint + envelope +
                                                      generic containers)
                            ▲
                            │
src/mini_blar.zig ──────────┘
  (mini_blar's higher-level FILE/DIR archive logic, built on BLIP)
```

The CLI is C and dogfoods the BLIP C FFI. mini_blar's own Zig code is a thin
layer that composes BLIP's generic ARRAY/DICT/UTF8/DATA containers into the
specific FILE/DIR shapes the spec defines, plus a Merkle hash over the
top-level archive.

## Sister project: blar

[`pmarreck/blar`](https://github.com/pmarreck/blar) — full BLAR implementation
with compression (LZMA2), encryption (AES-256-GCM), codec expansion (JXL/FLAC/
PDF/PNG/etc.), streaming creation, and a macOS GUI. mini_blar archives can be
read by blar; the converse is only true if the blar archive happens to stay
inside mini_blar's profile.

## Upstream dep: BLIP

[`pmarreck/BLIP`](https://github.com/pmarreck/BLIP) — variable-length integer
encoding + length-prefixed envelope + generic containers (ARRAY, DICT, UTF8,
DATA). mini_blar consumes a small slice of the BLIP API:
`blip_encode`/`blip_decode`, `blip_xxhash64`, the LP envelope mechanic via
`blip.container_mod`, and generic ARRAY/DICT containers via `blip.array_mod` /
`blip.dict_mod`.

## Glossary

- **BLIP**: Byte Length Integer Prefix. The varint + envelope + generic
  container library underlying both blar and mini_blar.
- **BLAR**: the archive format. Defined as a profile of BLIP containers.
- **Profile**: a constrained subset of a wire format. mini_blar's archives are
  a profile of blar archives — every mini_blar archive is a valid blar
  archive, but not vice versa.
- **FILE / DIR**: container types in the BLAR archive format defining file and
  directory entries. mini_blar handles these in their simplest form: required
  path/content/checksum, optional mtime/mode, no extras.
- **yolo**: the main branch in this and related repos. Never `main`/`master`.
