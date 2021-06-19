workspace(name = "cloud_archive")

load(":cloud_archive.bzl", "gs_archive", "minio_archive", "s3_archive")

s3_archive(
    name = "archive_s3",
    bucket = "1e100-temp",
    build_file = "//:BUILD.archive",
    file_path = "cloud_archive_test.zip",
    sha256 = "d0ff6239646b3a60e4d8926402281311e003ae03183b1ae24f2adba5d9289f04",
    strip_prefix = "cloud_archive_test",
)

minio_archive(
    name = "archive_minio_gz",
    build_file = "//:BUILD.archive",
    file_path = "minio/temp/cloud_archive_test.tar.gz",
    sha256 = "bf4dd5304180561a745e816ee6a8db974a3fcf5b9d706a493776d77202c48bc9",
    strip_prefix = "cloud_archive_test",
)

minio_archive(
    name = "archive_minio_zstd",
    build_file = "//:BUILD.archive",
    file_path = "minio/temp/cloud_archive_test.tar.zst",
    sha256 = "1891c85349f519206a2a2aa21f4927146b8cf84db04d3be91e0b54ce564d8b73",
    strip_prefix = "dir1",
)

gs_archive(
    name = "archive_gcloud_gz",
    bucket = "depthwise-temp",
    build_file = "//:BUILD.archive",
    file_path = "cloud_archive_test.tar.gz",
    sha256 = "bf4dd5304180561a745e816ee6a8db974a3fcf5b9d706a493776d77202c48bc9",
    strip_prefix = "cloud_archive_test",
)

gs_archive(
    name = "archive_gcloud_zstd",
    bucket = "depthwise-temp",
    build_file = "//:BUILD.archive",
    file_path = "cloud_archive_test.tar.zst",
    sha256 = "1891c85349f519206a2a2aa21f4927146b8cf84db04d3be91e0b54ce564d8b73",
    strip_prefix = "dir1",
)

gs_archive(
    name = "archive_gcloud_zstd_strip2",
    bucket = "depthwise-temp",
    build_file = "//:BUILD.archive",
    file_path = "cloud_archive_test.tar.zst",
    sha256 = "1891c85349f519206a2a2aa21f4927146b8cf84db04d3be91e0b54ce564d8b73",
    strip_prefix = "dir1/dir2",
)

gs_archive(
    name = "archive_gcloud_zstd_patch",
    bucket = "depthwise-temp",
    build_file = "//:BUILD.archive",
    file_path = "cloud_archive_test.tar.zst",
    patch_args = ["-p1"],
    patches = ["//:test.patch"],
    sha256 = "1891c85349f519206a2a2aa21f4927146b8cf84db04d3be91e0b54ce564d8b73",
    strip_prefix = "dir1",
)
