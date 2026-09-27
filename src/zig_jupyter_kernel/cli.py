from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from importlib.metadata import PackageNotFoundError
from importlib.metadata import version
from pathlib import Path

from jupyter_client.kernelspec import KernelSpecManager


KERNEL_NAME = "ziglab"
DISPLAY_NAME = "ZigLab (Zig 0.16)"


def _package_version() -> str:
    try:
        return version("zig-jupyter-kernel")
    except PackageNotFoundError:
        return "development"


def _kernel_spec() -> dict:
    """
    Create a kernelspec tied to the exact Python
    environment where ZigLab is installed.

    This is more reliable than depending on
    `zig-jupyter-kernel` being on GUI application PATH.
    """

    return {
        "argv": [
            sys.executable,
            "-m",
            "zig_jupyter_kernel",
            "-f",
            "{connection_file}",
        ],
        "display_name": DISPLAY_NAME,
        "language": "zig",
        "interrupt_mode": "signal",
        "metadata": {
            "debugger": False,
        },
    }


def install_kernel() -> int:
    print("Installing ZigLab Jupyter kernel...")
    print()

    with tempfile.TemporaryDirectory(
        prefix="ziglab-kernelspec-"
    ) as temp_dir:
        spec_dir = Path(temp_dir)

        kernel_json = (
            spec_dir / "kernel.json"
        )

        kernel_json.write_text(
            json.dumps(
                _kernel_spec(),
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

        manager = KernelSpecManager()

        destination = (
            manager.install_kernel_spec(
                str(spec_dir),
                kernel_name=KERNEL_NAME,
                user=True,
                replace=True,
            )
        )

    print("✓ ZigLab kernel installed")
    print(f"  Name: {KERNEL_NAME}")
    print(f"  Display: {DISPLAY_NAME}")
    print(f"  Location: {destination}")
    print()
    print("You can now use ZigLab from:")
    print("  • JupyterLab")
    print("  • VS Code notebooks")
    print("  • PyCharm notebooks")
    print()
    print("Run:")
    print("  ziglab doctor")
    print()
    print("or:")
    print("  ziglab lab")

    return 0


def _check_llvm(
    zig: str,
) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(
        prefix="ziglab-doctor-"
    ) as temp_dir:
        source = (
            Path(temp_dir)
            / "doctor.zig"
        )

        source.write_text(
            "pub fn main() void {}\n",
            encoding="utf-8",
        )

        process = subprocess.run(
            [
                zig,
                "build-exe",
                str(source),
                "-fllvm",
                "-fno-emit-bin",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

    if process.returncode == 0:
        return True, "LLVM backend available"

    message = (
        process.stderr.strip()
        or process.stdout.strip()
        or "LLVM compile check failed"
    )

    return False, message


def doctor() -> int:
    print(
        f"ZigLab Doctor "
        f"{_package_version()}"
    )
    print("=" * 42)

    healthy = True

    print(
        f"✓ Python {sys.version.split()[0]}"
    )

    zig = shutil.which("zig")

    if zig is None:
        print("✗ Zig compiler not found")
        healthy = False
        zig_version = None
    else:
        process = subprocess.run(
            [
                zig,
                "version",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

        zig_version = (
            process.stdout.strip()
        )

        if process.returncode == 0:
            print(
                f"✓ Zig {zig_version}"
            )
            print(
                f"  {zig}"
            )
        else:
            print(
                "✗ Could not read Zig version"
            )
            healthy = False

    if zig is not None:
        llvm_ok, llvm_message = (
            _check_llvm(zig)
        )

        if llvm_ok:
            print(
                "✓ Zig LLVM backend"
            )
        else:
            print(
                "✗ Zig LLVM backend"
            )
            print(
                f"  {llvm_message}"
            )
            healthy = False

    try:
        import ipykernel  # noqa: F401

        print(
            "✓ ipykernel available"
        )
    except ImportError:
        print(
            "✗ ipykernel missing"
        )
        healthy = False

    try:
        import jupyterlab  # noqa: F401

        print(
            "✓ JupyterLab available"
        )
    except ImportError:
        print(
            "✗ JupyterLab missing"
        )
        healthy = False

    manager = KernelSpecManager()

    specs = manager.get_all_specs()

    if KERNEL_NAME in specs:
        print(
            "✓ ZigLab kernelspec installed"
        )

        resource_dir = specs[
            KERNEL_NAME
        ].get(
            "resource_dir",
            "",
        )

        if resource_dir:
            print(
                f"  {resource_dir}"
            )
    else:
        print(
            "✗ ZigLab kernelspec not installed"
        )
        print(
            "  Run: ziglab install"
        )
        healthy = False

    print()

    if healthy:
        print(
            "ZigLab is ready ✓"
        )
        return 0

    print(
        "ZigLab needs attention ✗"
    )

    return 1


def launch_lab() -> int:
    print("Starting JupyterLab...")
    print()

    process = subprocess.run(
        [
            sys.executable,
            "-m",
            "jupyterlab",
        ],
        check=False,
    )

    return process.returncode


def show_version() -> int:
    print(
        f"ZigLab {_package_version()}"
    )

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ziglab",
        description=(
            "ZigLab — native Zig notebooks "
            "for Jupyter."
        ),
    )

    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
    )

    subparsers.add_parser(
        "install",
        help=(
            "Install or update the "
            "ZigLab Jupyter kernel."
        ),
    )

    subparsers.add_parser(
        "doctor",
        help=(
            "Check the ZigLab installation."
        ),
    )

    subparsers.add_parser(
        "lab",
        help=(
            "Start JupyterLab."
        ),
    )

    subparsers.add_parser(
        "version",
        help=(
            "Show ZigLab version."
        ),
    )

    return parser


def main() -> int:
    parser = build_parser()

    args = parser.parse_args()

    if args.command == "install":
        return install_kernel()

    if args.command == "doctor":
        return doctor()

    if args.command == "lab":
        return launch_lab()

    if args.command == "version":
        return show_version()

    parser.error(
        f"Unknown command: {args.command}"
    )

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
