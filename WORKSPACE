workspace(name = "cloud_archive")

load(":cloud_archive.bzl", "s3_archive")

s3_archive(
    name = "archive",
    bucket = "1e100-temp",
    build_file = "//:BUILD.archive",
    file_path = "cloud_archive_test.zip",
    sha256 = "d0ff6239646b3a60e4d8926402281311e003ae03183b1ae24f2adba5d9289f04",
    strip_prefix = "cloud_archive_test",
)
