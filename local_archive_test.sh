#!/bin/bash
# Integration test for local_archive and local_file rules.
# Verifies checksum, extraction, strip_prefix, patching, and patch_cmds.
set -euo pipefail

# --- Runfiles resolution (works under both WORKSPACE and bzlmod) ---
# Bazel provides RUNFILES_DIR or RUNFILES_MANIFEST_FILE; the
# @bazel_tools runfiles library handles both, but to keep this test
# self-contained we do a simple lookup: try the manifest first, then
# fall back to the directory tree.
_rlocation() {
    local target="$1"
    if [ -n "${RUNFILES_MANIFEST_FILE:-}" ] && [ -f "$RUNFILES_MANIFEST_FILE" ]; then
        grep -m1 "^${target} " "$RUNFILES_MANIFEST_FILE" | cut -d' ' -f2-
        return
    fi
    local candidate="${RUNFILES_DIR:-${TEST_SRCDIR:-$0.runfiles}}/$target"
    if [ -e "$candidate" ]; then
        echo "$candidate"
        return
    fi
    # bzlmod canonical name: _main~_repo_rules~<repo>
    local bzlmod_target
    bzlmod_target="$(echo "$target" | sed 's|^\([^/]*\)|_main~_repo_rules~\1|')"
    candidate="${RUNFILES_DIR:-${TEST_SRCDIR:-$0.runfiles}}/$bzlmod_target"
    if [ -e "$candidate" ]; then
        echo "$candidate"
        return
    fi
    # Return the original path so the caller's "file not found" is clear.
    echo "${RUNFILES_DIR:-${TEST_SRCDIR:-$0.runfiles}}/$target"
}

PASS=0
FAIL=0

assert_file_contains() {
    local file="$1"
    local expected="$2"
    local label="$3"
    if [ ! -f "$file" ]; then
        echo "FAIL [$label]: file not found: $file"
        FAIL=$((FAIL + 1))
        return
    fi
    actual="$(cat "$file")"
    if [ "$actual" = "$expected" ]; then
        echo "PASS [$label]"
        PASS=$((PASS + 1))
    else
        echo "FAIL [$label]: expected '$expected', got '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

# Test 1: local_file - basic file download + checksum
assert_file_contains \
    "$(_rlocation test_local_file/file/downloaded)" \
    "Hello from cloud_archive test." \
    "local_file basic"

# Test 2: local_archive with .tar.gz - basic extraction
assert_file_contains \
    "$(_rlocation test_local_archive_gz/cloud_archive_test.txt)" \
    "Hello from cloud_archive test." \
    "local_archive tar.gz extraction"

# Test 3: local_archive with .tar.zst + strip_prefix=dir1
assert_file_contains \
    "$(_rlocation test_local_archive_zstd/dir2/dir3/text3.txt)" \
    "The quick brown fox jumps over the lazy dog." \
    "local_archive tar.zst + strip_prefix"

# Test 4: local_archive with .tar.zst + strip_prefix=dir1/dir2
assert_file_contains \
    "$(_rlocation test_local_archive_zstd_strip2/dir3/text3.txt)" \
    "The quick brown fox jumps over the lazy dog." \
    "local_archive tar.zst + multi-level strip_prefix"

# Test 5: local_archive with patch applied
assert_file_contains \
    "$(_rlocation test_local_archive_patch/dir2/dir3/text3.txt)" \
    "The quick brown fox jumps over the lazy bear." \
    "local_archive patch"

# Test 6: local_archive with patch_cmds
assert_file_contains \
    "$(_rlocation test_local_archive_patch_cmds/dir2/dir3/text3.txt)" \
    "patched by cmd" \
    "local_archive patch_cmds"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
