---
purpose: Work items / roadmap for mini_blar (checkboxes, most recent first)
audience: both
maintained_by: agent
---

# mini_blar Plan

## Optional zstd compression (validate_gui launcher request, 2026-07-06)

Requested via inbox by validate_gui@thelio-pm: single-binary launcher embeds a
137 MB archive and wants it zstd-compressed **in-format** (comp_id=zstd), not
bolted on outside. Design: activate the existing `compression_mod` hook +
`enable_compression` build flag with a zstd-ONLY module (no multi-codec
dispatch; default build keeps the no-op stub → zero codecs linked).

- [x] Study contract: call sites, blar's compression.zig zstd slice, zstdz module API (2026-07-06 ~2:40 PM EST)
- [x] build.zig: `-Denable_compression` (default false) + `-Dzstd_level` (default 19); lazy `zstdz` dep pinned at 46a916ab (≥0a478bb baseline-ISA fix) (2026-07-06 ~2:45 PM EST)
- [x] TDD red: rewrite gated tests for zstd-only (round-trip, verifyFileAt-before-decompress, corruption→HashMismatch, non-zstd→UnsupportedCompression); confirmed 4 failures against skeleton (2026-07-06 ~2:43 PM EST)
- [x] Implement `src/compression_zstd.zig` (port of blar's zstd arms; wrapper LP `CSUM=xxhash64` per profile — not blar's blake3_128); stub kept as signature twin; 28/28 stub + 33/33 zstd tests green (2026-07-06 ~2:50 PM EST)
- [x] flake.nix: removed vestigial zigDeps FOD (deps are vendored in `zig-pkg/`; FOD had been unbuildable since vendoring, surviving on cache substitution only); `-Dcpu=baseline` on all builds/checks (ISA-poisoning guard, cf. zstdz@0a478bb); new `checks.test-compression` (musl-targeted on Linux so the libc-linked test exe spawns in the sandbox) (2026-07-06 ~3:00 PM EST)
- [x] `./test` runs both profiles; full suite green (2026-07-06 ~3:05 PM EST)
- [x] Push, Garnix green 5/5 (incl. new `test-compression` check) (2026-07-06 ~3:05 PM EST)
- [x] Reply to validate_gui (LLMsend note + ping; local session — "thelio-pm" == this box) (2026-07-06 ~3:10 PM EST)

## Per-entry MT zstd (Peter + validate_gui request, 2026-07-07)

- [x] Enable zstd nbWorkers on the per-entry path: entries ≥8 MB take the MT
      path with min(num_threads, 8) workers + pinned 8 MB jobSize; <8 MB
      always single-thread. Path selected by SIZE only → bytes independent
      of num_threads (invariant test held before AND after — zstd 1.6.0
      emits identical ST/MT-path bytes for our params, so archives are
      byte-identical to the previous rev). Probe: 36 MB level-19 15.0s → 3.65s
      (4.11×). serializeFileEntry gained a num_threads param. (2026-07-07 ~1:55 PM EST)
- [ ] Push, CI green, notify validate_gui (expect their 12.1s pack → ~3-4s)

## Backlog (optional)

- [ ] Bump blip dep v3.1.0 → v3.2.0: free `DictReader.findKey` O(n log n)
      speedup (was O(n²)), opt-in `DictIndex`; no wire change, backward
      compatible (per BLIP's 2026-06-02 inbox note). Low priority — our
      metadata dicts are small.

**Interface contract promised to validate_gui (keep stable):**
`createArchive`/`createFullArchive` accept per-entry `comp_id=.zstd`;
`ArchiveReader.fileContentDecompress(idx, allocator)` transparently
decompresses; `verifyFileAt(idx)` (xxhash64) verifies stored/compressed bytes
BEFORE decompression.

## Continuity: previously completed

- [x] Phase 3 split (BLIP umbrella → focused mini_blar repo): repo created,
      BLIP dep wired, non-mini_blar sources removed, build.zig/test/build
      trimmed, docs rewritten, pushed + tagged v3.0.0, Garnix green
      (2026-05-04 → 2026-05-05 EST; full details in jj log)
- [x] Zig deps vendored in-tree under `zig-pkg/` (blip; now also zstdz)
- [x] GitHub Actions bumped for Node 24; Zig 0.16 pinned via zig-overlay

## Open questions

- (none)
