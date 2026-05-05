/*
 * blar_common.h — minimal C utilities for the miniblar CLI.
 *
 * Scoped to mini_blar's profile: file I/O, mkdir -p, metadata extraction,
 * extended attribute helpers, tar-style flag parsing, default output name.
 *
 * No compression, no encryption, no codec expansion — those live in the
 * sibling blar project.
 */
#ifndef MINI_BLAR_COMMON_H
#define MINI_BLAR_COMMON_H

#include <ctype.h>
#include <errno.h>
#include <pwd.h>
#include <grp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "blar.h"

/* ── Exit codes ───────────────────────────────────────────────────────── */
#define EXIT_OK     0
#define EXIT_USAGE  64
#define EXIT_IO     74
#define EXIT_DATA   65

/* ── Version ──────────────────────────────────────────────────────────── */
#ifndef MINIBLAR_VERSION
#define MINIBLAR_VERSION "3.0.0"
#endif

/* ── read_file: slurp a path into a malloc'd buffer ───────────────────── */
static inline uint8_t *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    rewind(f);

    uint8_t *buf = (uint8_t *)malloc((size_t)sz);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if (got != (size_t)sz) { free(buf); return NULL; }

    *out_len = (size_t)sz;
    return buf;
}

/* ── write_file: dump a buffer to a path ─────────────────────────────── */
static inline bool write_file(const char *path, const uint8_t *buf, size_t len) {
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    size_t put = fwrite(buf, 1, len, f);
    int rc = fclose(f);
    return (put == len) && (rc == 0);
}

/* ── mkdir -p ────────────────────────────────────────────────────────── */
static inline int mkdirp(const char *path, mode_t mode) {
    if (!path || !*path) return -1;
    char buf[4096];
    size_t n = strlen(path);
    if (n >= sizeof(buf)) { errno = ENAMETOOLONG; return -1; }
    memcpy(buf, path, n + 1);

    for (size_t i = 1; i <= n; i++) {
        if (buf[i] == '/' || buf[i] == '\0') {
            char saved = buf[i];
            buf[i] = '\0';
            if (mkdir(buf, mode) != 0 && errno != EEXIST) return -1;
            buf[i] = saved;
        }
    }
    return 0;
}

/* Ensure the parent directory of `path` exists. */
static inline int ensure_parent_dir(const char *path, mode_t mode) {
    const char *slash = strrchr(path, '/');
    if (!slash) return 0;
    size_t n = (size_t)(slash - path);
    if (n == 0) return 0;
    char dir[4096];
    if (n >= sizeof(dir)) { errno = ENAMETOOLONG; return -1; }
    memcpy(dir, path, n);
    dir[n] = '\0';
    return mkdirp(dir, mode);
}

/* ── Metadata helpers ─────────────────────────────────────────────────── */

#if defined(__APPLE__)
  #define HAVE_BIRTHTIME 1
#endif

static inline int64_t get_mtime_ns(const struct stat *st) {
#if defined(__APPLE__)
    return (int64_t)st->st_mtimespec.tv_sec * 1000000000LL + (int64_t)st->st_mtimespec.tv_nsec;
#elif defined(__linux__)
    return (int64_t)st->st_mtim.tv_sec * 1000000000LL + (int64_t)st->st_mtim.tv_nsec;
#else
    return (int64_t)st->st_mtime * 1000000000LL;
#endif
}

static inline int64_t get_ctime_ns(const struct stat *st) {
#if defined(__APPLE__)
    return (int64_t)st->st_ctimespec.tv_sec * 1000000000LL + (int64_t)st->st_ctimespec.tv_nsec;
#elif defined(__linux__)
    return (int64_t)st->st_ctim.tv_sec * 1000000000LL + (int64_t)st->st_ctim.tv_nsec;
#else
    return (int64_t)st->st_ctime * 1000000000LL;
#endif
}

static inline int64_t get_birthtime_ns(const struct stat *st) {
#if defined(__APPLE__)
    return (int64_t)st->st_birthtimespec.tv_sec * 1000000000LL + (int64_t)st->st_birthtimespec.tv_nsec;
#else
    (void)st;
    return 0;
#endif
}

