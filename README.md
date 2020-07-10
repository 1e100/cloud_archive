# Cloud archive

This `WORKSPACE` rule for Google Bazel lets you securely download private
workspace dependencies from S3 or Minio.

## Requirements

This currently only works on Linux, although adapting it to macOS and Windows
shouldn't be difficult.

### S3

AWS CLI is required to be in the path for S3 support, and must be set
up such that you can download files from the buckets referenced in the rules
with `aws s3 cp`. `--profile` flag is also supported, for people who use
multiple profiles.

### Minio

Likewise for Minio, `mc` command should be in the path, and Minio should be set
up such that `mc cp` is able to download the referenced files.

## Usage

Please refer to `WORKSPACE` file in this repository for an example of how to
use this.

## Future work

Quite obviously this can also be adapted to other cloud storage providers,
basically anything that can download an archive from the command line should
work.

## License

This software is licensed under Apache 2.0.
