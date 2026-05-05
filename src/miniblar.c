/*
 * miniblar — Minimal BLIP archive CLI.
 *
 * Creates flat (FILE-only) archives in mini_blar's profile of the BLAR
 * format: TYPE=5/7, xxhash64 only, no compression, no encryption, no
 * codec expansion. Archives produced are valid input for the full blar
 * reader.
 *
 * Usage:
 *   miniblar create [-o <archive>] <files...>
 *   miniblar list <archive>
 *   miniblar extract <archive> [-C <dir>]
 *   miniblar verify <archive>
 *   miniblar info <archive>
 *   miniblar cat <archive> <path>
 *
 * Tar-style shorthand:
 *   miniblar cf  <archive> <files...>
 *   miniblar tf  <archive>
 *   miniblar xf  <archive> [-C <dir>]
 *   miniblar Vf  <archive>
 *   miniblar If  <archive>
 *   miniblar pf  <archive> <path>
 */

#include <fcntl.h>
#include <getopt.h>
#include <utime.h>
#include <sys/time.h>
#include "blar_common.h"

#ifndef MINIBLAR_VERSION
#define MINIBLAR_VERSION "3.0.0"
#endif

static void print_usage(FILE *out) {
    fprintf(out,
        "Usage: miniblar <command> [options] [args]\n"
        "\n"
        "Commands:\n"
        "  create  -o <archive> <files...>     Create a new archive\n"
        "  list    <archive>                   List archive contents\n"
        "  extract <archive> [-C <dir>]        Extract archive\n"
        "  verify  <archive>                   Verify all hashes\n"
        "  info    <archive>                   Show archive stats\n"
        "  cat     <archive> <path>            Print one file to stdout\n"
        "\n"
        "Tar-style shorthand: cf, tf, xf, Vf, If, pf\n"
        "Options: -h/--help  --version  --about  -f/--force  -C <dir>  -o <archive>\n"
    );
}

static void print_about(void) {
    printf("miniblar %s — minimal BLIP archive CLI (mini_blar profile)\n",
           MINIBLAR_VERSION);
}

/* Append ".mblar" to a path that lacks it. Returns malloc'd string or NULL. */
static char *ensure_mblar_extension(const char *path) {
    size_t len = strlen(path);
    if (len >= 6 && strcmp(path + len - 6, ".mblar") == 0) {
        char *copy = (char *)malloc(len + 1);
        if (copy) memcpy(copy, path, len + 1);
        return copy;
    }
    char *out = (char *)malloc(len + 7);
    if (!out) return NULL;
    memcpy(out, path, len);
    memcpy(out + len, ".mblar", 7);
    return out;
}

/* ── create ──────────────────────────────────────────────────────────── */
/*
 * Two call shapes:
 *   - subcommand:   create [-o <out>] [-f] [files...]      (-o anywhere)
 *   - tar-style:    cf <archive> [files...]                (archive is argv[0])
 */
