#include <cstdio>

int main() {
  printf("S3 file contents:\n");
  size_t bytes_read = 0;
  char buf[256];
  FILE* f = fopen("external/archive/cloud_archive_test.txt", "r");
  if (f == nullptr) {
    fprintf(stderr, "Failed to open file.");
    return 1;
  }
  while ((bytes_read = fread(buf, 1, sizeof(buf), f)) > 0) {
    fwrite(buf, 1, bytes_read, stdout);
  }
  fclose(f);
  return 0;
}
