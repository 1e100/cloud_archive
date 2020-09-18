workspace(name = "cloud_archive")

load(":cloud_archive.bzl", "s3_archive", "minio_archive")

s3_archive(
    name = "archive_s3",
    bucket = "1e100-temp",
    build_file = "//:BUILD.archive",
    file_path = "cloud_archive_test.zip",
    sha256 = "d0ff6239646b3a60e4d8926402281311e003ae03183b1ae24f2adba5d9289f04",
    strip_prefix = "cloud_archive_test",
)

minio_archive(
    name = "archive_minio",
    build_file = "//:BUILD.archive",
    file_path = "minio/temp/cloud_archive_test.tar.gz",
    sha256 = "bf4dd5304180561a745e816ee6a8db974a3fcf5b9d706a493776d77202c48bc9",
    strip_prefix = "cloud_archive_test",
)
