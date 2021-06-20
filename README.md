# Cloud archive

This set of `WORKSPACE` rules for Bazel lets you securely download private
workspace dependencies from Google Cloud Storage, S3, Minio, or Backblaze B2.
This can be useful when pulling data, code, and binary dependencies from these
storage backends into your Bazel build.

In addition, these rules are support the much faster Zstandard compression for
`*.tar.zst` and `*.tzst` files, assuming your `tar` supports `zstd` and `zstd`
is installed. If not you see errors, try `sudo apt install zstd` before you
file an issue, and make sure your `tar` is fresh enough to support this.

## Usage
```starlark
load("//:cloud_archive.bzl", "gs_archive")

gs_archive(
    name = "archive_gcloud",
    build_file = "//:BUILD.archive",
    bucket = "my_bucket",
    file_path = "cloud_archive_test.tar.gz",
    sha256 = "bf4dd5304180561a745e816ee6a8db974a3fcf5b9d706a493776d77202c48bc9",
    strip_prefix = "cloud_archive_test",
)
```
Pretty similar to HTTP archive rule in Bazel. `s3_archive`, `minio_archive` and
`b2_archive` are also available.

## Requirements

This currently only works on Linux, although adapting it to macOS and Windows
shouldn't be difficult.

### Google Cloud storage

The `gsutil` command must be installed, and authenticated using `gcloud auth
login`.

### S3

AWS CLI is required to be in the path for S3 support, and must be set
up such that you can download files from the buckets referenced in the rules
with `aws s3 cp`. `--profile` flag is also supported, for people who use
multiple profiles.

### Minio

Likewise for Minio, `mc` command should be in the path, and Minio should be set
up such that `mc cp` is able to download the referenced files.

### Backblaze

The `b2` command line utility must be installed and configured to access the
account as per [the
instructions](https://www.backblaze.com/b2/docs/quick_command_line.html).

## Usage

Please refer to `WORKSPACE` file in this repository for an example of how to
use this.

## How to test

To test, you will need to point the workspace targets to your own cloud
storage, as well as initialize cloud storage on your machine to the point where
the typical `cp` command works.

## Future work

Quite obviously this can also be adapted to other cloud storage providers,
basically anything that can download an archive from the command line should
work.

## License

This software is licensed under Apache 2.0.