static inline const char *get_owner_name(uid_t uid) {
    struct passwd *pw = getpwuid(uid);
    return pw ? pw->pw_name : NULL;
}

static inline const char *get_group_name(gid_t gid) {
    struct group *gr = getgrgid(gid);
    return gr ? gr->gr_name : NULL;
}

/* Populate a blar_archive_entry's metadata fields from a stat result.
 * The caller sets path, content, content_len, is_dir, xattrs, resource_fork. */
static inline void fill_entry_metadata(blar_archive_entry *e, const struct stat *st) {
    e->mode = (uint16_t)(st->st_mode & 07777);
    e->mtime_ns = get_mtime_ns(st);
    e->ctime_ns = get_ctime_ns(st);
    e->birthtime_ns = get_birthtime_ns(st);
    e->uid = (uint32_t)st->st_uid;
    e->gid = (uint32_t)st->st_gid;

    const char *owner = get_owner_name(st->st_uid);
    if (owner) {
        e->owner = (const uint8_t *)owner;
        e->owner_len = strlen(owner);
    } else {
        e->owner = NULL;
        e->owner_len = 0;
    }
    const char *gname = get_group_name(st->st_gid);
    if (gname) {
        e->groupname = (const uint8_t *)gname;
        e->groupname_len = strlen(gname);
    } else {
        e->groupname = NULL;
        e->groupname_len = 0;
    }
}

/* ── Extended attribute helpers (Linux + macOS) ────────────────────────── */
#if defined(__APPLE__) || defined(__linux__)
  #if defined(__has_include)
    #if __has_include(<sys/xattr.h>)
      #include <sys/xattr.h>
      #define HAVE_XATTR 1
    #endif
  #endif
#endif

#if HAVE_XATTR
/* Read xattrs from a path. Resource fork is split out on macOS.
 * Returns 0 on success. Caller frees with free_file_xattrs(). */
static inline int read_file_xattrs(const char *path,
                                    blar_xattr_entry **out_xattrs, size_t *out_count,
                                    uint8_t **out_resource_fork, size_t *out_resource_fork_len) {
    *out_xattrs = NULL;
    *out_count = 0;
    *out_resource_fork = NULL;
    *out_resource_fork_len = 0;

#if defined(__APPLE__)
    ssize_t list_len = listxattr(path, NULL, 0, XATTR_NOFOLLOW);
#else
    ssize_t list_len = listxattr(path, NULL, 0);
#endif
    if (list_len < 0) return (errno == ENOTSUP || errno == ENODATA) ? 0 : -1;
    if (list_len == 0) return 0;

    char *names = (char *)malloc((size_t)list_len);
    if (!names) return -1;

#if defined(__APPLE__)
    ssize_t got = listxattr(path, names, (size_t)list_len, XATTR_NOFOLLOW);
#else
    ssize_t got = listxattr(path, names, (size_t)list_len);
#endif
    if (got < 0) { free(names); return -1; }

    /* Two-pass: count, allocate, fill */
    size_t total = 0;
    for (ssize_t i = 0; i < got; i += (ssize_t)strlen(names + i) + 1) total++;
    if (total == 0) { free(names); return 0; }

    blar_xattr_entry *xa = (blar_xattr_entry *)calloc(total, sizeof(*xa));
    if (!xa) { free(names); return -1; }

    size_t kept = 0;
    for (ssize_t i = 0; i < got; ) {
        const char *name = names + i;
        size_t name_len = strlen(name);

#if defined(__APPLE__)
        ssize_t vlen = getxattr(path, name, NULL, 0, 0, XATTR_NOFOLLOW);
#else
        ssize_t vlen = getxattr(path, name, NULL, 0);
#endif
        if (vlen < 0) { i += (ssize_t)name_len + 1; continue; }

        uint8_t *val = (uint8_t *)malloc((size_t)vlen);
        if (val) {
#if defined(__APPLE__)
            ssize_t got_v = getxattr(path, name, val, (size_t)vlen, 0, XATTR_NOFOLLOW);
#else
            ssize_t got_v = getxattr(path, name, val, (size_t)vlen);
#endif
            if (got_v == vlen) {
#if defined(__APPLE__)
                if (strcmp(name, "com.apple.ResourceFork") == 0) {
                    *out_resource_fork = val;
                    *out_resource_fork_len = (size_t)vlen;
                    i += (ssize_t)name_len + 1;
                    continue;
                }
#endif
                uint8_t *name_buf = (uint8_t *)malloc(name_len);
                if (name_buf) {
                    memcpy(name_buf, name, name_len);
                    xa[kept].name = name_buf;
                    xa[kept].name_len = name_len;
                    xa[kept].value = val;
                    xa[kept].value_len = (size_t)vlen;
                    kept++;
                } else {
                    free(val);
                }
            } else {
                free(val);
            }
        }
        i += (ssize_t)name_len + 1;
    }
    free(names);

    if (kept == 0) { free(xa); xa = NULL; }
    *out_xattrs = xa;
    *out_count = kept;
    return 0;
}

