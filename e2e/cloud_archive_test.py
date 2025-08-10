from __future__ import annotations

import atexit
import os
import pathlib
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

import minio_server
from python.runfiles import Runfiles

MINIO_PORT = 9000

FILE_CONTENT = "go bears"
PATCHED_CONTENT = "Go Bears!"

# Always run in a new output_base to avoid false-negatives from caching.
TEMP_OUTPUT_BASE = tempfile.mkdtemp()
atexit.register(shutil.rmtree, TEMP_OUTPUT_BASE)


def wait_for_port(host: str, port: int, timeout: int = 5) -> bool:
    start = time.time()
    while time.time() - start < timeout:
        try:
            with socket.create_connection((host, port), timeout=1):
                return True
        except OSError:  # noqa: PERF203
            time.sleep(0.1)
    return False


class CloudArchiveTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        r = Runfiles.Create()
        mc_binary = r.Rlocation("mc_binary/file/mc")
        mc_config = r.Rlocation("my_workspace/mc/config.json")

        cls.env = {
            "PATH": f"{os.path.dirname(mc_binary)}:{os.environ['PATH']}",
            "MC_CONFIG_DIR": os.path.dirname(mc_config),
        }
        cls.workspace_dir = os.environ["BUILD_WORKING_DIRECTORY"]

        repository_cache = subprocess.check_output(
            ["bazel", "info", "repository_cache"],
            text=True,
            cwd=cls.workspace_dir,
        ).strip()
        cls.bazel_args = [
            f"--output_base={TEMP_OUTPUT_BASE}",
        ]
        cls.bazel_build_args = [
            f"--repository_cache={repository_cache}",
        ]

        execution_root = subprocess.check_output(
            ["bazel", *cls.bazel_args, "info", "execution_root"],
            text=True,
            cwd=cls.workspace_dir,
        ).strip()
        cls.output_dir = pathlib.Path(execution_root, "external")

    def test_minio(self) -> None:
        subtests = [
            (
                "@test_file//file",
                FILE_CONTENT,
                self.output_dir / "test_file" / "file" / "downloaded",
            ),
            (
                "@test_archive//:file.txt",
                FILE_CONTENT,
                self.output_dir / "test_archive" / "file.txt",
            ),
            (
                "@test_archive_p0_patch//:file.txt",
                PATCHED_CONTENT,
                self.output_dir / "test_archive_p0_patch" / "file.txt",
            ),
            (
                "@test_archive_p1_patch//:file.txt",
                PATCHED_CONTENT,
                self.output_dir / "test_archive_p1_patch" / "file.txt",
            ),
        ]
        with minio_server.run(port=MINIO_PORT) as proc:
            if not wait_for_port("127.0.0.1", MINIO_PORT):
                proc.kill()
                print("MinIO server failed to start")
                raise SystemExit(1)

            for target, expected_content, output_path in subtests:
                with self.subTest(target=target):
                    subprocess.check_call(
                        ["bazel", *self.bazel_args, "build", *self.bazel_build_args, target],
                        env=self.env,
                        cwd=self.workspace_dir,
                    )
                    assert expected_content in output_path.read_text()


if __name__ == "__main__":
    unittest.main()
