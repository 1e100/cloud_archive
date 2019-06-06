# Cloud archive

This `WORKSPACE` rule for Google Bazel lets you securely download private
dependencies from S3.

## Requirements

This currently only works on Linux, although adapting it to macOS and Windows
shouldn't be difficult. AWS CLI is required to be in the path, and must be set
up such that you can download files from the buckets referenced in the rules
with `aws s3 cp`. `--profile` flag is also supported, for people who use
multiple profiles.

## Usage

Please refer to `WORKSPACE` file in this repository for an example of how to
use this.

## Future work

Quite obviously this can also be adapted to other cloud storage providers,
basically anything that can download an archive from the command line should
work.

## License

This software is licensed under Apache 2.0.