static int cmd_create_impl(int argc, char **argv, bool tar_style) {
    const char *out_path = NULL;
    bool force = false;

    /* Pre-allocate input slot list so we can scan args in any order */
    int *input_indices = (int *)calloc((size_t)argc, sizeof(int));
    if (!input_indices) { fprintf(stderr, "miniblar: create: out of memory\n"); return EXIT_IO; }
    int input_count = 0;

    int i = 0;
    if (tar_style) {
        if (argc < 1) {
            fprintf(stderr, "miniblar: create: tar-style requires <archive> <files...>\n");
            free(input_indices); return EXIT_USAGE;
        }
        out_path = argv[0];
        i = 1;
    }

    while (i < argc) {
        const char *a = argv[i];
        if (!tar_style && (strcmp(a, "-o") == 0) && i + 1 < argc) {
            out_path = argv[++i];
        } else if (strcmp(a, "-f") == 0 || strcmp(a, "--force") == 0) {
            force = true;
        } else {
            input_indices[input_count++] = i;
        }
        i++;
    }

    if (input_count < 1) {
        fprintf(stderr, "miniblar: create: no input files given\n");
        free(input_indices); return EXIT_USAGE;
    }
    /* Subcommand mode: -o is required for multi-file archives.
     * Single-file archives auto-derive the output name from the input. */
    char *out_alloc = NULL;
    if (!out_path) {
        if (input_count > 1) {
            fprintf(stderr, "miniblar: create: -o <archive> required for multi-file archives\n");
            free(input_indices); return EXIT_USAGE;
        }
        out_alloc = default_output_name(argv[input_indices[0]]);
        out_path = out_alloc;
    } else {
        /* Append .mblar if missing */
        out_alloc = ensure_mblar_extension(out_path);
        out_path = out_alloc;
    }
    if (!out_path) {
        free(input_indices);
        fprintf(stderr, "miniblar: create: out of memory\n");
        return EXIT_IO;
    }

    if (!force) {
        struct stat st;
        if (stat(out_path, &st) == 0) {
            fprintf(stderr, "miniblar: '%s' already exists (use -f to overwrite)\n", out_path);
            free(out_alloc); free(input_indices);
            return EXIT_USAGE;
        }
    }

    blar_archive_entry *entries = (blar_archive_entry *)calloc((size_t)input_count, sizeof(*entries));
    if (!entries) { free(out_alloc); free(input_indices); return EXIT_IO; }

    for (int j = 0; j < input_count; j++) {
        const char *raw_path = argv[input_indices[j]];
        const char *stored_path = normalize_path_inplace(raw_path);

        /* Reject directories explicitly — mini_blar's CLI handles flat archives. */
        struct stat st_chk;
        if (stat(raw_path, &st_chk) == 0 && S_ISDIR(st_chk.st_mode)) {
            fprintf(stderr, "miniblar: create: directory arguments not supported (use blar): '%s'\n", raw_path);
            for (int k = 0; k < j; k++) {
                free((void *)entries[k].content);
                free_file_xattrs((blar_xattr_entry *)entries[k].xattrs,
                                  entries[k].xattr_count,
                                  (uint8_t *)entries[k].resource_fork);
            }
            free(entries); free(out_alloc); free(input_indices);
            return EXIT_USAGE;
        }

        size_t content_len = 0;
        uint8_t *content = read_file(raw_path, &content_len);
        if (!content) {
            fprintf(stderr, "miniblar: create: cannot read '%s': %s\n", raw_path, strerror(errno));
            for (int k = 0; k < j; k++) {
                free((void *)entries[k].content);
                free_file_xattrs((blar_xattr_entry *)entries[k].xattrs,
                                  entries[k].xattr_count,
                                  (uint8_t *)entries[k].resource_fork);
            }
            free(entries); free(out_alloc); free(input_indices);
            return EXIT_IO;
        }

        memset(&entries[j], 0, sizeof(entries[j]));
        entries[j].path = (const uint8_t *)stored_path;
        entries[j].path_len = strlen(stored_path);
        entries[j].content = content;
        entries[j].content_len = content_len;
        entries[j].is_dir = 0;

        struct stat st;
        if (stat(raw_path, &st) == 0) fill_entry_metadata(&entries[j], &st);

        blar_xattr_entry *xa = NULL; size_t xa_count = 0;
        uint8_t *rfork = NULL; size_t rfork_len = 0;
        read_file_xattrs(raw_path, &xa, &xa_count, &rfork, &rfork_len);
        entries[j].xattrs = xa;
        entries[j].xattr_count = xa_count;
        entries[j].resource_fork = rfork;
        entries[j].resource_fork_len = rfork_len;
    }

    uint8_t *archive = NULL; size_t archive_len = 0;
    int32_t rc = blar_archive_create_full(
        entries, (size_t)input_count, 0, 0, 0,
        NULL, NULL, NULL, &archive, &archive_len);

    for (int j = 0; j < input_count; j++) {
        free((void *)entries[j].content);
        free_file_xattrs((blar_xattr_entry *)entries[j].xattrs, entries[j].xattr_count,
                         (uint8_t *)entries[j].resource_fork);
    }
    free(entries); free(input_indices);

    if (rc != BLAR_OK) {
        fprintf(stderr, "miniblar: create: %s\n", blar_error_string(rc));
        free(out_alloc);
        return EXIT_IO;
    }

    bool ok = write_file(out_path, archive, archive_len);
    blar_free(archive, archive_len);
    if (!ok) {
        fprintf(stderr, "miniblar: create: cannot write '%s': %s\n", out_path, strerror(errno));
        free(out_alloc);
        return EXIT_IO;
    }
    free(out_alloc);
    return EXIT_OK;
}

