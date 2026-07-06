---
purpose: Environment/tooling facts learned while working in this repo
audience: agent
maintained_by: agent
---

# Learnings

## Zig 0.16 project-local package store: `zig-pkg/`

This repo vendors its Zig deps **in-tree** under `zig-pkg/<name-version-hash>/`
(blip, zstdz), and Zig 0.16 resolves deps from there with priority over the
global cache. Consequences:

- Sandboxed Nix builds need NO network and NO fixed-output derivation. The
  fleet-standard "Strategy 1 zigDeps FOD" in the flake was **vestigial and
  unbuildable** here (`zig build --fetch=all` fetched nothing → `zig-cache/p`
  never created → installPhase cp failed); it only appeared to work because
  its old output was still substitutable from the Garnix cache. Removed
  2026-07-06.
- Adding a dep = `zig fetch <url>` (records hash for build.zig.zon), then let
  a build unpack it into `zig-pkg/`, then commit that directory (jj
  auto-snapshots it).

## Nix sandbox can't spawn glibc-dynamic Zig test binaries

A test binary that links libc (e.g. via a C codec dep) is dynamically linked
against `/lib64/ld-linux-*`, which doesn't exist in the sandbox → zig build
runner dies with `FileNotFound` at spawn. Two known fixes:
- **musl target** for the check (`-Dtarget=<arch>-linux-musl`) → fully static,
  nothing to patch (what mini_blar's `checks.test-compression` does);
- **patchelf dance** (build test exes, patchelf interpreter, re-run) — what
  zstdz@2110c2c does; needs a `build_tests` step.

## jj repo-config trust file can go missing

`jj status` died with "Cannot access ~/.config/jj/repos/<hash>/config.toml".
The dir existed (with metadata.binpb) but the config.toml was gone. `touch`ing
an empty config.toml fixed it; jj then noted the repo "appears to have been
copied from ~/Code/BLIP/.jj" — an artifact of this repo's cp -a provenance.

## ISA-poisoning guard: `-Dcpu=baseline` on every Nix-built artifact

Garnix builders may have AVX-512; a natively-detected build bakes those
instructions into cache-shared binaries which SIGILL on Zen 2 (Threadripper
3990X). All flake build/check phases pass `-Dcpu=baseline` (mirrors
zstdz@0a478bb, which also carries an objdump-based `isa-baseline` check).
