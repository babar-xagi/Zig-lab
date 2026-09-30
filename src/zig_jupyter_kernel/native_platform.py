from __future__ import annotations

from dataclasses import dataclass
import platform


@dataclass(frozen=True)
class NativePlatform:
    name: str
    executable_suffix: str
    dynamic_library_suffix: str


def native_platform(
    system_name: str | None = None,
) -> NativePlatform:
    system = (
        system_name
        if system_name is not None
        else platform.system()
    )

    normalized = system.lower()

    if normalized == "linux":
        return NativePlatform(
            name="linux",
            executable_suffix="",
            dynamic_library_suffix=".so",
        )

    if normalized == "darwin":
        return NativePlatform(
            name="macos",
            executable_suffix="",
            dynamic_library_suffix=".dylib",
        )

    if normalized == "windows":
        return NativePlatform(
            name="windows",
            executable_suffix=".exe",
            dynamic_library_suffix=".dll",
        )

    raise RuntimeError(
        f"Unsupported operating system: {system}"
    )


def runtime_executable_name(
    system_name: str | None = None,
) -> str:
    target = native_platform(
        system_name
    )

    return (
        "ziglab-runtime"
        + target.executable_suffix
    )


def dynamic_library_name(
    base_name: str,
    system_name: str | None = None,
) -> str:
    target = native_platform(
        system_name
    )

    return (
        base_name
        + target.dynamic_library_suffix
    )
