# Integration Test Repository

```shell
bazel run //:minio_server
```

will start a [MinIO](https://docs.min.io) server locally.
By default, it serves from the `testdata/` directory.
There is a single bucket named `bucket`.

You can fetch the [AlStor client](https://docs.min.io/enterprise/aistor-object-store/reference/cli/) with `bazel`,

```shell
bazel build @mc_binary//file
```

This can be used from the command line by including the output on your `PATH`,

```shell
export PATH="$(bazel info execution_root)/external/mc_binary/file:$PATH"
```

The client's config is available in `mc/`.
There is a single alias named `local` with typical MinIO defaults set.
Again, we'll update our shell for convenience,

```shell
export MC_CONFIG_DIR="$PWD/mc"
```

You should now be able to access the server with `$ mc admin info local`.
You are now able to fetch the data using `bazel` and the `cloud_archive` rules,

**`minio_file`**:

```shell
bazel build @test_file//file
```

**`minio_archive`**:

```shell
bazel build @test_archive//:file.txt
```

## Tests

All of the above is done automatically when running the integration tests,

```shell
bazel run //:cloud_archive_test
```
