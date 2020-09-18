""" This rule will download an archive from Minio, Google Storage, S3 or
Backblaze, check sha256, extract it, and symlink the provided BUILD file
inside. """

# License: Apache 2.0
# Provenance: https://github.com/1e100/cloud_archive

def validate_checksum(repo_ctx, url, local_path, expected_sha256):
    # Verify checksum
    sha256_path = repo_ctx.which("sha256sum")
    repo_ctx.report_progress("Checksumming {}.".format(local_path))
    sha256_result = repo_ctx.execute([sha256_path, local_path])
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
    # Extract the downloaded archive.
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

def cloud_archive_download(
        repo_ctx,
        file_path,
        expected_sha256,
        provider,
        bucket = "",
        strip_prefix = "",
        build_file = "",
        build_file_contents = "",
        profile = ""):
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
      src_url = "s3://{}/{}".format(bucket, file_path)
      cmd = [tool_path] + extra_flags + ["s3", "cp", src_url, "."]
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
    extract_archive(repo_ctx, filename, strip_prefix, build_file, build_file_contents)

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
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "_provider": attr.string(default="minio"),
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
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "_provider": attr.string(default="s3"),
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
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "_provider": attr.string(default="google"),
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
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
        "_provider": attr.string(default="backblaze"),
    },
)
