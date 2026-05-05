# mini_blar Implementation Plan

> **You are the mini_blar agent.** Your working directory is `/Users/pmarreck/Documents-CloudManaged/mini_blar/`. Your job: carve this working copy of the original BLIP umbrella down to a focused constrained-archive-only project, set up the new `pmarreck/mini_blar` GitHub repo, wire BLIP as a dep, push, tag.
>
> **Use:** `superpowers:subagent-driven-development` or `superpowers:executing-plans` to work through the tasks. Steps use `- [ ]` checkboxes.
>
> **Important — wait for upstream:** the BLIP carve-out (Phase 1 in the canonical plan) must finish before you can wire the BLIP dep. The BLIP agent's signal is **`v3.0.0` tagged on `pmarreck/BLIP`**. Until that exists, you can do Tasks 3.1, 3.3 (preparatory work that doesn't need the dep yet), but Task 3.2 (BLIP dep wiring) must wait.

## Provenance

This working copy was created on 2026-05-04 by `cp -a` from `/Users/pmarreck/Documents-CloudManaged/BLIP/` at commit `559ddbf docs(plan): lock in symbol-rename to blar_* in Phase 2`. It retains the full git history of the original BLIP umbrella.

The complete multi-phase split plan (Phases 1-4 covering all three projects) lives in `pmarreck/BLIP`'s `PLAN.md`. This file extracts and personalizes Phase 3 only.

## Goal

Take this working copy and reshape it into the `pmarreck/mini_blar` repo:
- Drop ALL BLIP-side source (varint, LP envelope, generic containers, SEGMENT primitive, comparison varints, BLIP CLIs, BLIP specs).
- Drop ALL blar-side source (`src/blar.c`, `src/streaming.zig`, `src/expansion.zig`, all codec modules, the macOS GUI app, `tests/blar_*.sh`, codec-expansion tests, etc.).
- Keep: `src/mini_blar.zig`, `src/miniblar.c`, `src/blar_common.h`, `tests/miniblar_test.sh`.
- Wire BLIP as an external dep via `build.zig.zon` + `flake.nix`.
- Trim `build.zig` to a single executable target (`miniblar`).
- Get the miniblar test suite green, push to `pmarreck/mini_blar` on `yolo` branch, tag `v3.0.0`.

mini_blar is **a sister project to blar**, not a dependency of it. blar has its own complete implementation; mini_blar has its own simpler implementation. They're related at the **spec level only** (mini_blar archives are valid blar archives if they stay within mini_blar's profile, but the code is independent).

## Pre-flight context

**Project conventions (from CLAUDE.md):**
- Main branch is **`yolo`** across all repos. Never assume `main`/`master`.
- TDD-strict: failing test first, run it, confirm fail, minimal impl, rerun, confirm pass.
- `./test` runs the full suite. `./build` builds via `nix build`. `./bm` runs benchmarks (likely none for mini_blar).
- Use `codescan` MCP tools for code work; fall back to `Read`/`Bash`/`grep` for non-indexed operations.
- Tabs over spaces. `#!/usr/bin/env <interp>` for scripts.
- **Never** use `set -euo pipefail` in test scripts (only `set -u`).
- Commit messages: no AI attribution lines.
- Garnix CI is org-wide; just having `flake.nix` with `packages` and `checks` defined enables it.
- Use `nix develop -c zig build test` for tests (not bare `zig build test`).

**The BLIP dep you'll consume:**
- Repo: `pmarreck/BLIP`
- Tag: `v3.0.0` (must exist before Task 3.2)
- Provides: `libblip.a`, `src/blip.h`, the `blip` Zig module.
- For mini_blar's use case, the relevant BLIP-provided symbols are: `blip_encode`, `blip_decode`, `blip_xxhash64`, the LP envelope mechanic via the `blip.container_mod`, generic `ARRAY`/`DICT` containers via `blip.array_mod` / `blip.dict_mod`, and `blip_to_json`/`blip_from_json` if mini_blar wants those. mini_blar does NOT use compression, encryption, codec expansion, or SEGMENT.

