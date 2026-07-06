---
purpose: Log of agent mistakes in this repo, for periodic en-masse workflow review
audience: agent
maintained_by: agent
---

# Mistakes

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