static int cmd_create(int argc, char **argv) { return cmd_create_impl(argc, argv, false); }
static int cmd_create_tar(int argc, char **argv) { return cmd_create_impl(argc, argv, true); }

/* ── list ────────────────────────────────────────────────────────────── */
static int cmd_list(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "miniblar: list: archive required\n"); return EXIT_USAGE; }
    size_t buf_len = 0;
    uint8_t *buf = read_file(argv[0], &buf_len);
    if (!buf) { fprintf(stderr, "miniblar: list: cannot read '%s'\n", argv[0]); return EXIT_IO; }

    uint64_t count = 0;
    int32_t rc = blar_archive_entry_count(buf, buf_len, &count);
    if (rc != BLAR_OK) {
        fprintf(stderr, "miniblar: list: %s\n", blar_error_string(rc));
        free(buf); return EXIT_DATA;
    }
    for (uint64_t j = 0; j < count; j++) {
        const uint8_t *path = NULL; size_t path_len = 0;
        if (blar_archive_file_path(buf, buf_len, j, &path, &path_len) != BLAR_OK) continue;
        uint8_t type = 0;
        blar_archive_entry_type(buf, buf_len, j, &type);
        char prefix = (type == BLAR_TYPE_DIR) ? 'd' : '-';
        printf("%c %.*s\n", prefix, (int)path_len, (const char *)path);
    }
    free(buf);
    return EXIT_OK;
}

/* ── extract ─────────────────────────────────────────────────────────── */
static int cmd_extract(int argc, char **argv) {
    const char *archive = NULL;
    const char *outdir = ".";
    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "-C") == 0 && i + 1 < argc) {
            outdir = argv[++i];
        } else if (!archive) {
            archive = argv[i];
        }
    }
    if (!archive) { fprintf(stderr, "miniblar: extract: archive required\n"); return EXIT_USAGE; }

    size_t buf_len = 0;
    uint8_t *buf = read_file(archive, &buf_len);
    if (!buf) { fprintf(stderr, "miniblar: extract: cannot read '%s'\n", archive); return EXIT_IO; }

    if (mkdirp(outdir, 0755) != 0) {
        fprintf(stderr, "miniblar: extract: cannot create '%s': %s\n", outdir, strerror(errno));
        free(buf); return EXIT_IO;
    }

    uint64_t count = 0;
    if (blar_archive_entry_count(buf, buf_len, &count) != BLAR_OK) {
        fprintf(stderr, "miniblar: extract: invalid archive\n");
        free(buf); return EXIT_DATA;
    }

    for (uint64_t j = 0; j < count; j++) {
        const uint8_t *path = NULL; size_t path_len = 0;
        if (blar_archive_file_path(buf, buf_len, j, &path, &path_len) != BLAR_OK) continue;

        char full[4096];
        int n = snprintf(full, sizeof(full), "%s/%.*s", outdir, (int)path_len, (const char *)path);
        if (n < 0 || (size_t)n >= sizeof(full)) continue;

        uint8_t type = 0;
        blar_archive_entry_type(buf, buf_len, j, &type);
        if (type == BLAR_TYPE_DIR) {
            mkdirp(full, 0755);
            continue;
        }

        if (ensure_parent_dir(full, 0755) != 0) {
            fprintf(stderr, "miniblar: extract: cannot create parent of '%s'\n", full);
            continue;
        }

        const uint8_t *data = NULL; size_t data_len = 0;
        if (blar_archive_file_content(buf, buf_len, j, &data, &data_len) != BLAR_OK) continue;
        bool ok = write_file(full, data, data_len);
        blar_free_content(data, data_len);
        if (!ok) {
            fprintf(stderr, "miniblar: extract: cannot write '%s': %s\n", full, strerror(errno));
            continue;
        }

        uint16_t mode = 0; int64_t mtime_ns = 0;
        const uint8_t *owner = NULL; size_t owner_len = 0;
        blar_archive_entry_metadata(buf, buf_len, j, &mode, &mtime_ns, &owner, &owner_len);
        if (mode != 0) chmod(full, (mode_t)mode);
        if (mtime_ns != 0) {
            struct timeval tv[2];
            tv[0].tv_sec  = (time_t)(mtime_ns / 1000000000LL);
            tv[0].tv_usec = (suseconds_t)((mtime_ns / 1000) % 1000000);
            tv[1] = tv[0];
            utimes(full, tv);
        }
    }

    free(buf);
    return EXIT_OK;
}

