# cloud_archive

`cloud_archive` provides Bazel repository rules for downloading private files
and archives from cloud storage with the provider's CLI, verifying them by
SHA-256, and exposing them as normal external repositories.

Supported providers:

- AWS S3
- Google Cloud Storage
- MinIO
- Backblaze B2

Archive rules can extract content, apply `strip_prefix` and `add_prefix`, and
run patches before the repository becomes available to the build. The project
supports both Bzlmod and legacy `WORKSPACE` usage.

## Requirements

- Bazel. This repository is pinned to `8.5.1` in `.bazelversion`.
- Linux or macOS.
- A provider CLI available one of these ways:
  - on `$PATH`
  - configured once via `cloud_archive.configure()` in Bzlmod
  - passed per rule via `tool_target`
- The CLI must already be authenticated so its native download command works:
  - S3: `aws s3api get-object`
  - GCS: `gsutil cp`
  - MinIO: `mc cp`
  - B2: `b2 download-file-by-name`

## Bzlmod Usage

Bzlmod is the recommended setup for Bazel 8+.

### 1. Add the dependency

```starlark
# MODULE.bazel
bazel_dep(name = "cloud_archive", version = "<released version>")
```

### 2. Optional: configure CLI tools once

If the provider CLIs are already on `$PATH`, you can skip this. If you manage
them as Bazel dependencies, configure them once with the module extension and
every `cloud_archive` rule in the repo will use them automatically.

```starlark
# MODULE.bazel
cloud_archive = use_extension("@cloud_archive//:extensions.bzl", "cloud_archive")

cloud_archive.configure(
    s3 = "@my_awscli//:aws",
    gs = "@my_gsutil//:gsutil",
    # minio = "@my_mc//:mc",
    # b2 = "@my_b2//:b2",
)

use_repo(cloud_archive, "cloud_archive_tools")
```

All fields are optional. Omitted providers fall back to `$PATH`. When multiple
modules configure tools, the root module wins.

### 3. Declare repository rules

Use `use_repo_rule()` to instantiate the rules you need:

```starlark
# MODULE.bazel
s3_archive = use_repo_rule("@cloud_archive//:cloud_archive.bzl", "s3_archive")
gs_file = use_repo_rule("@cloud_archive//:cloud_archive.bzl", "gs_file")

s3_archive(
    name = "model_weights",
    bucket = "my-ml-artifacts",
    file_path = "models/v3/weights.tar.gz",
    sha256 = "abc123...",
    strip_prefix = "weights",
    build_file = "//third_party:model_weights.BUILD",
)

gs_file(
    name = "deploy_tool",
    bucket = "my-tools",
    file_path = "bin/tool-linux-amd64",
    sha256 = "def456...",
    executable = True,
)
```

### 4. Use the repositories in BUILD files

Archive rules expose whatever targets are defined by `build_file` or
`build_file_contents`. File rules expose a single `filegroup` at
`@name//file:file`.

```starlark
# BUILD.bazel
cc_binary(
    name = "train",
    srcs = ["train.cc"],
    data = ["@model_weights//:files"],
)

sh_binary(
    name = "run_tool",
    srcs = ["wrapper.sh"],
    data = ["@deploy_tool//file:file"],
)
```

## WORKSPACE Usage

Use this only for projects that still rely on legacy external dependency
registration.

### 1. Add `cloud_archive` itself

```starlark
# WORKSPACE
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "cloud_archive",
    sha256 = "<release archive sha256>",
    strip_prefix = "cloud_archive-<version>",
    urls = ["https://github.com/1e100/cloud_archive/archive/refs/tags/<version>.tar.gz"],
)
```

### 2. Register the helper repo and declare rules

In `WORKSPACE` mode there is no module extension, so call
`cloud_archive_setup()` once before declaring any `cloud_archive` rules.

