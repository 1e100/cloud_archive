# Shared test helpers for cloud_archive sh_tests.
# Source this file after Bazel runfiles initialization so that rlocation is available.

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
