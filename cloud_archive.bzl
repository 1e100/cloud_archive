# This rule will download an archive from S3, check sha256, extract it, and
# symlink the provided BUILD file inside.

# License: Apache 2.0


def _s3_archive_impl(ctx):
    url = "s3://{}/{}".format(ctx.attr.bucket, ctx.attr.file_path)
    filename = ctx.path(url).basename

    # Download
    aws_cli_path = ctx.which("aws")
    profile_flags = []
    if ctx.attr.aws_profile:
        profile_flags = ["--profile", ctx.attr.aws_profile]
    aws_cli_cmd = [aws_cli_path] + profile_flags + ["s3", "cp", url, "."]
    s3_result = ctx.execute(aws_cli_cmd)
    if s3_result.return_code != 0:
        fail("Failed to download {} from S3: {}".format(url, s3_result.stderr))

    # Verify checksum
    sha256_path = ctx.which("sha256sum")
    sha256_result = ctx.execute([sha256_path, filename])
    if sha256_result.return_code != 0:
        fail("Failed to verify checksum: {}".format(sha256_result.stderr))
    sha256 = sha256_result.stdout.split(" ")[0]
    if sha256 != ctx.attr.sha256:
        fail("Checksum mismatch for {}, expected {}, got {}.".format(
            url, ctx.attr.sha256, sha256))

    # Extract the downloaded archive.
    ctx.extract(filename, stripPrefix=ctx.attr.strip_prefix)

    # Provide external BUILD file if requested.
    bash_path = ctx.os.environ.get("BAZEL_SH", "bash")
    if ctx.attr.build_file:
        ctx.execute([bash_path, "-c", "rm -f BUILD BUILD.bazel"])
        ctx.symlink(ctx.attr.build_file, "BUILD.bazel")


s3_archive = repository_rule(
    implementation=_s3_archive_impl, attrs={
        "bucket":
        attr.string(mandatory=True, doc="S3 bucket name"),
        "file_path":
        attr.string(mandatory=True,
                    doc="Relative path to the archive file within the bucket"),
        "aws_profile":
        attr.string(doc="AWS profile to use for authentication"),
        "sha256":
        attr.string(mandatory=True, doc="SHA256 checksum of the archive"),
        "build_file":
        attr.label(allow_single_file=True,
                   doc="BUILD file for the unpacked archive"),
        "strip_prefix":
        attr.string(doc="Prefix to strip when archive is unpacked"),
    })
