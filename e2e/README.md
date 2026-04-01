# MinIO End-to-End Tests

Integration tests for `minio_file` and `minio_archive` rules against a real
(local) MinIO server.

## Prerequisites

- Linux or macOS (x86_64 / arm64; MinIO binaries are fetched automatically)
- `curl` on `$PATH`
- Bazel (see `../.bazelversion`)

## Running

```sh
cd e2e
./run_tests.sh
```

The script will:

1. Download pinned MinIO server and client binaries into `bin/` (cached across
   runs).
2. Start a local MinIO server on port 9123.
3. Create a `testbucket` bucket and upload test data from `../testdata/`.
4. Run `bazel test` which exercises `minio_file` and `minio_archive` rules
   (including checksum validation, extraction, `strip_prefix`, and patching).
5. Shut down the server and clean up.

## What is tested

| Rule             | Variant                      |
|------------------|------------------------------|
| `minio_file`     | basic file download          |
| `minio_archive`  | `.tar.gz` extraction         |
| `minio_archive`  | `.tar.zst` + `strip_prefix`  |
| `minio_archive`  | `.tar.zst` + patch           |