/* ── verify ──────────────────────────────────────────────────────────── */
static int cmd_verify(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "miniblar: verify: archive required\n"); return EXIT_USAGE; }
    size_t buf_len = 0;
    uint8_t *buf = read_file(argv[0], &buf_len);
    if (!buf) { fprintf(stderr, "miniblar: verify: cannot read '%s'\n", argv[0]); return EXIT_IO; }

    bool outer = blar_archive_verify(buf, buf_len);
    uint64_t count = 0;
    int32_t rc = blar_archive_entry_count(buf, buf_len, &count);
    if (rc != BLAR_OK) {
        fprintf(stderr, "miniblar: verify: %s\n", blar_error_string(rc));
        free(buf); return EXIT_DATA;
    }
    int failed = 0;
    for (uint64_t j = 0; j < count; j++) {
        if (blar_archive_file_verify(buf, buf_len, j) != BLAR_OK) {
            const uint8_t *path = NULL; size_t path_len = 0;
            blar_archive_file_path(buf, buf_len, j, &path, &path_len);
            fprintf(stderr, "FAIL: %.*s\n", (int)path_len, (const char *)path);
            failed++;
        }
    }
    free(buf);
    if (!outer || failed > 0) {
        fprintf(stderr, "miniblar: verify: %d entry failure(s); outer=%s\n",
                failed, outer ? "ok" : "FAIL");
        return EXIT_DATA;
    }
    printf("ok\n");
    return EXIT_OK;
}

/* ── info ────────────────────────────────────────────────────────────── */
static int cmd_info(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "miniblar: info: archive required\n"); return EXIT_USAGE; }
    size_t buf_len = 0;
    uint8_t *buf = read_file(argv[0], &buf_len);
    if (!buf) { fprintf(stderr, "miniblar: info: cannot read '%s'\n", argv[0]); return EXIT_IO; }

    uint64_t count = 0;
    if (blar_archive_entry_count(buf, buf_len, &count) != BLAR_OK) {
        fprintf(stderr, "miniblar: info: invalid archive\n");
        free(buf); return EXIT_DATA;
    }
    uint64_t files = 0, dirs = 0, total_bytes = 0;
    for (uint64_t j = 0; j < count; j++) {
        uint8_t type = 0;
        blar_archive_entry_type(buf, buf_len, j, &type);
        if (type == BLAR_TYPE_DIR) {
            dirs++;
        } else {
            files++;
            const uint8_t *data = NULL; size_t data_len = 0;
            if (blar_archive_file_content(buf, buf_len, j, &data, &data_len) == BLAR_OK) {
                total_bytes += data_len;
                blar_free_content(data, data_len);
            }
        }
    }
    bool ok = blar_archive_verify(buf, buf_len);
    printf("Archive:    %s\n", argv[0]);
    printf("Size:       %zu bytes\n", buf_len);
    printf("Files:      %llu\n", (unsigned long long)files);
    printf("Dirs:       %llu\n", (unsigned long long)dirs);
    printf("Content:    %llu bytes\n", (unsigned long long)total_bytes);
    printf("Integrity:  %s\n", ok ? "ok" : "FAIL");
    free(buf);
    return EXIT_OK;
}

