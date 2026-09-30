from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys


EXPECTED_ZIG_VERSION = "0.16.0"


def bundled_zig_available() -> bool:
    return importlib.util.find_spec("ziglang") is not None


def zig_command() -> list[str]:
    if bundled_zig_available():
        return [
            sys.executable,
            "-m",
            "ziglang",
        ]

    system_zig = shutil.which("zig")

    if system_zig is not None:
        return [system_zig]

    raise RuntimeError(
        "Zig compiler is unavailable. "
        "ZigLab's bundled Zig toolchain was not found "
        "and no system Zig exists."
    )


def zig_origin() -> str:
    if bundled_zig_available():
        return "bundled"

    if shutil.which("zig") is not None:
        return "system"

    return "missing"


def zig_version() -> str:
    process = subprocess.run(
        [
            *zig_command(),
            "version",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )

    if process.returncode != 0:
        raise RuntimeError(
            process.stderr.strip()
            or process.stdout.strip()
            or "Could not determine Zig version."
        )

    return process.stdout.strip()
