#!/bin/bash
# Runs all tests in the cloud_archive repository:
#   1. Unit tests  – local_archive_test (no external services required)
#   2. End-to-end tests – minio_e2e_test (spins up a local MinIO server)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

UNIT_PASS=false
E2E_PASS=false

# ---------------------------------------------------------------------------
# Unit tests
# ---------------------------------------------------------------------------
echo "========================================"
echo " Running unit tests"
echo "========================================"
if bazel test //:local_archive_test --test_output=all; then
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
