# Validation reporting boundary

Reviewed against the downstream validation guidance received on 2026-10-14.

The current C interface in `src/blar.h` exposes boolean archive verification
and numeric `BLAR_ERR_*` results. `blar_archive_file_verify` distinguishes
hash mismatch from mapped parse errors; it does not return a detailed
finding record or byte offset. No richer diagnostic contract is claimed.

Downstream applications own verdict classification. Reader tolerance does
not excuse a proven integrity violation. An admitted producer-defect pattern
requires the consumer's finite registry; mini_blar must not invent a
`KNOWN_DEFECT` result or reuse a validation-depth label as a library status.
Implementation limits describe what was examined, not damage to the input.

A future detailed-finding interface must use a published consumer contract,
typed reasons, and measured offsets. Unknown locations must remain explicitly
unknown. Preserve the current ABI until that extension is specified and tested.

The downstream terminology update was still a candidate on 2026-10-14;
the published checkout retained older classification wording. Resolve the
current candidate with its maintainer before changing verdict routing. This
review changes documentation only. No stale reader-tolerance severity rule
was found in the project's current documentation.
