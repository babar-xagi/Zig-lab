import asyncio
import shutil
import tempfile
from pathlib import Path
from textwrap import indent

from .toolchain import zig_command
from .native_platform import (
    dynamic_library_name,
    runtime_executable_name,
)


CELL_PRELUDE = """const ziglab = @import("abi.zig");
const State = ziglab.State;
"""


class NativeRuntime:
    def __init__(self) -> None:
        self.process: asyncio.subprocess.Process | None = None
        self._temp_dir: Path | None = None
        self._cell_index = 0
        self._declarations: list[str] = []

    @property
    def running(self) -> bool:
        return (
            self.process is not None
            and self.process.returncode is None
        )

    @property
    def pid(self) -> int | None:
        if not self.running:
            return None

        assert self.process is not None
        return self.process.pid

    @property
    def declaration_count(self) -> int:
        return len(self._declarations)

    def declarations_source(self) -> str:
        return "\n\n".join(self._declarations)

    def clear_declarations(self) -> None:
        self._declarations.clear()

    @property
    def _abi_source(self) -> Path:
        return Path(__file__).with_name("abi.zig")

    @property
    def _dynlib_source(self) -> Path:
        return Path(__file__).with_name("dynlib.zig")

    async def start(self) -> str:
        if self.running:
            return (
                "Native Zig runtime already running "
                f"(pid={self.pid})."
            )

        zig = zig_command()

        runtime_source = (
            Path(__file__).with_name("runtime.zig")
        )

        abi_source = self._abi_source

        if not runtime_source.exists():
            raise RuntimeError(
                f"Runtime source not found: {runtime_source}"
            )

        if not abi_source.exists():
            raise RuntimeError(
                f"ABI source not found: {abi_source}"
            )

        temp_dir = Path(
            tempfile.mkdtemp(
                prefix="zig-lab-runtime-"
            )
        )

        binary = (
            temp_dir
            / runtime_executable_name()
        )

        compile_process = (
            await asyncio.create_subprocess_exec(
                *zig,
                "build-exe",
                "-fllvm",
                str(runtime_source),
                f"-femit-bin={binary}",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        )

        stdout_bytes, stderr_bytes = (
            await compile_process.communicate()
        )

        if compile_process.returncode != 0:
            shutil.rmtree(
                temp_dir,
                ignore_errors=True,
            )

            raise RuntimeError(
                "Failed to compile native Zig runtime.\n"
                + stdout_bytes.decode(
                    "utf-8",
                    errors="replace",
                )
                + stderr_bytes.decode(
                    "utf-8",
                    errors="replace",
                )
            )

        # Dynamic notebook cells are compiled inside this directory.
        # They need their own local copy of abi.zig.
        shutil.copy2(
            abi_source,
            temp_dir / "abi.zig",
        )

        shutil.copy2(
            self._dynlib_source,
            temp_dir / "dynlib.zig",
        )

        process = await asyncio.create_subprocess_exec(
            str(binary),
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        if process.stdout is None:
            process.kill()

            raise RuntimeError(
                "Native runtime stdout pipe unavailable."
            )

        ready = (
            await process.stdout.readline()
        ).decode(
            "utf-8",
            errors="replace",
        ).strip()

        if ready != "READY":
            process.kill()
            await process.wait()

            shutil.rmtree(
                temp_dir,
                ignore_errors=True,
            )

            raise RuntimeError(
                "Native runtime failed to start. "
                f"Expected READY, received {ready!r}."
            )

        self.process = process
        self._temp_dir = temp_dir
        self._cell_index = 0

        return (
            "Native Zig runtime started "
            f"(pid={process.pid})."
        )

    async def command(
        self,
        command: str,
    ) -> str:
        if not self.running:
            raise RuntimeError(
                "Native Zig runtime is not running. "
                "Run //%native-start first."
            )

        assert self.process is not None

        if self.process.stdin is None:
            raise RuntimeError(
                "Native runtime stdin pipe unavailable."
            )

        if self.process.stdout is None:
            raise RuntimeError(
                "Native runtime stdout pipe unavailable."
            )

        self.process.stdin.write(
            (command + "\n").encode("utf-8")
        )

        await self.process.stdin.drain()

        response = (
            await self.process.stdout.readline()
        )

        if not response:
            stderr_text = ""

            if self.process.stderr is not None:
                stderr_bytes = (
                    await self.process.stderr.read()
                )

                stderr_text = stderr_bytes.decode(
                    "utf-8",
                    errors="replace",
                )

            returncode = await self.process.wait()

            message = (
                "Native Zig runtime exited unexpectedly "
                f"(code={returncode})."
            )

            if stderr_text:
                message += (
                    "\n\n--- Zig runtime stderr ---\n"
                    + stderr_text
                )

            raise RuntimeError(message)

        return response.decode(
            "utf-8",
            errors="replace",
        ).rstrip("\r\n")

    async def persist_declaration(
        self,
        source: str,
    ) -> str:
        candidate = source.strip()

        if not candidate:
            raise RuntimeError(
                "Native declaration cell is empty."
            )

        if "ziglab_cell" in candidate:
            raise RuntimeError(
                "The name 'ziglab_cell' is reserved."
            )

        zig = zig_command()

        declarations = [
            *self._declarations,
            candidate,
        ]

        validation_source = (
            CELL_PRELUDE
            + "\n"
            + "\n\n".join(declarations)
            + "\n\n"
            + "export fn ziglab_cell(state: *State) void {\n"
            + "    _ = state;\n"
            + "}\n"
        )

        with tempfile.TemporaryDirectory(
            prefix="zig-lab-declaration-"
        ) as temp_dir:

            temp_path = Path(temp_dir)

            shutil.copy2(
                self._abi_source,
                temp_path / "abi.zig",
            )

            source_file = (
                temp_path / "declaration.zig"
            )

            library_file = (
                temp_path
                / dynamic_library_name(
                    "ziglab-declaration"
                )
            )

            source_file.write_text(
                validation_source,
                encoding="utf-8",
            )

            process = (
                await asyncio.create_subprocess_exec(
                    *zig,
                    "build-lib",
                "-fllvm",
                    str(source_file),
                    "-dynamic",
                    f"-femit-bin={library_file}",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
            )

            stdout_bytes, stderr_bytes = (
                await process.communicate()
            )

        if process.returncode != 0:
            raise RuntimeError(
                "Native Zig declaration compilation failed.\n"
                + stdout_bytes.decode(
                    "utf-8",
                    errors="replace",
                )
                + stderr_bytes.decode(
                    "utf-8",
                    errors="replace",
                )
            )

        self._declarations.append(candidate)

        return (
            "Stored native Zig declaration cell "
            f"#{self.declaration_count}."
        )

    def _render_native_cell(
        self,
        body: str,
    ) -> str:
        parts = [
            CELL_PRELUDE,
        ]

        declarations = self.declarations_source()

        if declarations:
            parts.append(declarations)

        parts.append(
            "export fn ziglab_cell(state: *State) void {\n"
            + indent(body.strip(), "    ")
            + "\n}\n"
        )

        return "\n\n".join(parts)

    async def compile_and_run_cell(
        self,
        body: str,
    ) -> str:
        if not self.running:
            raise RuntimeError(
                "Native Zig runtime is not running. "
                "Run //%native-start first."
            )

        if not body.strip():
            raise RuntimeError(
                "Native cell is empty."
            )

        zig = zig_command()

        if self._temp_dir is None:
            raise RuntimeError(
                "Native runtime temporary directory "
                "is unavailable."
            )

        self._cell_index += 1

        source_file = (
            self._temp_dir
            / f"cell_{self._cell_index:04d}.zig"
        )

        library_file = (
            self._temp_dir
            / dynamic_library_name(
                (
                    "ziglab-cell-"
                    f"{self._cell_index:04d}"
                )
            )
        )

        source_file.write_text(
            self._render_native_cell(body),
            encoding="utf-8",
        )

        compile_process = (
            await asyncio.create_subprocess_exec(
                *zig,
                "build-lib",
                "-fllvm",
                str(source_file),
                "-dynamic",
                f"-femit-bin={library_file}",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        )

        stdout_bytes, stderr_bytes = (
            await compile_process.communicate()
        )

        if compile_process.returncode != 0:
            raise RuntimeError(
                "Native Zig cell compilation failed.\n"
                + stdout_bytes.decode(
                    "utf-8",
                    errors="replace",
                )
                + stderr_bytes.decode(
                    "utf-8",
                    errors="replace",
                )
            )

        return await self.command(
            f"load {library_file}"
        )

    async def stop(self) -> str:
        if not self.running:
            self._cleanup()

            return "Native Zig runtime is not running."

        assert self.process is not None

        try:
            response = await self.command("quit")
        except Exception:
            response = "Runtime stopped."

        try:
            await asyncio.wait_for(
                self.process.wait(),
                timeout=2.0,
            )
        except TimeoutError:
            self.process.kill()
            await self.process.wait()

        pid = self.process.pid

        self.process = None

        self._cleanup()

        return (
            "Native Zig runtime stopped "
            f"(pid={pid}, response={response})."
        )

    def _cleanup(self) -> None:
        if self._temp_dir is not None:
            shutil.rmtree(
                self._temp_dir,
                ignore_errors=True,
            )

        self._temp_dir = None
        self._cell_index = 0
