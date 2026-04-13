#!/bin/bash
# Runs all tests in the cloud_archive repository:
#   1. Unit tests  – local_archive_test (no external services required)
#   2. End-to-end tests – minio_e2e_test (stages mc-backed test data)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

# Bazel output under ~/.cache is not writable in some constrained environments.
# Use batch mode to avoid a resident server, which also helps in sandboxes.
BAZEL_OUTPUT_USER_ROOT="${BAZEL_OUTPUT_USER_ROOT:-${TMPDIR:-/tmp}/cloud_archive_bazel}"
BAZEL=(bazel --batch "--output_user_root=$BAZEL_OUTPUT_USER_ROOT")

UNIT_PASS=false
E2E_PASS=false

# ---------------------------------------------------------------------------
# Unit tests
# ---------------------------------------------------------------------------
echo "========================================"
echo " Running unit tests"
echo "========================================"
if "${BAZEL[@]}" test //:local_archive_test --test_output=all; then
    UNIT_PASS=true
else
    echo "ERROR: Unit tests FAILED." >&2
fi

# ---------------------------------------------------------------------------
# End-to-end tests
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo " Running end-to-end tests"
echo "========================================"
if "$REPO_ROOT/e2e/run_tests.sh"; then
    E2E_PASS=true
else
    echo "ERROR: End-to-end tests FAILED." >&2
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo " Summary"
echo "========================================"
echo "  Unit tests : $( $UNIT_PASS && echo PASS || echo FAIL )"
echo "  E2E tests  : $( $E2E_PASS  && echo PASS || echo FAIL )"
echo "========================================"

$UNIT_PASS && $E2E_PASS
