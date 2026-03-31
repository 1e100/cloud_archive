"""Module extension for configuring cloud_archive tool dependencies."""

def _tools_config_impl(rctx):
    rctx.file("BUILD.bazel", "")
    rctx.file("config.json", rctx.attr.config_json)

_tools_config = repository_rule(
    implementation = _tools_config_impl,
    attrs = {"config_json": attr.string(mandatory = True)},
)

_configure_tag = tag_class(
    doc = "Configure which CLI binaries cloud_archive rules use. " +
          "When a tool label is provided, that binary is fetched and used " +
          "instead of searching $PATH. Call this at most once per module.",
    attrs = {
        "s3": attr.label(
            allow_single_file = True,
            doc = "Label for the aws CLI binary (used by s3_archive/s3_file).",
        ),
        "gs": attr.label(
            allow_single_file = True,
            doc = "Label for the gsutil CLI binary (used by gs_archive/gs_file).",
        ),
        "minio": attr.label(
            allow_single_file = True,
            doc = "Label for the mc CLI binary (used by minio_archive/minio_file).",
        ),
        "b2": attr.label(
            allow_single_file = True,
            doc = "Label for the b2 CLI binary (used by b2_archive/b2_file).",
        ),
    },
)

def _cloud_archive_impl(mctx):
    config = {}

    # Root module's tags take precedence (mctx.modules is root-first).
    for mod in mctx.modules:
        for tag in mod.tags.configure:
            if tag.s3 and "s3" not in config:
                config["s3"] = str(tag.s3)
            if tag.gs and "google" not in config:
                config["google"] = str(tag.gs)
            if tag.minio and "minio" not in config:
                config["minio"] = str(tag.minio)
            if tag.b2 and "backblaze" not in config:
                config["backblaze"] = str(tag.b2)

    _tools_config(name = "cloud_archive_tools", config_json = json.encode(config))

cloud_archive = module_extension(
    implementation = _cloud_archive_impl,
    tag_classes = {"configure": _configure_tag},
)
