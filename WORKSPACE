workspace(name = "cloud_archive")

load(":cloud_archive.bzl", "gs_archive", "local_archive", "local_file", "minio_archive", "s3_archive")

# --- Local test targets (no cloud backend required) ---

local_file(
    name = "test_local_file",
    sha256 = "7c5fdb91d42da23cf7f42c786b20b770f64643bfd62ad7f52d3ab4c4fd189eff",
    src = "//testdata:test_file.txt",
)

local_archive(
    name = "test_local_archive_gz",
    build_file = "//:BUILD.archive",
    sha256 = "d793e5de917902aecfb73937028f5dbd29bc78c6c4bc096b3f59e4d576915eca",
    src = "//testdata:test_archive.tar.gz",
)

local_archive(
    name = "test_local_archive_zstd",
    build_file = "//:BUILD.archive",
    sha256 = "a403d6f57510c459f2c5c944fbc092e8e7de80900dd7c112838557a0e8e02d5f",
    src = "//testdata:test_archive.tar.zst",
    strip_prefix = "dir1",
)

local_archive(
    name = "test_local_archive_zstd_strip2",
    build_file = "//:BUILD.archive",
    sha256 = "a403d6f57510c459f2c5c944fbc092e8e7de80900dd7c112838557a0e8e02d5f",
    src = "//testdata:test_archive.tar.zst",
    strip_prefix = "dir1/dir2",
)

local_archive(
    name = "test_local_archive_patch",
    build_file = "//:BUILD.archive",
    patch_args = ["-p1"],
    patches = ["//testdata:test.patch"],
    sha256 = "a403d6f57510c459f2c5c944fbc092e8e7de80900dd7c112838557a0e8e02d5f",
    src = "//testdata:test_archive.tar.zst",
    strip_prefix = "dir1",
)

local_archive(
    name = "test_local_archive_patch_cmds",
    build_file = "//:BUILD.archive",
    patch_cmds = ["echo 'patched by cmd' > dir2/dir3/text3.txt"],
    sha256 = "a403d6f57510c459f2c5c944fbc092e8e7de80900dd7c112838557a0e8e02d5f",
    src = "//testdata:test_archive.tar.zst",
    strip_prefix = "dir1",
)

# --- Cloud targets (require configured backends) ---

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
