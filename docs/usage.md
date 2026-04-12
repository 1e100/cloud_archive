# Usage

cloud\_archive provides Bazel repository rules that download private
dependencies from cloud storage (S3, Google Cloud Storage, Minio, Backblaze B2)
using the provider's CLI tool. Archives are checksummed, extracted, and
optionally patched before being made available as standard Bazel repos.

## Bzlmod (Bazel 8+, recommended)

### 1. Add the dependency

```python
# MODULE.bazel
bazel_dep(name = "cloud_archive", version = "1.0.0")
```

### 2. (Optional) Configure CLI tool binaries

By default, cloud\_archive finds CLI tools (`aws`, `gsutil`, `mc`, `b2`) on
`$PATH`. If you manage these tools as Bazel dependencies, register them once
with the module extension and every rule in the repo will use them automatically:

```python
# MODULE.bazel
cloud_archive = use_extension("@cloud_archive//:extensions.bzl", "cloud_archive")
cloud_archive.configure(
    s3 = "@my_awscli//:aws",       # used by s3_archive / s3_file
    gs = "@my_gsutil//:gsutil",     # used by gs_archive / gs_file
    # minio = "@my_mc//:mc",       # used by minio_archive / minio_file
    # b2 = "@my_b2//:b2",          # used by b2_archive / b2_file
)
use_repo(cloud_archive, "cloud_archive_tools")
```

All fields are optional. Omitted providers fall back to `$PATH`. The root
module's configuration takes precedence over any transitive dependency's.

### 3. Declare repository rules

Use `use_repo_rule` to load and invoke the rules:

```python
# MODULE.bazel
s3_archive = use_repo_rule("@cloud_archive//:cloud_archive.bzl", "s3_archive")

s3_archive(
    name = "my_model_weights",
    bucket = "my-ml-artifacts",
    file_path = "models/v3/weights.tar.gz",
    sha256 = "abc123...",
    strip_prefix = "weights",
    build_file = "//third_party:model_weights.BUILD",
)
```

For single files (no extraction):

```python
s3_file = use_repo_rule("@cloud_archive//:cloud_archive.bzl", "s3_file")

s3_file(
    name = "my_binary",
    bucket = "my-tools",
    file_path = "binaries/tool-v2",
    sha256 = "def456...",
    executable = True,
)
```

### 4. Use in BUILD files

Downloaded archives and files become standard Bazel repos. Reference them with
`@name` in your BUILD files:

```python
# BUILD
cc_binary(
    name = "train",
    srcs = ["train.cc"],
    data = ["@my_model_weights//:files"],
)

sh_binary(
    name = "run_tool",
    srcs = ["wrapper.sh"],
    data = ["@my_binary//file:file"],
)
```

Archive rules (`*_archive`) expose the targets defined in the `build_file` or
`build_file_contents` you provide. File rules (`*_file`) expose a single
`filegroup` at `//file:file`.

## WORKSPACE (legacy)

For Bazel versions before 8, or projects that have not yet migrated to bzlmod:

```python
# WORKSPACE
workspace(name = "my_project")

load("@cloud_archive//:cloud_archive.bzl", "cloud_archive_setup", "gs_archive", "s3_archive", "s3_file")

cloud_archive_setup()

s3_archive(
    name = "my_model_weights",
    bucket = "my-ml-artifacts",
    file_path = "models/v3/weights.tar.gz",
    sha256 = "abc123...",
    strip_prefix = "weights",
    build_file = "//third_party:model_weights.BUILD",
)

gs_archive(
    name = "my_dataset",
    bucket = "my-datasets",
    file_path = "data/train.tar.zst",
    sha256 = "789fed...",
    strip_prefix = "train",
    build_file_contents = """
package(default_visibility = ["//visibility:public"])
filegroup(name = "files", srcs = glob(["**"]))
""",
)
```

BUILD file usage is identical to the bzlmod case. The `@name` references work
the same way regardless of how the repo rule was registered.

Note: the module extension (`cloud_archive.configure`) is not available in
WORKSPACE mode. To use a Bazel-managed CLI binary, set the `tool_target`
attribute on each rule invocation:

```python
s3_archive(
    name = "my_dep",
    tool_target = "@my_awscli//:aws",
    # ... other attrs
)
```

## Available rules

| Rule | Provider | Type |
| --- | --- | --- |
| `s3_archive` | AWS S3 | archive |
| `s3_file` | AWS S3 | file |
| `gs_archive` | Google Cloud Storage | archive |
| `gs_file` | Google Cloud Storage | file |
| `minio_archive` | Minio | archive |
| `minio_file` | Minio | file |
| `b2_archive` | Backblaze B2 | archive |
| `b2_file` | Backblaze B2 | file |

### Common attributes (all rules)

| Attribute | Required | Description |
| --- | --- | --- |
| `name` | yes | Repository name |
| `file_path` | yes | Path to the file within the bucket (or minio path) |
| `sha256` | yes | Expected SHA-256 checksum |
| `tool_target` | no | Label to a CLI binary; overrides both extension config and `$PATH` |

### Archive-only attributes

| Attribute | Description |
| --- | --- |
| `build_file` | Label of a BUILD file to use for the extracted archive |
| `build_file_contents` | Inline BUILD file contents (takes priority over `build_file`) |
| `strip_prefix` | Directory prefix to strip from the archive |
| `patches` | List of patch file labels to apply |
| `patch_args` | Arguments for the patch tool (e.g. `["-p1"]`) |
| `patch_cmds` | Shell commands to run after patching |

### File-only attributes

| Attribute | Description |
| --- | --- |
| `downloaded_file_path` | Filename for the downloaded file (default: `"downloaded"`) |
| `executable` | Whether to make the downloaded file executable |

### Provider-specific attributes

| Attribute | Providers | Description |
| --- | --- | --- |
| `bucket` | S3, GCS, B2 | Bucket name |
| `profile` | S3 | AWS CLI profile for authentication |
| `file_version` | S3 | Version ID for versioned buckets |

## Tool resolution order

When a cloud rule executes, it resolves the CLI binary in this order:

1. **Per-rule `tool_target`** attribute, if set.
2. **Module extension** config from `cloud_archive.configure()`, if the provider
   was configured.
3. **`$PATH`** lookup (e.g. `which aws`).

This means you can configure tools globally via the extension, then override a
specific rule if needed.
