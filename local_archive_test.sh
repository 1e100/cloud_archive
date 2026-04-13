#!/bin/bash
# Integration test for local_archive and local_file rules.
# Verifies checksum, extraction, strip_prefix, patching, and patch_cmds.
set -euo pipefail

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash Runfiles library:
# https://github.com/bazelbuild/bazel/blob/master/tools/bash/runfiles/runfiles.bash
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }
set -e
# --- end runfiles.bash initialization v3 ---

PASS=0
FAIL=0

# shellcheck source=test_helpers.sh
source "$(rlocation cloud_archive/test_helpers.sh)"

# Test 1: local_file - basic file download + checksum
assert_file_contains \
    "test_local_file/file/downloaded" \
    "Hello from cloud_archive test." \
    "local_file basic"

# Test 2: local_archive with .tar.gz - basic extraction
assert_file_contains \
    "test_local_archive_gz/cloud_archive_test.txt" \
    "Hello from cloud_archive test." \
    "local_archive tar.gz extraction"

# Test 3: local_archive with .tar.zst + strip_prefix=dir1
assert_file_contains \
    "test_local_archive_zstd/dir2/dir3/text3.txt" \
    "The quick brown fox jumps over the lazy dog." \
    "local_archive tar.zst + strip_prefix"

# Test 4: local_archive with .tar.zst + strip_prefix=dir1/dir2
assert_file_contains \
    "test_local_archive_zstd_strip2/dir3/text3.txt" \
    "The quick brown fox jumps over the lazy dog." \
    "local_archive tar.zst + multi-level strip_prefix"

# Test 5: local_archive with patch applied
assert_file_contains \
    "test_local_archive_patch/dir2/dir3/text3.txt" \
    "The quick brown fox jumps over the lazy bear." \
    "local_archive patch"

# Test 6: local_archive with patch_cmds
assert_file_contains \
    "test_local_archive_patch_cmds/dir2/dir3/text3.txt" \
    "patched by cmd" \
    "local_archive patch_cmds"

# Test 7: local_archive with add_prefix + strip_prefix
assert_file_contains \
    "test_local_archive_add_prefix/myprefix/dir2/dir3/text3.txt" \
    "The quick brown fox jumps over the lazy dog." \
    "local_archive add_prefix + strip_prefix"

# Test 8: local_archive with type attribute (extensionless file)
assert_file_contains \
    "test_local_archive_type/cloud_archive_test.txt" \
    "Hello from cloud_archive test." \
    "local_archive type attribute"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
