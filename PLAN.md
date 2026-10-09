# PLAN

Completed history: [docs/PLAN_LOG.md](docs/PLAN_LOG.md). Compression context and interface contract: [docs/plan_context/compression.md](docs/plan_context/compression.md).

## Dependency freshness

- [x] Verify BLIP, zstdz, Nix lock inputs, and GitHub Actions against upstream heads; retain Zig 0.16.0 under the series policy and refresh nixpkgs-unstable (0d06d2a; done 2026-10-08 20:55 EDT).
- [x] Adopt BLIP containerAt and replace vendored packages with upstream hash-verified contents; full tests, optimized build, Linux Nix checks, and all-system flake evaluation passed (0d06d2a; done 2026-10-08 20:55 EDT).

## Branch reconciliation

- [x] Add Mechatron targets and README badge after e76a6c9 exposed the missing manifest; the existing Linux package and both test profiles passed direct Nix builds (done 2026-09-27 16:19 EDT).
- [x] Restore checkout to yolo and commit staged documentation links; fetched origin/yolo matched ca14739, latest jj snapshots were identical, and the xattr branch was already merged; nix develop -c ./test and ./build passed (afc35b6; done 2026-09-27 16:15 EDT).

## Optional zstd compression (validate_gui launcher request, 2026-07-06)

- [x] Reply to validate_gui (LLMsend note + ping; local session — "thelio-pm" == this box) (2026-07-06 ~3:10 PM EST)

## Per-entry MT zstd (Peter + validate_gui request, 2026-07-07)

- [x] Enable zstd nbWorkers on the per-entry path: entries ≥8 MB take the MT path with min(num_threads, 8) workers + pinned 8 MB jobSize; <8 MB always single-thread. Path selected by SIZE only → bytes independent of num_threads (invariant test held before AND after — zstd 1.6.0 emits identical ST/MT-path bytes for our params, so archives are byte-identical to the previous rev). Probe: 36 MB level-19 15.0s → 3.65s (4.11×). serializeFileEntry gained a num_threads param. (2026-07-07 ~1:55 PM EST)
- [x] Push, Garnix 5/5 green, validate_gui notified (rev 50bc69f75540; expect their 12.1s pack → ~3-4s; awaiting their re-measure) (2026-07-07 ~2:15 PM EST)

## Backlog (optional)

- [x] Update BLIP from v3.1.0 to upstream HEAD 5128c62, including faster DictReader.findKey and optional DictIndex (0d06d2a; done 2026-10-08 20:55 EDT).
