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

mini_blar archives:

- May contain `FILE` and `DIR` entries (TYPE=5, TYPE=7)
- Use only `TYPE`, `CSUM`, `VAL` attributes (no `COMP`, `ENC`, `SEG`, `SIG`)
- Use only `xxhash64` for content checksums
- Have no compression, no encryption, no container expansion

If you need any of those, use blar.

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
