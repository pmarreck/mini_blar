# mini_blar

A constrained subset of the [blar](https://github.com/pmarreck/blar) archive
format — for embedded systems, bootstrap environments, and any context where
the full blar feature set (compression, encryption, codec expansion, signatures)
is overkill.

mini_blar archives are valid blar archives: any blar implementation can read
them. mini_blar's writer only emits a profile of the format, and its reader
only handles that profile.

Built on [BLIP](https://github.com/pmarreck/BLIP).

## Profile

mini_blar archives (default profile):

- May contain `FILE` and `DIR` entries (TYPE=5, TYPE=7)
- Use only `TYPE`, `CSUM`, `VAL` attributes (no `COMP`, `ENC`, `SEG`, `SIG`)
- Use only `xxhash64` for content checksums
- Have no compression, no encryption, no container expansion

If you need any of those, use blar — with one exception:

### Optional zstd compression (`-Denable_compression=true`)

For self-extracting / single-binary-launcher use cases (e.g. validate_gui
embedding executables in an appended archive), mini_blar can be built with
exactly one codec:

```bash
zig build -Denable_compression=true            # link zstd, allow COMP=zstd
zig build -Denable_compression=true -Dzstd_level=22   # override level (default 19)
```

- Per-file compression via `createFullArchive(..., comp_id = .zstd, ...)`;
  reads are transparent through `ArchiveReader.fileContentDecompress`.
- The compressed wrapper container stays inside the profile's checksum rule:
  `CSUM=xxhash64` over the stored (compressed) bytes, so `verifyFileAt`
  verifies **before** decompression.
- Any comp_id other than `.zstd` → `error.UnsupportedCompression`. One codec,
  no runtime dispatch.
- The default build links **zero** codecs — the no-op stub keeps mini_blar
  truly minimal (dead-code elimination strips everything).
- The zstd level is baked at build time (compress once at build, decompress
  on every launch → bias for ratio; zstd decompress speed is
  ~level-independent).

## Build

```bash
./build         # release (via nix build)
./build debug   # debug (via zig build)
./test          # run unit + CLI tests
```

## Relationship to blar and BLIP

```
                        ┌──────────┐
                        │   BLIP   │  varint + LP envelope + generic containers
                        └────┬─────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
       ┌─────────────┐              ┌──────────────┐
       │  mini_blar  │              │     blar     │
       │  (this)     │              │  (sister)    │
       └─────────────┘              └──────────────┘
       constrained                  full feature set
       FILE/DIR only                + codecs, comp, enc
       xxhash64 only                + GUI, signatures
```

mini_blar and blar are **sister projects**. mini_blar does not depend on blar.
Both depend on BLIP. The two impls share a wire-format profile, not code.

## License

See [LICENSE](LICENSE).
