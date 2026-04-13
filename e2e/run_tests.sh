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
MINIO_RELEASE="RELEASE.2025-06-13T11-33-47Z"
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

MINIO_URL="https://dl.min.io/server/minio/release/${MINIO_OS}-${MINIO_ARCH}/archive/minio.${MINIO_RELEASE}"
MC_URL="https://dl.min.io/client/mc/release/${MINIO_OS}-${MINIO_ARCH}/archive/mc.${MC_RELEASE}"

BIN_DIR="$SCRIPT_DIR/bin"
MINIO_BIN="$BIN_DIR/minio"
MC_BIN="$BIN_DIR/mc"
MINIO_DATA_DIR="${TMPDIR:-/tmp}/cloud_archive_e2e_minio_data"
MINIO_PORT=9123
MINIO_PID=""
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"
MC_CONFIG_DIR="$BIN_DIR/.mc"
BAZEL_OUTPUT_USER_ROOT="${BAZEL_OUTPUT_USER_ROOT:-${TMPDIR:-/tmp}/cloud_archive_bazel}"
BAZEL=(bazel --batch "--output_user_root=$BAZEL_OUTPUT_USER_ROOT")

cleanup() {
    echo "Cleaning up..."
    if [ -n "$MINIO_PID" ] && kill -0 "$MINIO_PID" 2>/dev/null; then
        kill "$MINIO_PID" 2>/dev/null || true
        wait "$MINIO_PID" 2>/dev/null || true
    fi
    rm -rf "$MINIO_DATA_DIR" "$MC_CONFIG_DIR"
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
"$MINIO_BIN" server "$MINIO_DATA_DIR" --address "127.0.0.1:$MINIO_PORT" --quiet &
MINIO_PID=$!

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
rm -rf "$MC_CONFIG_DIR"
export MC_CONFIG_DIR
"$MC_BIN" alias set local "http://127.0.0.1:$MINIO_PORT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --quiet

# --- Upload test data ---
"$MC_BIN" mb local/testbucket --ignore-existing --quiet
"$MC_BIN" cp ../testdata/test_file.txt local/testbucket/test_file.txt --quiet
"$MC_BIN" cp ../testdata/test_archive.tar.gz local/testbucket/test_archive.tar.gz --quiet
"$MC_BIN" cp ../testdata/test_archive.tar.zst local/testbucket/test_archive.tar.zst --quiet

echo "Test data uploaded."

# --- Run Bazel tests ---
# Ensure mc is on PATH so the minio rules can find it.
export PATH="$BIN_DIR:$PATH"

echo "Running Bazel tests..."
"${BAZEL[@]}" test //:minio_e2e_test \
    --test_output=all \
    --repo_env=MC_CONFIG_DIR="$MC_CONFIG_DIR" \
    --repo_env=PATH="$PATH"

echo ""
echo "All e2e tests passed."
