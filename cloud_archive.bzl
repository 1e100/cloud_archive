""" This rule will download an archive from S3, check sha256, extract it, and
symlink the provided BUILD file inside. """

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

def s3_archive_download(
        repo_ctx,
        s3_bucket,
        s3_file_path,
        expected_sha256,
        strip_prefix = "",
        build_file = "",
        build_file_contents = "",
        aws_profile = None):
    """ Securely downloads and unpacks an archive from S3, then places a
    BUILD file inside. """
    url = "s3://{}/{}".format(s3_bucket, s3_file_path)
    filename = repo_ctx.path(url).basename

    # Download
    aws_cli_path = repo_ctx.which("aws")
    profile_flags = []
    if aws_profile:
        profile_flags = ["--profile", aws_profile]
    aws_cli_cmd = [aws_cli_path] + profile_flags + ["s3", "cp", url, "."]
    repo_ctx.report_progress("Downloading {}.".format(url))
    s3_result = repo_ctx.execute(aws_cli_cmd, timeout = 1800)
    if s3_result.return_code != 0:
        fail("Failed to download {} from S3: {}".format(url, s3_result.stderr))

    validate_checksum(repo_ctx, url, filename, expected_sha256)
    extract_archive(repo_ctx, filename, strip_prefix, build_file, build_file_contents)

def _s3_archive_impl(ctx):
    s3_archive_download(
        ctx,
        ctx.attr.bucket,
        ctx.attr.file_path,
        ctx.attr.sha256,
        strip_prefix = ctx.attr.strip_prefix,
        build_file = ctx.attr.build_file,
        build_file_contents = ctx.attr.build_file_contents,
        aws_profile = ctx.attr.aws_profile,
    )

s3_archive = repository_rule(
    implementation = _s3_archive_impl,
    attrs = {
        "bucket": attr.string(mandatory = True, doc = "S3 bucket name"),
        "file_path": attr.string(
            mandatory = True,
            doc = "Relative path to the archive file within the bucket",
        ),
        "aws_profile": attr.string(doc = "AWS profile to use for authentication"),
        "sha256": attr.string(mandatory = True, doc = "SHA256 checksum of the archive"),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD file for the unpacked archive",
        ),
        "build_file_contents": attr.string(doc = "The contents of the build file for the target"),
        "strip_prefix": attr.string(doc = "Prefix to strip when archive is unpacked"),
    },
)

def minio_archive_download(
        repo_ctx,
        file_path,
        expected_sha256,
        strip_prefix = "",
        build_file = "",
        build_file_contents = ""):
    """ Securely downloads and unpacks an archive from Minio, then places a
    BUILD file inside. """
    filename = repo_ctx.path(file_path).basename

    # Download
    minio_cli_path = repo_ctx.which("mc")
    minio_cli_cmd = [minio_cli_path] + ["cp", "-q", file_path, "."]
    repo_ctx.report_progress("Downloading {}.".format(file_path))
    minio_result = repo_ctx.execute(minio_cli_cmd, timeout = 1800)
    if minio_result.return_code != 0:
        fail("Failed to download {} from Minio: {}".format(file_path, minio_result.stderr))

    validate_checksum(repo_ctx, file_path, filename, expected_sha256)
    extract_archive(repo_ctx, filename, strip_prefix, build_file, build_file_contents)

def _minio_archive_impl(ctx):
    minio_archive_download(
        ctx,
        ctx.attr.file_path,
        ctx.attr.sha256,
        strip_prefix = ctx.attr.strip_prefix,
        build_file = ctx.attr.build_file,
        build_file_contents = ctx.attr.build_file_contents,
    )

minio_archive = repository_rule(
    implementation = _minio_archive_impl,
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
    },
)
