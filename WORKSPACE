workspace(name = "cloud_archive")

load(":cloud_archive.bzl", "s3_archive")

s3_archive(
    name = "archive",
    build_file = "//:BUILD.archive",
    sha256 = "d0ff6239646b3a60e4d8926402281311e003ae03183b1ae24f2adba5d9289f04",
    strip_prefix = "cloud_archive_test",
    url = "s3://depthwise-temp/cloud_archive_test.zip",
)
