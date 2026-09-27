# Compression context

Moved from PLAN.md during branch reconciliation on 2026-09-27.

Requested via inbox by validate_gui@thelio-pm: single-binary launcher embeds a
137 MB archive and wants it zstd-compressed **in-format** (comp_id=zstd), not
bolted on outside. Design: activate the existing `compression_mod` hook +
`enable_compression` build flag with a zstd-ONLY module (no multi-codec
dispatch; default build keeps the no-op stub → zero codecs linked).

**Interface contract promised to validate_gui (keep stable):**
`createArchive`/`createFullArchive` accept per-entry `comp_id=.zstd`;
`ArchiveReader.fileContentDecompress(idx, allocator)` transparently
decompresses; `verifyFileAt(idx)` (xxhash64) verifies stored/compressed bytes
BEFORE decompression.