static inline void free_file_xattrs(blar_xattr_entry *xa, size_t count, uint8_t *rfork) {
    if (xa) {
        for (size_t i = 0; i < count; i++) {
            free((void *)xa[i].name);
            free((void *)xa[i].value);
        }
        free(xa);
    }
    if (rfork) free(rfork);
}
#else
static inline int read_file_xattrs(const char *path,
                                    blar_xattr_entry **out_xattrs, size_t *out_count,
                                    uint8_t **out_resource_fork, size_t *out_resource_fork_len) {
    (void)path;
    *out_xattrs = NULL; *out_count = 0;
    *out_resource_fork = NULL; *out_resource_fork_len = 0;
    return 0;
}
static inline void free_file_xattrs(blar_xattr_entry *xa, size_t count, uint8_t *rfork) {
    (void)xa; (void)count; (void)rfork;
}
#endif

/* ── Tar-style flag parsing ───────────────────────────────────────────── */
typedef enum {
    OP_NONE = 0,
    OP_CREATE,
    OP_LIST,
    OP_EXTRACT,
    OP_VERIFY,
    OP_INFO,
    OP_CAT,
} mb_op_t;

/* Recognise GNU tar-style shorthand: cf, tf, xf, Vf, If, pf (with or
 * without leading hyphen). Returns the op and *consumed=1 if matched. */
static inline mb_op_t parse_tar_flags(const char *arg, int *consumed) {
    if (!arg) { *consumed = 0; return OP_NONE; }
    const char *p = arg;
    if (*p == '-') p++;
    if (strlen(p) != 2 || p[1] != 'f') { *consumed = 0; return OP_NONE; }
    *consumed = 1;
    switch (p[0]) {
        case 'c': return OP_CREATE;
        case 't': return OP_LIST;
        case 'x': return OP_EXTRACT;
        case 'V': return OP_VERIFY;
        case 'I': return OP_INFO;
        case 'p': return OP_CAT;
        default:  *consumed = 0; return OP_NONE;
    }
}

/* ── Default output name helper ───────────────────────────────────────── */
/* "foo.txt"  → "foo.txt.mblar"
 * "src/foo"  → "foo.mblar"
 * Caller frees. */
static inline char *default_output_name(const char *first_input) {
    const char *base = strrchr(first_input, '/');
    base = base ? base + 1 : first_input;
    size_t blen = strlen(base);
    char *out = (char *)malloc(blen + 7); /* + ".mblar\0" */
    if (!out) return NULL;
    memcpy(out, base, blen);
    memcpy(out + blen, ".mblar", 7);
    return out;
}

/* Strip leading "./" and "/" from a path. */
static inline const char *normalize_path_inplace(const char *path) {
    while (*path == '/') path++;
    while (path[0] == '.' && path[1] == '/') path += 2;
    return path;
}

#endif /* MINI_BLAR_COMMON_H */
