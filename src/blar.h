/*
 * blar.h — C FFI for mini_blar.
 *
 * Re-exports the archive operations from src/c_api.zig.
 */
#ifndef MINI_BLAR_BLAR_H
#define MINI_BLAR_BLAR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Error codes ──────────────────────────────────────────────────────── */
#define BLAR_OK                  0
#define BLAR_ERR_INVALID        -1
#define BLAR_ERR_BOUNDS         -2
#define BLAR_ERR_NOT_FOUND      -3
#define BLAR_ERR_HASH_MISMATCH  -4
#define BLAR_ERR_ALLOC          -5
#define BLAR_ERR_INVALID_MAGIC  -6
#define BLAR_ERR_IO             -7

/* ── Flags ────────────────────────────────────────────────────────────── */
#define BLAR_ARCHIVE_ABSOLUTE_PATHS  (1u << 0)

/* ── Container type IDs ───────────────────────────────────────────────── */
#define BLAR_TYPE_FILE  5
#define BLAR_TYPE_DIR   7

/* ── Input structs ────────────────────────────────────────────────────── */

typedef struct {
    const uint8_t *name;
    size_t name_len;
    const uint8_t *value;
    size_t value_len;
} blar_xattr_entry;

typedef struct {
    const uint8_t *path;
    size_t path_len;
    const uint8_t *content;
    size_t content_len;
    int32_t is_dir;

    uint16_t mode;
    uint16_t _pad0;
    int64_t mtime_ns;
    int64_t ctime_ns;
    int64_t birthtime_ns;
    uint32_t uid;
    uint32_t gid;
    const uint8_t *owner;
    size_t owner_len;
    const uint8_t *groupname;
    size_t groupname_len;

    const blar_xattr_entry *xattrs;
    size_t xattr_count;
    const uint8_t *resource_fork;
    size_t resource_fork_len;
} blar_archive_entry;

/* ── Callback typedefs ────────────────────────────────────────────────── */
typedef void (*blar_progress_fn)(uint64_t items_done, uint64_t bytes_done, void *ctx);
typedef void (*blar_phase_fn)(const uint8_t *label, size_t label_len, void *ctx);

/* ── Public API ───────────────────────────────────────────────────────── */

const char *blar_error_string(int32_t code);

int32_t blar_archive_create_full(
    const blar_archive_entry *entries,
    size_t entry_count,
    uint32_t flags,
    uint32_t compression_id,   /* must be 0 in mini_blar profile */
    uint8_t  num_threads,
    blar_progress_fn progress_fn,
    blar_phase_fn    phase_fn,
    void *progress_ctx,
    uint8_t **out_buf,
    size_t   *out_len);

int32_t blar_archive_file_count(const uint8_t *buf, size_t len, uint64_t *out_count);
int32_t blar_archive_entry_count(const uint8_t *buf, size_t len, uint64_t *out_count);

int32_t blar_archive_file_path(
    const uint8_t *buf, size_t len,
    uint64_t idx,
    const uint8_t **out_ptr, size_t *out_len);

int32_t blar_archive_file_content(
    const uint8_t *buf, size_t len,
    uint64_t idx,
    const uint8_t **out_data, size_t *out_len);

int32_t blar_archive_file_content_by_path(
    const uint8_t *buf, size_t len,
    const uint8_t *path, size_t path_len,
    const uint8_t **out_data, size_t *out_len);

int32_t blar_archive_file_verify(const uint8_t *buf, size_t len, uint64_t idx);

bool    blar_archive_verify(const uint8_t *buf, size_t len);

int32_t blar_archive_entry_type(const uint8_t *buf, size_t len, uint64_t idx, uint8_t *out_type);

void    blar_archive_entry_metadata(
            const uint8_t *buf, size_t len,
            uint64_t idx,
            uint16_t *out_mode,
            int64_t  *out_mtime_ns,
            const uint8_t **out_owner, size_t *out_owner_len);

void blar_free(uint8_t *buf, size_t len);
void blar_free_content(const uint8_t *buf, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* MINI_BLAR_BLAR_H */