/* ── cat ─────────────────────────────────────────────────────────────── */
static int cmd_cat(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "miniblar: cat: usage: cat <archive> <path>\n"); return EXIT_USAGE; }
    size_t buf_len = 0;
    uint8_t *buf = read_file(argv[0], &buf_len);
    if (!buf) { fprintf(stderr, "miniblar: cat: cannot read '%s'\n", argv[0]); return EXIT_IO; }

    /* Apply the same path normalization the archive uses on storage so callers
     * can pass either the raw path they fed `create` or the normalized form. */
    const char *query = normalize_path_inplace(argv[1]);

    const uint8_t *data = NULL; size_t data_len = 0;
    int32_t rc = blar_archive_file_content_by_path(
        buf, buf_len,
        (const uint8_t *)query, strlen(query),
        &data, &data_len);
    if (rc == BLAR_ERR_NOT_FOUND) {
        fprintf(stderr, "miniblar: cat: '%s' not found\n", argv[1]);
        free(buf); return EXIT_DATA;
    } else if (rc != BLAR_OK) {
        fprintf(stderr, "miniblar: cat: %s\n", blar_error_string(rc));
        free(buf); return EXIT_DATA;
    }
    fwrite(data, 1, data_len, stdout);
    blar_free_content(data, data_len);
    free(buf);
    return EXIT_OK;
}

/* ── peek (out-of-profile stub) ──────────────────────────────────────── */
/* mini_blar's profile excludes the `peek` introspection helper that lives
 * in the full blar/BLIP toolchain. Print main usage to stay friendly to
 * pipelines that probe for help. */
static int cmd_peek(int argc, char **argv) {
    (void)argc; (void)argv;
    print_usage(stdout);
    fprintf(stdout, "\nNote: 'peek' is not part of the mini_blar profile (use blar instead).\n");
    return EXIT_OK;
}

/* ── main ────────────────────────────────────────────────────────────── */
int main(int argc, char **argv) {
    if (argc < 2) { print_usage(stderr); return EXIT_USAGE; }
    const char *cmd = argv[1];

    if (strcmp(cmd, "-h") == 0 || strcmp(cmd, "--help") == 0) {
        print_usage(stdout); return EXIT_OK;
    }
    if (strcmp(cmd, "--about") == 0 || strcmp(cmd, "--version") == 0) {
        print_about(); return EXIT_OK;
    }

    /* Tar-style shorthand */
    int consumed = 0;
    mb_op_t op = parse_tar_flags(cmd, &consumed);
    bool tar_style = (consumed != 0);
    if (!tar_style) {
        if      (strcmp(cmd, "create")  == 0) op = OP_CREATE;
        else if (strcmp(cmd, "list")    == 0) op = OP_LIST;
        else if (strcmp(cmd, "extract") == 0) op = OP_EXTRACT;
        else if (strcmp(cmd, "verify")  == 0) op = OP_VERIFY;
        else if (strcmp(cmd, "info")    == 0) op = OP_INFO;
        else if (strcmp(cmd, "cat")     == 0) op = OP_CAT;
        else if (strcmp(cmd, "peek")    == 0) return cmd_peek(argc - 2, argv + 2);
        else op = OP_NONE;
    }

    int sub_argc = argc - 2;
    char **sub_argv = argv + 2;

    switch (op) {
        case OP_CREATE:  return tar_style ? cmd_create_tar(sub_argc, sub_argv)
                                          : cmd_create    (sub_argc, sub_argv);
        case OP_LIST:    return cmd_list   (sub_argc, sub_argv);
        case OP_EXTRACT: return cmd_extract(sub_argc, sub_argv);
        case OP_VERIFY:  return cmd_verify (sub_argc, sub_argv);
        case OP_INFO:    return cmd_info   (sub_argc, sub_argv);
        case OP_CAT:     return cmd_cat    (sub_argc, sub_argv);
        default:
            fprintf(stderr, "miniblar: unknown command '%s'\n", cmd);
            print_usage(stderr);
            return EXIT_USAGE;
    }
}