**mini_blar's scope (the "constrained subset" the spec talks about):**
- FILE and DIR containers only (TYPE=5, TYPE=7)
- xxhash64 checksums only (no CRC32, no BLAKE3-128)
- No COMP attribute (no compression)
- No ENC attribute (no encryption)
- No SEG attribute (no segmentation)
- No SIG attribute (no signatures)
- No container expansion (no JXL/FLAC/PDF/etc. handling)
- Reads/writes a profile of the BLAR format that any blar implementation can consume

## Phase 3 tasks

### Task 3.1: Set up mini_blar repo on GitHub

**Files:**
- Modify: `.git/config` (remote URL)
- Create: `pmarreck/mini_blar` on GitHub

- [x] **Step 1: Create the GitHub repo** (2026-05-04 EST)

```bash
gh repo create pmarreck/mini_blar --public --description "Constrained subset of the BLAR archive format — for embedded/bootstrap use" --no-readme
```

- [x] **Step 2: Set the new remote** (2026-05-04 EST)

```bash
git remote set-url origin git@github.com:pmarreck/mini_blar.git
git branch -M yolo
git push -u origin yolo
```

- [x] **Step 3: Verify** (2026-05-04 EST)

```bash
git remote -v
git log -1 --oneline
```

Expected: remote = `pmarreck/mini_blar`, HEAD = the commit you started on (`559ddbf` or similar).

### Task 3.2: Wait for BLIP `v3.0.0`, then add it as a dep

**Wait condition:** `gh release view v3.0.0 --repo pmarreck/BLIP --json tagName --jq .tagName` returns `v3.0.0`.

- [x] **Step 1: Verify BLIP `v3.0.0` exists** (2026-05-05 EST)

```bash
until gh release view v3.0.0 --repo pmarreck/BLIP --json tagName --jq .tagName 2>/dev/null | grep -q v3.0.0; do
    echo "Waiting for BLIP v3.0.0 tag…"
    sleep 60
done
echo "BLIP v3.0.0 is published. Proceeding."
```

- [x] **Step 2: Add BLIP to `build.zig.zon`** (2026-05-05 EST)

In `build.zig.zon`, add a `blip` entry to `.dependencies`:
```zig
.dependencies = .{
    .blip = .{
        .url = "https://github.com/pmarreck/BLIP/archive/refs/tags/v3.0.0.tar.gz",
        .hash = "",  // see Step 4
    },
},
```

(mini_blar likely has no other deps. The original BLIP umbrella's other deps — libmagic, libjxl, libflac, etc. — are codec-related and don't apply.)

- [x] **Step 3: Add BLIP as a Nix flake input** (2026-05-05 EST)

In `flake.nix`:
```nix
inputs.blip.url = "github:pmarreck/BLIP/v3.0.0";
inputs.blip.inputs.nixpkgs.follows = "nixpkgs";
```

- [x] **Step 4: Hash the dep** (2026-05-05 EST)

```bash
nix build 2>&1 | tail -10
```

Copy the printed `got: sha256-...` value into `build.zig.zon` and `flake.nix` if needed. (See `fix-zig-deps-hash` skill if it gets fiddly.)

- [x] **Step 5: Commit** (2026-05-05 EST)

```bash
git add build.zig.zon flake.nix flake.lock
git commit -m "chore(split): add BLIP v3.0.0 as external dep"
```

### Task 3.3: Remove everything that isn't mini_blar

**Files to KEEP:**
- `src/mini_blar.zig`
- `src/miniblar.c`
- `src/blar_common.h` (shared utilities — read_file, mkdirp, etc.)
- `tests/miniblar_test.sh`
- `flake.nix`, `build.zig`, `build.zig.zon`, `./build`, `./test`
- `LICENSE`

**Files to DELETE: everything else** (BLIP-side, blar-side, codec-side, GUI, irrelevant tests, irrelevant specs).

