---
purpose: Log of agent mistakes in this repo, for periodic en-masse workflow review
audience: agent
maintained_by: agent
---

# Mistakes

## 2026-07-07 — amplified an unverified consumer claim into the README

validate_gui's reply asserted "multi-thread zstd makes the archive bytes
non-deterministic build-to-build"; I documented it as a README caveat without
verifying. Einstein challenged it with primary sources (zstd#2079: MT output
is deterministic AND thread-count-independent by design; the historical
nondeterminism bugs #1077/#2327 were fixed by v1.4.7; we vendor v1.6.0), and
a local experiment refuted it: num_threads 2/8/auto produce byte-identical
output, and threads=1 vs threads=8 archives are byte-identical (per-entry
zstd is always single-threaded here anyway — serializeFileEntry pins it).
Now encoded as three permanent regression tests. Lessons:
1. **Negative capability claims ("X is nondeterministic") get a repro before
   they get documented** — they're cheap to test and expensive to spread.
2. The consumer who reports a property of YOUR system is still a producer of
   claims — maker≠checker applies to documentation too.
3. When correcting, encode the corrected belief as a test, not just prose.

## 2026-07-06 — stub/real module signature drift caused unreachable-else

Added an `error.UnsupportedCompression` arm to `serializeFileEntry`'s
catch-switch while the stub's `compressContainer` still returned the narrow
`CompressionError![]u8`. With the stub selected, all three errors in the set
had explicit arms → Zig rejected the now-unreachable `else` prong → default
profile stopped compiling (caught immediately because I ran BOTH profiles).
Lesson: when two modules are comptime-swapped behind one name, keep them
**signature twins** — same param types, same return-type error union — and
verify every change under both build flags before moving on.

## 2026-07-06 — `nix build ... | tail && echo OK` swallowed a failure

Piping `nix build` through `tail` made the pipeline's exit status be tail's
(0), so the `&&` success marker printed even though the build FAILED.
Lesson: when a command's exit code matters, test `${PIPESTATUS[0]}` (or don't
pipe). The follow-up run did it right and exposed the real failure.