```starlark
# WORKSPACE
load(
    "@cloud_archive//:cloud_archive.bzl",
    "cloud_archive_setup",
    "gs_archive",
    "s3_archive",
)

cloud_archive_setup()

s3_archive(
    name = "model_weights",
    bucket = "my-ml-artifacts",
    file_path = "models/v3/weights.tar.gz",
    sha256 = "abc123...",
    strip_prefix = "weights",
    build_file = "//third_party:model_weights.BUILD",
)

gs_archive(
    name = "training_data",
    bucket = "my-datasets",
    file_path = "train/train.tar.zst",
    sha256 = "789fed...",
    strip_prefix = "train",
    build_file_contents = """
package(default_visibility = ["//visibility:public"])
filegroup(name = "files", srcs = glob(["**"]))
""",
)
```

If you need to use a Bazel-managed CLI binary in `WORKSPACE` mode, set
`tool_target` on that rule directly:

```starlark
s3_archive(
    name = "private_dep",
    bucket = "my-bucket",
    file_path = "deps/private_dep.tar.gz",
    sha256 = "012345...",
    tool_target = "@my_awscli//:aws",
    build_file = "//third_party:private_dep.BUILD",
)
```

BUILD file usage is otherwise identical to the Bzlmod case.

## Available Rules

| Rule | Provider | Type |
| --- | --- | --- |
| `s3_archive` | AWS S3 | archive |
| `s3_file` | AWS S3 | file |
| `gs_archive` | Google Cloud Storage | archive |
| `gs_file` | Google Cloud Storage | file |
| `minio_archive` | MinIO | archive |
| `minio_file` | MinIO | file |
| `b2_archive` | Backblaze B2 | archive |
| `b2_file` | Backblaze B2 | file |

For MinIO rules, `file_path` should be the full `mc` source path, for example
`"local/mybucket/path/to/archive.tar.zst"`. The other providers use separate
`bucket` and `file_path` attributes.

## Rule Attributes

### Common attributes

| Attribute | Required | Description |
| --- | --- | --- |
| `name` | yes | Repository name |
| `file_path` | yes | Object path inside the bucket, or the full MinIO source path |
| `sha256` | yes | Expected SHA-256 checksum |
| `tool_target` | no | Label of a CLI binary; overrides extension config and `$PATH` |
| `download_max_attempts` | no | Maximum download attempts before failing. Default: `3`. Set to `1` to disable retries. |
| `download_backoff_base` | no | Base delay in seconds between retry attempts; doubles each attempt (exponential backoff). Default: `5`. |

### Archive-only attributes

| Attribute | Description |
| --- | --- |
| `build_file` | Label of a BUILD file for the extracted archive |
| `build_file_contents` | Inline BUILD contents; takes precedence over `build_file` |
| `strip_prefix` | Directory prefix to strip during extraction |
| `add_prefix` | Directory prefix to add after extraction |
| `type` | Explicit archive type for extensionless files such as `tar.gz` or `tar.zst` |
| `patches` | Patch files to apply after extraction |
| `patch_args` | Arguments for the patch tool, for example `["-p1"]` |
| `patch_cmds` | Shell commands to run after patching |

### File-only attributes

| Attribute | Description |
| --- | --- |
| `downloaded_file_path` | Path assigned to the downloaded file inside the repo |
| `executable` | Whether to make the downloaded file executable |

### Provider-specific attributes

| Attribute | Providers | Description |
| --- | --- | --- |
| `bucket` | S3, GCS, B2 | Bucket name |
| `profile` | S3 | AWS CLI profile to use |
| `file_version` | S3 | Version ID for versioned objects |

## Tool Resolution Order

When a rule needs a provider CLI, it resolves it in this order:

1. Per-rule `tool_target`
2. Module extension config from `cloud_archive.configure()`
3. `$PATH`

That lets you set a default once for the whole repo, then override a specific
rule if needed.

## Testing

Run the repository-local tests with:

```sh
bazel test //...
```

That exercises the `local_file` and `local_archive` test rules without needing
real cloud credentials.

MinIO end-to-end coverage lives in [`e2e/README.md`](e2e/README.md) and can be
run with:

```sh
cd e2e
./run_tests.sh
```

That suite spins up a local MinIO server, configures `mc` via `MC_CONFIG_DIR`,
uploads test objects, and exercises the `local/bucket/key` MinIO path flow.

## License

Apache 2.0. See [`LICENSE`](LICENSE).
