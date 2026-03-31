""" This rule will download an archive from Minio, Google Storage, S3 or
Backblaze, check sha256, extract it, and symlink the provided BUILD file
inside. """

# License: Apache 2.0
# Provenance: https://github.com/1e100/cloud_archive

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "patch")

_CLOUD_FILE_BUILD = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "file",
    srcs = ["{}"],
)
"""

def validate_checksum(repo_ctx, url, local_path, expected_sha256):
    # Verify checksum
    if repo_ctx.os.name == "linux":
        sha256_cmd = [repo_ctx.which("sha256sum")]
    elif repo_ctx.os.name in ["mac os x", "darwin"]:
        sha256_cmd = [repo_ctx.which("shasum"), "-a", "256"]
    else:
        fail("Unsupported OS: " + repo_ctx.os.name)
    repo_ctx.report_progress("Checksumming {}.".format(local_path))
    sha256_result = repo_ctx.execute(sha256_cmd + [local_path])
    if sha256_result.return_code != 0:
        fail("Failed to verify checksum: {}".format(sha256_result.stderr))
    sha256 = sha256_result.stdout.split(" ")[0]
    if sha256 != expected_sha256:
        fail("Checksum mismatch for {}, expected {}, got {}.".format(
            url,
            expected_sha256,
            sha256,
        ))

def extract_archive(repo_ctx, local_path, strip_prefix, build_file, build_file_contents):
    # Since Bazel 5.1 (bazelbuild/bazel#15087), repo_ctx.extract handles zstd
    # natively, so no need to shell out to tar/zstd.
    repo_ctx.extract(local_path, stripPrefix = strip_prefix)

    # Provide external BUILD file if requested; `build_file_contents` takes
    # priority.
    bash_path = repo_ctx.os.environ.get("BAZEL_SH", "bash")
    if build_file_contents:
        repo_ctx.execute([bash_path, "-c", "rm -f BUILD BUILD.bazel"])
        repo_ctx.file("BUILD.bazel", build_file_contents, executable = False)
    elif build_file:
        repo_ctx.execute([bash_path, "-c", "rm -f BUILD BUILD.bazel"])
        repo_ctx.symlink(build_file, "BUILD.bazel")

_TOOL_TARGET_DOC = (
    "Optional label pointing to a pre-built CLI binary (e.g. @my_awscli//:aws). " +
    "When set, this binary is used instead of searching $PATH. The referenced " +
    "repository is fetched automatically before this rule executes."
)

_PROVIDER_TOOL_NAMES = {
    "minio": "mc",
    "google": "gsutil",
    "s3": "aws",
    "backblaze": "b2",
}

def _resolve_tool(repo_ctx, provider, tool_target):
    """Returns a path to the CLI binary for the given provider.

    If tool_target is set, resolves the label to a path (which causes
    Bazel to fetch that repository first). Otherwise falls back to
    repo_ctx.which() on $PATH.
    """
    if tool_target:
        return repo_ctx.path(tool_target)

    name = _PROVIDER_TOOL_NAMES.get(provider)
    if not name:
        fail("Provider not supported: " + provider)
    path = repo_ctx.which(name)
    if path == None:
        fail("Could not find '{}' on $PATH for provider {}. ".format(name, provider) +
             "Set tool_target to a label providing the binary instead.")
    return path

def cloud_file_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        bucket = "",
        profile = "",
        file_version = "",
        downloaded_file_path = "downloaded",
        executable = False,
        tool_target = None):
    """ Securely downloads a file from Minio, then places a BUILD file inside. """
    repo_root = repo_ctx.path(".")
    forbidden_files = [
        repo_root,
        repo_ctx.path("WORKSPACE"),
        repo_ctx.path("BUILD"),
        repo_ctx.path("BUILD.bazel"),
        repo_ctx.path("file/BUILD"),
        repo_ctx.path("file/BUILD.bazel"),
    ]
    download_path = repo_ctx.path("file/" + downloaded_file_path)
    if download_path in forbidden_files or not str(download_path).startswith(str(repo_root)):
        fail("'%s' cannot be used as file_path in http_file" % downloaded_file_path)

    # This has to be before the download otherwise some tools may fail to create the directory.
    repo_ctx.file("file/BUILD", _CLOUD_FILE_BUILD.format(downloaded_file_path))
    cloud_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        bucket,
        profile,
        file_version,
        "file/" + downloaded_file_path,
        tool_target = tool_target,
    )
    if executable:
        repo_ctx.execute(["chmod", "+x", "file/" + downloaded_file_path])

def cloud_archive_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        bucket = "",
        strip_prefix = "",
        build_file = "",
        build_file_contents = "",
        profile = "",
        file_version = "",
        tool_target = None):
    """ Securely downloads and unpacks an archive from Minio, then places a
    BUILD file inside. """
    filename = repo_ctx.path(file_path).basename

    # Download to the basename so extraction can find the file, even when
    # file_path contains directory components (e.g. minio paths).
    cloud_download(repo_ctx, file_path, expected_sha256, provider, bucket, profile, file_version, filename, tool_target = tool_target)

    # Extract
    extract_archive(repo_ctx, filename, strip_prefix, build_file, build_file_contents)

    # Patch using Bazel's built-in utility, which reads patches, patch_args,
    # and patch_cmds directly from repo_ctx.attr.
    patch(repo_ctx)

def cloud_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        bucket = "",
        profile = "",
        file_version = "",
        downloaded_file_path = "",
        tool_target = None):
    """ Securely downloads a file from a cloud provider. """
    downloaded_file_path = downloaded_file_path or file_path

    # Download tooling is pretty similar, but commands are different. Note that
    # Minio does not support bucket per se. The path is expected to contain what
    # you'd normally feed into `mc`.
    if provider == "local":
        # Local provider: file_path is an absolute path to a local file.
        # Just copy it; no external tool needed.
        tool_path = repo_ctx.which("cp")
        if tool_path == None:
            fail("Could not find 'cp' command.")
        src_url = file_path
        cmd = [tool_path, file_path, downloaded_file_path]
    else:
        tool_path = _resolve_tool(repo_ctx, provider, tool_target)

        if provider == "minio":
            src_url = file_path
            cmd = [tool_path, "cp", "-q", src_url, downloaded_file_path]
        elif provider == "google":
            src_url = "gs://{}/{}".format(bucket, file_path)
            cmd = [tool_path, "cp", src_url, downloaded_file_path]
        elif provider == "s3":
            extra_flags = ["--profile", profile] if profile else []
            bucket_arg = ["--bucket", bucket]
            file_arg = ["--key", file_path]
            file_version_arg = ["--version-id", file_version] if file_version else []
            src_url = repo_ctx.path(file_path).basename
            cmd = [tool_path] + extra_flags + ["s3api", "get-object"] + bucket_arg + file_arg + file_version_arg + [downloaded_file_path]
        elif provider == "backblaze":
            # NOTE: currently untested, as I don't have a B2 account.
            src_url = "b2://{}/{}".format(bucket, file_path)
            cmd = [tool_path, "download-file-by-name", "--noProgress", bucket, file_path, downloaded_file_path]

    # Download.
    repo_ctx.report_progress("Downloading {}.".format(src_url))
    result = repo_ctx.execute(cmd, timeout = 1800)
    if result.return_code != 0:
        fail("Failed to download {} from {}: {}".format(src_url, provider, result.stderr))

    # Verify.
    validate_checksum(repo_ctx, file_path, downloaded_file_path, expected_sha256)

def _local_file_impl(ctx):
    """Implementation of the local file rule."""
    cloud_file_download(
        ctx,
        str(ctx.path(ctx.attr.src)),
        ctx.attr.sha256,
        provider = "local",
        downloaded_file_path = ctx.attr.downloaded_file_path,
        executable = ctx.attr.executable,
    )

def _local_archive_impl(ctx):
    """Implementation of the local archive rule."""
    cloud_archive_download(
        ctx,
        str(ctx.path(ctx.attr.src)),
        ctx.attr.sha256,
        provider = "local",
        strip_prefix = ctx.attr.strip_prefix,
        build_file = ctx.attr.build_file,
        build_file_contents = ctx.attr.build_file_contents,
    )

def _cloud_file_impl(ctx):
    """Implementation of the provider-agnostic, file-based rule."""
    cloud_file_download(
        ctx,
        ctx.attr.file_path,
        ctx.attr.sha256,
        provider = ctx.attr._provider,
        profile = ctx.attr.profile if hasattr(ctx.attr, "profile") else "",
        bucket = ctx.attr.bucket if hasattr(ctx.attr, "bucket") else "",
        file_version = ctx.attr.file_version if hasattr(ctx.attr, "file_version") else "",
        downloaded_file_path = ctx.attr.downloaded_file_path,
        executable = ctx.attr.executable,
        tool_target = ctx.attr.tool_target,
    )

def _cloud_archive_impl(ctx):
    cloud_archive_download(
        ctx,
        ctx.attr.file_path,
        ctx.attr.sha256,
        provider = ctx.attr._provider,
        strip_prefix = ctx.attr.strip_prefix,
        build_file = ctx.attr.build_file,
        build_file_contents = ctx.attr.build_file_contents,
        profile = ctx.attr.profile if hasattr(ctx.attr, "profile") else "",
        bucket = ctx.attr.bucket if hasattr(ctx.attr, "bucket") else "",
        file_version = ctx.attr.file_version if hasattr(ctx.attr, "file_version") else "",
        tool_target = ctx.attr.tool_target,
    )

minio_file = repository_rule(
    implementation = _cloud_file_impl,
    attrs = {
        "file_path": attr.string(
            mandatory = True,
            doc = "Path to the file on minio. Backend needs to be set up locally for this to work.",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "downloaded_file_path": attr.string(
            default = "downloaded",
            doc = "Path assigned to the file downloaded",
        ),
        "executable": attr.bool(doc="If the downloaded file should be made executable."),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "minio"),
    },
)

minio_archive = repository_rule(
    implementation = _cloud_archive_impl,
    attrs = {
        "file_path": attr.string(
            mandatory = True,
            doc = "Path to the file on minio. Backend needs to be set up locally for this to work.",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD file for the unpacked archive",
        ),
        "build_file_contents": attr.string(doc = "The contents of the build file for the target"),
        "patches": attr.label_list(doc = "Patches to apply, if any.", allow_files = True),
        "patch_args": attr.string_list(doc = "Arguments to use when applying patches."),
        "patch_cmds": attr.string_list(doc = "Sequence of Bash commands to be applied after patches are applied."),
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "minio"),
    },
)

s3_file = repository_rule(
    implementation = _cloud_file_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "Bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "downloaded_file_path": attr.string(
            default = "downloaded",
            doc = "Path assigned to the file downloaded",
        ),
        "executable": attr.bool(doc="If the downloaded file should be made executable."),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "s3"),
    },
)

s3_archive = repository_rule(
    implementation = _cloud_archive_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "Bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "profile": attr.string(doc = "Profile to use for authentication."),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD file for the unpacked archive",
        ),
        "build_file_contents": attr.string(doc = "The contents of the build file for the target"),
        "patches": attr.label_list(doc = "Patches to apply, if any.", allow_files = True),
        "patch_args": attr.string_list(doc = "Arguments to use when applying patches."),
        "patch_cmds": attr.string_list(doc = "Sequence of Bash commands to be applied after patches are applied."),
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "file_version": attr.string(doc = "file version id of object if bucket is versioned"),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "s3"),
    },
)

gs_file = repository_rule(
    implementation = _cloud_file_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "Google Storage bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "downloaded_file_path": attr.string(
            default = "downloaded",
            doc = "Path assigned to the file downloaded",
        ),
        "executable": attr.bool(doc="If the downloaded file should be made executable."),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "google"),
    },
)

gs_archive = repository_rule(
    implementation = _cloud_archive_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "Google Storage bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD file for the unpacked archive",
        ),
        "build_file_contents": attr.string(doc = "The contents of the build file for the target"),
        "patches": attr.label_list(doc = "Patches to apply, if any.", allow_files = True),
        "patch_args": attr.string_list(doc = "Arguments to use when applying patches."),
        "patch_cmds": attr.string_list(doc = "Sequence of Bash commands to be applied after patches are applied."),
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "google"),
    },
)

b2_file = repository_rule(
    implementation = _cloud_file_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "Backblaze B2 bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "downloaded_file_path": attr.string(
            default = "downloaded",
            doc = "Path assigned to the file downloaded",
        ),
        "executable": attr.bool(doc="If the downloaded file should be made executable."),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "backblaze"),
    },
)

b2_archive = repository_rule(
    implementation = _cloud_archive_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "Backblaze B2 bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD file for the unpacked archive",
        ),
        "build_file_contents": attr.string(doc = "The contents of the build file for the target"),
        "patches": attr.label_list(doc = "Patches to apply, if any.", allow_files = True),
        "patch_args": attr.string_list(doc = "Arguments to use when applying patches."),
        "patch_cmds": attr.string_list(doc = "Sequence of Bash commands to be applied after patches are applied."),
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "tool_target": attr.label(allow_single_file = True, doc = _TOOL_TARGET_DOC),
        "_provider": attr.string(default = "backblaze"),
    },
)

# The local_file and local_archive rules exist solely for testing. They
# exercise the full pipeline (checksum, extraction, strip_prefix, patching,
# patch_cmds, BUILD file generation) without requiring any cloud backend.
# There is no other reason to use them; for real dependencies, use one of the
# cloud provider rules above.

local_file = repository_rule(
    implementation = _local_file_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Label of the local file to use.",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the file"),
        "downloaded_file_path": attr.string(
            default = "downloaded",
            doc = "Path assigned to the file downloaded",
        ),
        "executable": attr.bool(doc = "If the downloaded file should be made executable."),
    },
)

local_archive = repository_rule(
    implementation = _local_archive_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Label of the local archive file to use.",
        ),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD file for the unpacked archive",
        ),
        "build_file_contents": attr.string(doc = "The contents of the build file for the target"),
        "patches": attr.label_list(doc = "Patches to apply, if any.", allow_files = True),
        "patch_args": attr.string_list(doc = "Arguments to use when applying patches."),
        "patch_cmds": attr.string_list(doc = "Sequence of Bash commands to be applied after patches are applied."),
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
    },
)
