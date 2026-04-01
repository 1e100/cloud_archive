#include <cstdio>
#include <filesystem>

namespace {

void PrintFileContents(const std::filesystem::path path) {
  printf("File contents:\n");
  size_t bytes_read = 0;
  char buf[256];
  FILE* f = fopen(path.string().c_str(), "r");
  if (f == nullptr) {
    throw std::invalid_argument("Failed to open file " + path.string());
  }
  while ((bytes_read = fread(buf, 1, sizeof(buf), f)) > 0) {
    fwrite(buf, 1, bytes_read, stdout);
    printf("\n");
  }
  fclose(f);
}

}  // namespace

int main() {
  PrintFileContents("external/archive_gcloud_gz/cloud_archive_test.txt");
  PrintFileContents("external/archive_gcloud_zstd/dir2/dir3/text3.txt");
  PrintFileContents("external/archive_gcloud_zstd_strip2/dir3/text3.txt");
  PrintFileContents("external/archive_gcloud_zstd_patch/dir2/dir3/text3.txt");

  return 0;
}
