#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$REPO_ROOT/negative_tests/downloaded_file_path_escape"
BAZEL_OUTPUT_USER_ROOT="${BAZEL_OUTPUT_USER_ROOT:-${TMPDIR:-/tmp}/cloud_archive_bazel_downloaded_file_path_validation}"
BAZEL=(bazel --batch "--output_user_root=$BAZEL_OUTPUT_USER_ROOT")

echo "Running downloaded_file_path validation regression..."

set +e
output="$(
    cd "$TEST_DIR"
    "${BAZEL[@]}" build //:trigger 2>&1
)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "FAIL [downloaded_file_path validation]: expected build failure for traversal path"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -Fq "downloaded_file_path"; then
    echo "FAIL [downloaded_file_path validation]: expected downloaded_file_path error"
    printf '%s\n' "$output"
    exit 1
fi

echo "PASS [downloaded_file_path validation]"
