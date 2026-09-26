import asyncio
import shutil
import tempfile
from pathlib import Path

from ipykernel.kernelbase import Kernel

from .session import ZigSession


class ZigKernel(Kernel):
    implementation = "zig-jupyter-kernel"
    implementation_version = "0.2.0"

    language = "zig"
    language_version = "0.16.0"

    banner = "Zig Jupyter Kernel 0.2.0"

    language_info = {
        "name": "zig",
        "mimetype": "text/x-zig",
        "file_extension": ".zig",
    }

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # This object lives for as long as this kernel process lives.
        self.zig_session = ZigSession()

    def _send_stream(self, name: str, text: str) -> None:
        self.send_response(
            self.iopub_socket,
            "stream",
            {
                "name": name,
                "text": text,
            },
        )

    def _ok(self) -> dict:
        return {
            "status": "ok",
            "execution_count": self.execution_count,
            "payload": [],
            "user_expressions": {},
        }

    def _error(self, name: str, message: str) -> dict:
        return {
            "status": "error",
            "execution_count": self.execution_count,
            "ename": name,
            "evalue": message,
            "traceback": [],
        }

    async def _run_zig(
        self,
        source: str,
        *,
        execute: bool,
    ):
        zig = shutil.which("zig")

        if zig is None:
            return None, "", "Zig compiler was not found in PATH."

        with tempfile.TemporaryDirectory(
            prefix="zig-jupyter-"
        ) as temp_dir:

            source_file = Path(temp_dir) / "cell.zig"

            source_file.write_text(
                source,
                encoding="utf-8",
            )

            if execute:
                command = [
                    zig,
                    "run",
                    str(source_file),
                ]
            else:
                command = [
                    zig,
                    "build-exe",
                    str(source_file),
                    "-fno-emit-bin",
                ]

            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            stdout_bytes, stderr_bytes = await process.communicate()

        stdout = stdout_bytes.decode(
            "utf-8",
            errors="replace",
        )

        stderr = stderr_bytes.decode(
            "utf-8",
            errors="replace",
        )

        return process.returncode, stdout, stderr

    async def _persist(
        self,
        source: str,
        silent: bool,
    ):
        if not source.strip():
            message = "Nothing to persist."

            if not silent:
                self._send_stream("stderr", message + "\n")

            return self._error(
                "ZigPersistError",
                message,
            )

        # A persistent cell should contain top-level declarations,
        # not its own main function.
        if "pub fn main" in source:
            message = (
                "//%persist cells should contain top-level "
                "declarations, not pub fn main()."
            )

            if not silent:
                self._send_stream("stderr", message + "\n")

            return self._error(
                "ZigPersistError",
                message,
            )

        validation_source = (
            self.zig_session.render_validation_program(source)
        )

        returncode, stdout, stderr = await self._run_zig(
            validation_source,
            execute=False,
        )

        if returncode is None:
            if not silent:
                self._send_stream("stderr", stderr + "\n")

            return self._error(
                "ZigNotFound",
                stderr,
            )

        if stdout and not silent:
            self._send_stream("stdout", stdout)

        if stderr and not silent:
            self._send_stream("stderr", stderr)

        if returncode != 0:
            return self._error(
                "ZigCompileError",
                "Persistent declaration was not stored.",
            )

        self.zig_session.add_declaration(source)

        if not silent:
            self._send_stream(
                "stdout",
                (
                    "Stored persistent Zig declaration cell "
                    f"#{self.zig_session.declaration_count}.\n"
                ),
            )

        return self._ok()

    async def _run_persistent(
        self,
        body: str,
        silent: bool,
    ):
        source = self.zig_session.render_run_program(body)

        returncode, stdout, stderr = await self._run_zig(
            source,
            execute=True,
        )

        if returncode is None:
            if not silent:
                self._send_stream("stderr", stderr + "\n")

            return self._error(
                "ZigNotFound",
                stderr,
            )

        if stdout and not silent:
            self._send_stream("stdout", stdout)

        if stderr and not silent:
            self._send_stream("stderr", stderr)

        if returncode != 0:
            return self._error(
                "ZigError",
                f"zig exited with code {returncode}",
            )

        return self._ok()

    async def _run_standalone(
        self,
        code: str,
        silent: bool,
    ):
        returncode, stdout, stderr = await self._run_zig(
            code,
            execute=True,
        )

        if returncode is None:
            if not silent:
                self._send_stream("stderr", stderr + "\n")

            return self._error(
                "ZigNotFound",
                stderr,
            )

        if stdout and not silent:
            self._send_stream("stdout", stdout)

        if stderr and not silent:
            self._send_stream("stderr", stderr)

        if returncode != 0:
            return self._error(
                "ZigError",
                f"zig exited with code {returncode}",
            )

        return self._ok()

    async def do_execute(
        self,
        code,
        silent,
        store_history=True,
        user_expressions=None,
        allow_stdin=False,
        *,
        cell_meta=None,
        cell_id=None,
    ):
        stripped = code.strip()

        if not stripped:
            return self._ok()

        lines = stripped.splitlines()

        command = lines[0].strip()

        body = "\n".join(lines[1:])

        if command == "//%persist":
            return await self._persist(
                body,
                silent,
            )

        if command == "//%run":
            return await self._run_persistent(
                body,
                silent,
            )

        if command == "//%reset":
            self.zig_session.reset()

            if not silent:
                self._send_stream(
                    "stdout",
                    "Persistent Zig session reset.\n",
                )

            return self._ok()

        if command == "//%show":
            source = self.zig_session.declarations_source()

            if not silent:
                if source:
                    self._send_stream(
                        "stdout",
                        source + "\n",
                    )
                else:
                    self._send_stream(
                        "stdout",
                        "No persistent declarations stored.\n",
                    )

            return self._ok()

        # No notebook command:
        # preserve the old standalone-cell behavior.
        return await self._run_standalone(
            code,
            silent,
        )
