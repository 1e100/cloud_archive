#!/bin/bash
# End-to-end test runner for MinIO-backed cloud_archive rules.
#
# This script:
#   1. Downloads pinned MinIO server + client binaries (if not cached).
#   2. Starts a local MinIO server.
#   3. Creates a test bucket and uploads test data.
#   4. Runs `bazel test` which fetches via minio_file / minio_archive.
#   5. Cleans up.
#
# Usage: cd e2e && ./run_tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --- Pinned MinIO release versions ---
# Using versioned archive URLs so checksums remain stable.
MINIO_RELEASE="RELEASE.2025-02-18T16-25-55Z"
MC_RELEASE="RELEASE.2025-02-15T12-58-54Z"

MINIO_URL="https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_RELEASE}"
MC_URL="https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_RELEASE}"

BIN_DIR="$SCRIPT_DIR/bin"
MINIO_BIN="$BIN_DIR/minio"
MC_BIN="$BIN_DIR/mc"
MINIO_DATA_DIR="$SCRIPT_DIR/minio_data"
MINIO_PORT=9123
MINIO_PID=""

MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"

cleanup() {
    echo "Cleaning up..."
    if [ -n "$MINIO_PID" ] && kill -0 "$MINIO_PID" 2>/dev/null; then
        kill "$MINIO_PID" 2>/dev/null || true
        wait "$MINIO_PID" 2>/dev/null || true
    fi
    rm -rf "$MINIO_DATA_DIR"
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

download_if_missing "$MINIO_URL" "$MINIO_BIN"
download_if_missing "$MC_URL" "$MC_BIN"

# --- Start MinIO server ---
rm -rf "$MINIO_DATA_DIR"
mkdir -p "$MINIO_DATA_DIR"

export MINIO_ROOT_USER
export MINIO_ROOT_PASSWORD

echo "Starting MinIO server on port $MINIO_PORT..."
"$MINIO_BIN" server "$MINIO_DATA_DIR" --address ":$MINIO_PORT" --quiet &
MINIO_PID=$!

# Wait for server to be ready.
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:$MINIO_PORT/minio/health/ready" >/dev/null 2>&1; then
        echo "MinIO server is ready."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "ERROR: MinIO server failed to start."
        exit 1
    fi
    sleep 0.5
done

# --- Configure mc client ---
# Use a local config directory so we don't pollute ~/.mc.
# Pass it through to Bazel repo rules via --repo_env so that mc invoked by
# cloud_archive.bzl can find the "local" alias.
MC_CONFIG_DIR="$SCRIPT_DIR/bin/.mc"
export MC_CONFIG_DIR
"$MC_BIN" alias set local "http://127.0.0.1:$MINIO_PORT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --quiet

# --- Upload test data ---
"$MC_BIN" mb local/testbucket --quiet 2>/dev/null || true
"$MC_BIN" cp ../testdata/test_file.txt local/testbucket/test_file.txt --quiet
"$MC_BIN" cp ../testdata/test_archive.tar.gz local/testbucket/test_archive.tar.gz --quiet
"$MC_BIN" cp ../testdata/test_archive.tar.zst local/testbucket/test_archive.tar.zst --quiet

echo "Test data uploaded."

# --- Run Bazel tests ---
# Ensure mc is on PATH so the minio rules can find it, and configure its alias.
export PATH="$BIN_DIR:$PATH"

echo "Running Bazel tests..."
bazel test //:minio_e2e_test \
    --test_output=all \
    --repo_env=MC_CONFIG_DIR="$MC_CONFIG_DIR" \
    --repo_env=PATH="$PATH"

echo ""
echo "All e2e tests passed."
