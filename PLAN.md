# PLAN

Completed history: [docs/PLAN_LOG.md](docs/PLAN_LOG.md). Compression context and interface contract: [docs/plan_context/compression.md](docs/plan_context/compression.md).

## Inbox reconciliation

- [x] Reconcile two inbox notes, retire five completions, and document the existing validation ABI; documentation checks passed and executable inputs remain identical to CI-passing 6414cfc (context: docs/plan_context/validation-contract.md; done 2026-10-14 14:38 EDT).

## Dependency freshness

- [x] Verify BLIP, zstdz, Nix lock inputs, and GitHub Actions against upstream heads; retain Zig 0.16.0 under the series policy and refresh nixpkgs-unstable (0d06d2a; done 2026-10-08 20:55 EDT).
- [x] Adopt BLIP containerAt and replace vendored packages with upstream hash-verified contents; full tests, optimized build, Linux Nix checks, and all-system flake evaluation passed (0d06d2a; done 2026-10-08 20:55 EDT).

- [x] Update BLIP from v3.1.0 to upstream HEAD 5128c62, including faster DictReader.findKey and optional DictIndex (0d06d2a; done 2026-10-08 20:55 EDT).