- [x] **Step 1: Delete BLIP-side files** (2026-05-05 EST)

```bash
git rm src/blip.zig src/blip.h \
       src/container_types.zig src/container.zig \
       src/checksum.zig src/leaf.zig src/array.zig src/dict.zig \
       src/peek.zig src/poke.zig \
       src/segmentation.zig \
       src/encoding.zig src/leb128.zig src/protobuf_varint.zig src/asn1_length.zig \
       src/prefix_varint.zig src/sqlite_varint.zig src/bignum.zig src/fuzz.zig \
       src/benchmark.zig src/main.zig \
       BLIP_SPEC.md BLIP_SPEC_CONCISE.md BLIP_CONTAINER_SPEC.md BLIP_SIGIL_REGISTRY.md \
       docs/transport_embedding.md \
       tests/peek_test.sh tests/poke_test.sh tests/json_test.sh \
       tests/binary_format_test.sh tests/text_roundtrip_test.sh tests/tri_representation_test.sh
```

(If `BLIP_SIGIL_REGISTRY.md` doesn't exist yet, ignore — it's created during BLIP's Phase 1.)

- [x] **Step 2: Delete blar-side files (codecs, archive impl, GUI, archive tests)** (2026-05-05 EST)

```bash
git rm src/blar.c src/streaming.zig src/expansion.zig src/lib.zig \
       src/jxl.zig src/flac.zig src/pdf.zig src/png.zig src/bmp.zig \
       src/tar.zig src/tiff.zig src/gif.zig src/tga.zig src/wav.zig \
       src/aiff.zig src/fits.zig src/dicom.zig src/nifti.zig src/zip.zig \
       tests/blar_test.sh tests/blar_full_test.sh tests/segmentation_test.sh \
       tests/compression_test.sh tests/encryption_test.sh \
       tests/container_expansion_test.sh tests/container_expansion_dual_test.sh \
       tests/pdf_container_test.sh tests/png_container_test.sh \
       tests/streaming_test.sh tests/explode_implode_test.sh
git rm -r macos-app
```

(If any of these paths don't exist, the `git rm` will fail for that path; ignore individual not-found errors and re-list what's left.)

- [x] **Step 3: Verify what's left** (2026-05-05 EST)

```bash
ls src/
ls tests/
```

Expected:
- `src/`: `mini_blar.zig`, `miniblar.c`, `blar_common.h` (just three files)
- `tests/`: `miniblar_test.sh` (just one)

- [x] **Step 4: Audit for unexpected files at top level** (2026-05-05 EST)

```bash
ls
```

Drop any unexpected directories or files (e.g., leftover `inbox/`, `bench/`, etc.) that are BLIP-umbrella artifacts not relevant to mini_blar. Keep: `flake.nix`, `flake.lock`, `build.zig`, `build.zig.zon`, `./build`, `./test`, `LICENSE`, `README.md`, `CLAUDE.md`, `PLAN.md` (this file), `PROJECT_OVERVIEW.md`, `CODE_MINIMAP.md`.

- [x] **Step 5: Commit** (2026-05-05 EST)

```bash
git add -A
git commit -m "chore(split): mini_blar gets only the constrained-subset impl"
```

### Task 3.4: Trim `build.zig` to a single binary target

**Files:**
- Modify: `build.zig`

The current `build.zig` defines several targets (libblip, blar, miniblar, blip-bench, etc.). Reduce to one executable.

- [x] **Step 1: Reduce `build.zig` to the miniblar-only shape** (2026-05-05 EST)

Replace the contents with (sketch):
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseFast)") orelse .ReleaseFast;

    const blip_dep = b.dependency("blip", .{
        .target = target,
        .optimize = optimize,
    });

    const mini_blar_module = b.createModule(.{
        .root_source_file = b.path("src/mini_blar.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "blip", .module = blip_dep.module("blip") },
        },
    });

    const miniblar = b.addExecutable(.{
        .name = "miniblar",
        .root_module = mini_blar_module,
    });
    miniblar.linkLibrary(blip_dep.artifact("blip"));
    miniblar.addIncludePath(blip_dep.path("src"));
    miniblar.addCSourceFile(.{ .file = b.path("src/miniblar.c") });
    b.installArtifact(miniblar);

    // Tests
    const tests = b.addTest(.{
        .root_module = mini_blar_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

(Tweak as needed — the actual existing `build.zig` may have a different structure, but this is the target shape.)

- [x] **Step 2: Verify the build** (2026-05-05 EST)

```bash
nix develop -c zig build -Doptimize=ReleaseFast 2>&1 | tail -3
ls zig-out/bin/
```

Expected: `zig-out/bin/miniblar` only.

- [x] **Step 3: Run tests** (2026-05-05 EST)

```bash
nix develop -c zig build test 2>&1 | grep -E "tests passed|failed"
bash tests/miniblar_test.sh 2>&1 | tail -5
```

- [x] **Step 4: Fix any failures** (2026-05-05 EST)

Common likely failures:
- **Missing imports of `blip` module** in `src/mini_blar.zig` → change `@import("blip.zig")` to `@import("blip")`.
- **Removed local types** referenced from `mini_blar.zig` → e.g., if it imported `ChecksumId` from `container_types.zig`, that now lives in `blip.container_types_mod.ChecksumId`.
- **C side missing `blip.h`** in `miniblar.c` → make sure `addIncludePath(blip_dep.path("src"))` is in the build.zig.
- **Test fixtures** → if `miniblar_test.sh` references sample files, make sure they're still present.

- [x] **Step 5: Commit** (2026-05-05 EST)

```bash
git add -A
git commit -m "chore(split): trim build.zig to single miniblar binary"
```

### Task 3.5: Trim master test runner and any `./build`/`./bm` scripts

The original BLIP umbrella has a `./test` script that runs many test suites. mini_blar only needs `tests/miniblar_test.sh`.

- [x] **Step 1: Trim `./test`** (2026-05-05 EST)

Reduce the master `./test` to just:
```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_FAIL=0

run_suite() {
    local name="$1"
    local cmd="$2"
    echo "━━━ $name ━━━"
    eval "$cmd"
    local rc=$?
    if [[ $rc -ne 0 ]]; then TOTAL_FAIL=$((TOTAL_FAIL + 1)); fi
}

cd "$SCRIPT_DIR"
echo "Building..."
nix develop -c zig build -Doptimize=ReleaseFast 2>/dev/null \
    || { echo "FATAL: build failed"; exit 1; }

run_suite "Zig Unit Tests" "nix develop -c zig build test 2>&1"
run_suite "miniblar CLI Tests" "bash tests/miniblar_test.sh"

echo ""
echo "TOTAL: $TOTAL_FAIL failed"
exit $TOTAL_FAIL
```

- [x] **Step 2: Trim `./build`** (2026-05-05 EST)

Reduce to:
```bash
#!/usr/bin/env bash
set -u

case "${1:-}" in
    --debug) MODE="Debug" ;;
    --test)  MODE="Debug"; TEST=1 ;;
    *)       MODE="ReleaseFast" ;;
esac

if [[ -n "${TEST:-}" ]]; then
    nix develop -c zig build test -Doptimize="$MODE"
else
    nix build .#default
fi
```

- [x] **Step 3: Remove `./bm` if present** (2026-05-05 EST)

mini_blar likely has no benchmarks of its own (it's a constrained subset). Remove `./bm` and `bench/` if present.

```bash
git rm -f bm
git rm -rf bench 2>/dev/null || true
```

- [x] **Step 4: Commit** (2026-05-05 EST)

```bash
git add -A
git commit -m "chore(split): trim test/build/bm scripts to mini_blar scope"
```

### Task 3.6: Update top-level docs

- [x] **Step 1: README.md** (2026-05-05 EST)

Replace with:
```markdown
# mini_blar

A constrained subset of the [blar](https://github.com/pmarreck/blar) archive
format, suitable for embedded systems, bootstrap environments, and any context
where the full blar feature set (compression, encryption, codec expansion, etc.)
is overkill.

mini_blar archives are valid blar archives — any blar implementation can read
them.  But mini_blar's writer only emits a profile of the format, and its
reader only handles that profile.

Built on [BLIP](https://github.com/pmarreck/BLIP).

## Profile

mini_blar archives:
- May contain FILE and DIR entries
- Use only TYPE, CSUM, VAL attributes (no COMP, ENC, SEG, SIG)
- Use only xxhash64 for content checksums
- Have no compression, no encryption, no container expansion

If you need any of those, use blar.

## Build

```bash
./build       # release
./test        # run tests
```
```

- [x] **Step 2: PROJECT_OVERVIEW.md** (2026-05-05 EST)

Brief description of mini_blar's design and constraints. Cross-ref blar and BLIP.

- [x] **Step 3: CLAUDE.md** (2026-05-05 EST)

Trim to mini_blar-only context. Drop varint/codec/etc. discussion.

- [x] **Step 4: CODE_MINIMAP.md** (2026-05-05 EST)

Document the three source files: `mini_blar.zig`, `miniblar.c`, `blar_common.h`.

- [x] **Step 5: Commit** (2026-05-05 EST)

```bash
git add README.md PROJECT_OVERVIEW.md CLAUDE.md CODE_MINIMAP.md
git commit -m "docs(split): mini_blar top-level docs"
```

### Task 3.7: Push and tag

- [x] **Step 1: Push** (2026-05-05 EST)

```bash
git push origin yolo
sleep 5
curl -s "https://garnix.io/api/badges/pmarreck/mini_blar?branch=yolo" | head -1
```

Expected: green build status.

- [x] **Step 2: Tag** (2026-05-05 EST)

```bash
git tag v3.0.0
git push origin v3.0.0
```

## Acceptance criteria (Phase 3)

A successful completion of Phase 3 means:
1. ✅ `pmarreck/mini_blar` repo exists on GitHub with full pre-split git history retained
2. ✅ `flake.nix`, `build.zig`, `./test`, `./build` all self-contained and minimal
3. ✅ mini_blar consumes BLIP via `build.zig.zon` + flake input
4. ✅ Garnix CI green on yolo
5. ✅ Tagged `v3.0.0`
6. ✅ `src/` contains only: `mini_blar.zig`, `miniblar.c`, `blar_common.h`
7. ✅ `tests/` contains only: `miniblar_test.sh`
8. ✅ All miniblar tests green
9. ✅ Top-level docs reflect mini_blar's constrained-subset scope and cross-reference blar/BLIP
10. ✅ No code-level dependency on blar (mini_blar is a sister project, not a child)

## Open questions

- (none — every decision in the plan has a recommendation. If a recommendation turns out to be wrong, push back via Peter rather than guessing.)

## Glossary

- **mini_blar**: this project. A constrained profile of blar's format with an independent impl. Embedded/bootstrap use.
- **BLIP**: the upstream dep at `pmarreck/BLIP`. Provides varint, LP envelope, generic containers, peek/poke navigation. mini_blar uses a small slice of the BLIP API (encode/decode + DICT/ARRAY/UTF8/DATA + xxhash64).
- **blar**: the sister project at `pmarreck/blar`. The full BLAR archive format with codec expansion, compression, encryption, and the macOS GUI app. mini_blar does NOT depend on blar.
- **yolo**: the main branch. Never `main`/`master`.
- **Profile**: a constrained subset of a wire format. mini_blar archives are a profile of blar archives — every mini_blar archive is a valid blar archive, but not vice versa.
- **FILE/DIR**: container types (TYPE=5 and TYPE=7) defining file and directory entries with metadata. mini_blar handles these in their simplest form: required path/content/checksum, optional mtime/mode, no compression/encryption.
