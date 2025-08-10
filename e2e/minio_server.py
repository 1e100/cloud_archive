from __future__ import annotations

from contextlib import contextmanager
import os
import subprocess
import typing

from python.runfiles import Runfiles

MINIO_ACCESS_KEY = "minioadmin"
MINIO_SECRET_KEY = "minioadmin"  # noqa: S105


@contextmanager
def run(*_: typing.Any, port: int = 9000, wait: bool = False) -> typing.Generator:
    r = Runfiles.Create()
    minio_binary = r.Rlocation("minio_binary/file/minio")
    data_directory = os.path.dirname(
        os.path.dirname(
            os.path.dirname(
                r.Rlocation(
                    "my_workspace/testdata/bucket/file.txt/xl.meta"  # The particular file is not important.  # noqa: E501
                )
            )
        )
    )

    env = os.environ.copy()
    env["MINIO_ROOT_USER"] = MINIO_ACCESS_KEY
    env["MINIO_ROOT_PASSWORD"] = MINIO_SECRET_KEY

    proc = subprocess.Popen(  # noqa: S603
        [minio_binary, "server", f"--address=:{port}", data_directory],
        env=env,
    )

    try:
        if wait:
            proc.wait()
            return
        yield proc
    finally:
        if not wait:
            proc.terminate()
            proc.wait()


if __name__ == "__main__":
    with run(wait=True):
        pass
