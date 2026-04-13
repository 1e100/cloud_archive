#!/bin/bash
# End-to-end test runner for MinIO-backed cloud_archive rules.
#
# This script:
#   1. Downloads a pinned `mc` binary (if not cached).
#   2. Stages local test data in an `mc`-readable directory layout.
#   3. Runs `bazel test` which fetches via minio_file / minio_archive.
#   4. Cleans up.
#
# Usage: cd e2e && ./run_tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --- Pinned client release version ---
MC_RELEASE="RELEASE.2025-04-16T18-13-26Z"

# Detect OS and architecture for the correct MinIO download URLs.
case "$(uname -s)" in
    Linux)  MINIO_OS="linux" ;;
    Darwin) MINIO_OS="darwin" ;;
    *)      echo "ERROR: Unsupported OS: $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64)       MINIO_ARCH="amd64" ;;
    aarch64|arm64) MINIO_ARCH="arm64" ;;
    *)            echo "ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

MC_URL="https://dl.min.io/client/mc/release/${MINIO_OS}-${MINIO_ARCH}/archive/mc.${MC_RELEASE}"

BIN_DIR="$SCRIPT_DIR/bin"
MC_BIN="$BIN_DIR/mc"
STAGED_ROOT="$SCRIPT_DIR/local/testbucket"
BAZEL_OUTPUT_USER_ROOT="${BAZEL_OUTPUT_USER_ROOT:-${TMPDIR:-/tmp}/cloud_archive_bazel}"
BAZEL=(bazel --batch "--output_user_root=$BAZEL_OUTPUT_USER_ROOT")

cleanup() {
    echo "Cleaning up..."
    rm -rf "$SCRIPT_DIR/local"
    echo "Done."
}
trap cleanup EXIT

# --- Download binaries if needed ---
download_if_missing() {
    local url="$1"
    local dest="$2"
    if [ ! -x "$dest" ]; then
        echo "Downloading $(basename "$dest")..."
        mkdir -p "$(dirname "$dest")"
        curl -fSL "$url" -o "$dest"
        chmod +x "$dest"
    fi
}

download_if_missing "$MC_URL" "$MC_BIN"

# --- Stage local data for mc ---
rm -rf "$SCRIPT_DIR/local"
mkdir -p "$STAGED_ROOT"
cp ../testdata/test_file.txt "$STAGED_ROOT/test_file.txt"
cp ../testdata/test_archive.tar.gz "$STAGED_ROOT/test_archive.tar.gz"
cp ../testdata/test_archive.tar.zst "$STAGED_ROOT/test_archive.tar.zst"

echo "Test data staged."

# --- Run Bazel tests ---
# Ensure mc is on PATH so the minio rules can find it.
export PATH="$BIN_DIR:$PATH"

echo "Running Bazel tests..."
"${BAZEL[@]}" test //:minio_e2e_test \
    --test_output=all \
    --repo_env=CLOUD_ARCHIVE_E2E_ROOT="$SCRIPT_DIR" \
    --repo_env=PATH="$PATH"

echo ""
echo "All e2e tests passed."
