import asyncio
import shutil
import tempfile
from pathlib import Path


class NativeRuntime:
    """
    Controls one long-lived Zig runtime process.

    The Zig process remains alive between commands, so native
    runtime state can survive across Jupyter cell executions.
    """

    def __init__(self) -> None:
        self.process: asyncio.subprocess.Process | None = None
        self._temp_dir: Path | None = None

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

        return self.process.pid

    async def start(self) -> str:
        if self.running:
            return (
                f"Native Zig runtime already running "
                f"(pid={self.pid})."
            )

        zig = shutil.which("zig")

        if zig is None:
            raise RuntimeError(
                "Zig compiler was not found in PATH."
            )

        runtime_source = (
            Path(__file__).with_name("runtime.zig")
        )

        if not runtime_source.exists():
            raise RuntimeError(
                f"Runtime source not found: {runtime_source}"
            )

        temp_dir = Path(
            tempfile.mkdtemp(
                prefix="zig-lab-runtime-"
            )
        )

        binary = temp_dir / "zig-lab-runtime"

        compile_process = (
            await asyncio.create_subprocess_exec(
                zig,
                "build-exe",
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

            stdout = stdout_bytes.decode(
                "utf-8",
                errors="replace",
            )

            stderr = stderr_bytes.decode(
                "utf-8",
                errors="replace",
            )

            raise RuntimeError(
                "Failed to compile native Zig runtime.\n"
                + stdout
                + stderr
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

        ready_bytes = await process.stdout.readline()

        ready = ready_bytes.decode(
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

        return (
            f"Native Zig runtime started "
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

        response_bytes = (
            await self.process.stdout.readline()
        )

        if not response_bytes:
            raise RuntimeError(
                "Native Zig runtime exited unexpectedly."
            )

        return response_bytes.decode(
            "utf-8",
            errors="replace",
        ).rstrip("\r\n")

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
            f"Native Zig runtime stopped "
            f"(pid={pid}, response={response})."
        )

    def _cleanup(self) -> None:
        if self._temp_dir is not None:
            shutil.rmtree(
                self._temp_dir,
                ignore_errors=True,
            )

        self._temp_dir = None
