""" This rule will download an archive from Minio, Google Storage, S3 or
Backblaze, check sha256, extract it, and symlink the provided BUILD file
inside. """

# License: Apache 2.0
# Provenance: https://github.com/1e100/cloud_archive

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
    bash_path = repo_ctx.os.environ.get("BAZEL_SH", "bash")
    if local_path.endswith(".tar.zst") or local_path.endswith(".tzst"):
        # Recent TAR supports zstd, if the compressor is installed.
        zst_path = repo_ctx.which("zstd")
        if zst_path == None:
            fail("To decompress .tar.zst, install zstd.")
        tar_path = repo_ctx.which("tar")
        if tar_path == None:
            fail("To decompress .tar.zst, install tar.")
        extra_tar_params = []
        if strip_prefix != None and strip_prefix:
            # Trick: we need to extract a subdir, and remove its components
            # from the path. We do so via `tar xvf file.tar.zst sub/dir
            # --strip-components=N`. Here we figure out the N.
            num_components = 0
            prefix = strip_prefix.strip("/")
            for c in prefix.split("/"):
                if len(c) > 0:
                    num_components += 1
            extra_tar_params = [prefix, "--strip-components=" + str(num_components)]

        # Decompress with tar, piping through zstd internally, and stripping prefix
        # if requested.
        tar_cmd = [tar_path, "-x", "-f", local_path] + extra_tar_params
        repo_ctx.execute(tar_cmd)
    else:
        # Extract the downloaded archive using Bazel's built-in decompressors.
        repo_ctx.extract(local_path, stripPrefix = strip_prefix)

    # Provide external BUILD file if requested; `build_file_contents` takes
    # priority.
    if build_file_contents:
        repo_ctx.execute([bash_path, "-c", "rm -f BUILD BUILD.bazel"])
        repo_ctx.file("BUILD.bazel", build_file_contents, executable = False)
    elif build_file:
        repo_ctx.execute([bash_path, "-c", "rm -f BUILD BUILD.bazel"])
        repo_ctx.symlink(build_file, "BUILD.bazel")

def cloud_archive_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        patches,
        patch_args,
        bucket = "",
        strip_prefix = "",
        build_file = "",
        build_file_contents = "",
        profile = "",
        patch_cmds = [],
        file_version = ""):
    """ Securely downloads and unpacks an archive from Minio, then places a
    BUILD file inside. """
    filename = repo_ctx.path(file_path).basename

    # Download tooling is pretty similar, but commands are different. Note that
    # Minio does not support bucket per se. The path is expected to contain what
    # you'd normally feed into `mc`.
    if provider == "minio":
        tool_path = repo_ctx.which("mc")
        src_url = file_path
        cmd = [tool_path, "cp", "-q", src_url, "."]
    elif provider == "google":
        tool_path = repo_ctx.which("gsutil")
        src_url = "gs://{}/{}".format(bucket, file_path)
        cmd = [tool_path, "cp", src_url, "."]
    elif provider == "s3":
        tool_path = repo_ctx.which("aws")
        extra_flags = ["--profile", profile] if profile else []
        bucket_arg = ["--bucket", bucket]
        file_arg = ["--key", file_path]
        file_version_arg = ["--version-id", file_version] if file_version else []
        src_url = filename
        cmd = [tool_path] + extra_flags + ["s3api", "get-object"] + bucket_arg + file_arg + file_version_arg + [filename]
    elif provider == "backblaze":
        # NOTE: currently untested, as I don't have a B2 account.
        tool_path = repo_ctx.which("b2")
        src_url = "b2://{}/{}".format(bucket, file_path)
        cmd = [tool_path, "download-file-by-name", "--noProgress", bucket, file_path, "."]
    else:
        fail("Provider not supported: " + provider.capitalize())

    if tool_path == None:
        fail("Could not find command line utility for {}".format(provider.capitalize()))

    # Download.
    repo_ctx.report_progress("Downloading {}.".format(src_url))
    result = repo_ctx.execute(cmd, timeout = 1800)
    if result.return_code != 0:
        fail("Failed to download {} from {}: {}".format(src_url, provider.capitalize(), result.stderr))

    # Verify.
    filename = repo_ctx.path(src_url).basename
    validate_checksum(repo_ctx, file_path, filename, expected_sha256)

    # Extract
    extract_archive(repo_ctx, filename, strip_prefix, build_file, build_file_contents)

    # If patches are provided, apply them.
    if patches != None and len(patches) > 0:
        patches = [str(repo_ctx.path(patch)) for patch in patches]

        # Built in Bazel patch only supports -pN or no parameters at all, so we
        # determine if we can use the built in patch.
        only_strip_param = (patch_args != None and
                            len(patch_args) == 1 and
                            patch_args[0].startswith("-p") and
                            patch_args[0][2:].isdigit())
        strip_n = 0
        if only_strip_param:
            strip_n = int(patch_args[0][2])

        if patch_args == None or only_strip_param:
            # OK to use built-in patch.
            for patch in patches:
                repo_ctx.patch(patch, strip = strip_n)
        else:
            # Must use extrenal patch. Note that this hasn't been tested, so it
            # might not work. If it's busted, please send a PR.
            patch_path = repo_ctx.which("patch")
            for patch in patches:
                patch_cmd = [patch_path] + patch_args + ["-i", patch]
                result = repo_ctx.execute(patch_cmd)
                if result.return_code != 0:
                    fail("Patch {} failed to apply.".format(patch))

    # apply patch_cmds one by one after all patches have been applied
    bash_path = repo_ctx.os.environ.get("BAZEL_SH", "bash")
    for cmd in patch_cmds:
        repo_ctx.execute([bash_path, "-c", cmd])

def _cloud_archive_impl(ctx):
    cloud_archive_download(
        ctx,
        ctx.attr.file_path,
        ctx.attr.sha256,
        provider = ctx.attr._provider,
        patches = ctx.attr.patches,
        patch_args = ctx.attr.patch_args,
        patch_cmds = ctx.attr.patch_cmds,
        strip_prefix = ctx.attr.strip_prefix,
        build_file = ctx.attr.build_file,
        build_file_contents = ctx.attr.build_file_contents,
        profile = ctx.attr.profile if hasattr(ctx.attr, "profile") else "",
        bucket = ctx.attr.bucket if hasattr(ctx.attr, "bucket") else "",
        file_version = ctx.attr.file_version if hasattr(ctx.attr, "file_version") else "",
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
        "_provider": attr.string(default = "minio"),
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
        "_provider": attr.string(default = "s3"),
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
        "_provider": attr.string(default = "google"),
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
        "_provider": attr.string(default = "backblaze"),
    },
)
