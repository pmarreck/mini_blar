# PLAN

Completed history: [docs/PLAN_LOG.md](docs/PLAN_LOG.md). Compression context and interface contract: [docs/plan_context/compression.md](docs/plan_context/compression.md).

## Branch reconciliation

- [x] Restore checkout to yolo and commit staged documentation links; fetched origin/yolo matched ca14739, latest jj snapshots were identical, and the xattr branch was already merged; nix develop -c ./test and ./build passed (afc35b6; done 2026-09-27 16:15 EDT).

## Optional zstd compression (validate_gui launcher request, 2026-07-06)

- [x] Reply to validate_gui (LLMsend note + ping; local session — "thelio-pm" == this box) (2026-07-06 ~3:10 PM EST)

## Per-entry MT zstd (Peter + validate_gui request, 2026-07-07)

- [x] Enable zstd nbWorkers on the per-entry path: entries ≥8 MB take the MT path with min(num_threads, 8) workers + pinned 8 MB jobSize; <8 MB always single-thread. Path selected by SIZE only → bytes independent of num_threads (invariant test held before AND after — zstd 1.6.0 emits identical ST/MT-path bytes for our params, so archives are byte-identical to the previous rev). Probe: 36 MB level-19 15.0s → 3.65s (4.11×). serializeFileEntry gained a num_threads param. (2026-07-07 ~1:55 PM EST)
- [x] Push, Garnix 5/5 green, validate_gui notified (rev 50bc69f75540; expect their 12.1s pack → ~3-4s; awaiting their re-measure) (2026-07-07 ~2:15 PM EST)

## Backlog (optional)

- [ ] Bump blip dep v3.1.0 → v3.2.0: free `DictReader.findKey` O(n log n) speedup (was O(n²)), opt-in `DictIndex`; no wire change, backward compatible (per BLIP's 2026-06-02 inbox note). Low priority — our metadata dicts are small.
