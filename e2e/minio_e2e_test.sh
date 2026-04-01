#!/bin/bash
# E2E test for minio_file and minio_archive rules.
# This script is invoked by Bazel (sh_test) after run_tests.sh has started
# the MinIO server and triggered the fetch. It validates the fetched content.
set -euo pipefail

# --- begin runfiles.bash initialization v3 ---
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }
set -e
# --- end runfiles.bash initialization v3 ---

PASS=0
FAIL=0

assert_file_contains() {
    local rloc="$1"
    local expected="$2"
    local label="$3"
    local file
    file="$(rlocation "$rloc")"
    if [ ! -f "$file" ]; then
        echo "FAIL [$label]: file not found: $file (rlocation of $rloc)"
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

# Test 1: minio_file - basic file download + checksum
assert_file_contains \
    "test_minio_file/file/downloaded" \
    "Hello from cloud_archive test." \
    "minio_file basic"

# Test 2: minio_archive with .tar.gz - extraction
assert_file_contains \
    "test_minio_archive_gz/cloud_archive_test.txt" \
    "Hello from cloud_archive test." \
    "minio_archive tar.gz extraction"

# Test 3: minio_archive with .tar.zst + strip_prefix
assert_file_contains \
    "test_minio_archive_zstd/dir2/dir3/text3.txt" \
    "The quick brown fox jumps over the lazy dog." \
    "minio_archive tar.zst + strip_prefix"

# Test 4: minio_archive with patch applied
assert_file_contains \
    "test_minio_archive_patch/dir2/dir3/text3.txt" \
    "The quick brown fox jumps over the lazy bear." \
    "minio_archive patch"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
