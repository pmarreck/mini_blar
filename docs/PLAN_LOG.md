# PLAN log

Completed PLAN.md items retired by plan-retire, oldest retirement first.

## Retired 2026-09-27

- [x] [Optional zstd compression (validate_gui launcher request, 2026-07-06)] Study contract: call sites, blar's compression.zig zstd slice, zstdz module API (2026-07-06 ~2:40 PM EST)
- [x] [Optional zstd compression (validate_gui launcher request, 2026-07-06)] build.zig: `-Denable_compression` (default false) + `-Dzstd_level` (default 19); lazy `zstdz` dep pinned at 46a916ab (≥0a478bb baseline-ISA fix) (2026-07-06 ~2:45 PM EST)
- [x] [Optional zstd compression (validate_gui launcher request, 2026-07-06)] TDD red: rewrite gated tests for zstd-only (round-trip, verifyFileAt-before-decompress, corruption→HashMismatch, non-zstd→UnsupportedCompression); confirmed 4 failures against skeleton (2026-07-06 ~2:43 PM EST)
- [x] [Optional zstd compression (validate_gui launcher request, 2026-07-06)] Implement `src/compression_zstd.zig` (port of blar's zstd arms; wrapper LP `CSUM=xxhash64` per profile — not blar's blake3_128); stub kept as signature twin; 28/28 stub + 33/33 zstd tests green (2026-07-06 ~2:50 PM EST)
- [x] [Optional zstd compression (validate_gui launcher request, 2026-07-06)] flake.nix: removed vestigial zigDeps FOD (deps are vendored in `zig-pkg/`; FOD had been unbuildable since vendoring, surviving on cache substitution only); `-Dcpu=baseline` on all builds/checks (ISA-poisoning guard, cf. zstdz@0a478bb); new `checks.test-compression` (musl-targeted on Linux so the libc-linked test exe spawns in the sandbox) (2026-07-06 ~3:00 PM EST)
- [x] [Optional zstd compression (validate_gui launcher request, 2026-07-06)] `./test` runs both profiles; full suite green (2026-07-06 ~3:05 PM EST)
- [x] [Optional zstd compression (validate_gui launcher request, 2026-07-06)] Push, Garnix green 5/5 (incl. new `test-compression` check) (2026-07-06 ~3:05 PM EST)
- [x] [Continuity: previously completed] Phase 3 split (BLIP umbrella → focused mini_blar repo): repo created, BLIP dep wired, non-mini_blar sources removed, build.zig/test/build trimmed, docs rewritten, pushed + tagged v3.0.0, Garnix green (2026-05-04 → 2026-05-05 EST; full details in jj log)
- [x] [Continuity: previously completed] Zig deps vendored in-tree under `zig-pkg/` (blip; now also zstdz)
- [x] [Continuity: previously completed] GitHub Actions bumped for Node 24; Zig 0.16 pinned via zig-overlay

## Retired 2026-10-14

- [x] [Branch reconciliation] Add Mechatron targets and README badge after e76a6c9 exposed the missing manifest; the existing Linux package and both test profiles passed direct Nix builds (done 2026-09-27 16:19 EDT).
- [x] [Branch reconciliation] Restore checkout to yolo and commit staged documentation links; fetched origin/yolo matched ca14739, latest jj snapshots were identical, and the xattr branch was already merged; nix develop -c ./test and ./build passed (afc35b6; done 2026-09-27 16:15 EDT).
- [x] [Optional zstd compression] Notify the downstream launcher consumer of the shipped compression profile (2026-07-06 ~3:10 PM EST).
- [x] [Per-entry MT zstd] Enable zstd nbWorkers on the per-entry path: entries ≥8 MB take the MT path with min(num_threads, 8) workers + pinned 8 MB jobSize; <8 MB always single-thread. Path selected by SIZE only → bytes independent of num_threads (invariant test held before AND after; zstd 1.6.0 emits identical ST/MT-path bytes for these parameters, so archives are byte-identical to the previous revision). Probe: 36 MB level-19 15.0s → 3.65s (4.11×). serializeFileEntry gained a num_threads parameter (2026-07-07 ~1:55 PM EST).
- [x] [Per-entry MT zstd] Push 50bc69f75540, pass the then-active CI checks 5/5, and notify the downstream launcher consumer; its later remeasurement reported 12.1s → 5.98s for 34 MB + 14 MB binaries at level 19 (notification 2026-07-07 ~2:15 PM EST; remeasurement 2026-07-07).
