import asyncio
import shutil
import tempfile
from pathlib import Path

from ipykernel.kernelbase import Kernel

from .session import ZigSession
from .native_runtime import NativeRuntime
from .natural_syntax import (
    expression_identifiers,
    parse_declaration,
    parse_inspection,
    parse_update,
    render_native_declaration_with_bindings,
    render_native_update,
)


class ZigKernel(Kernel):
    implementation = "zig-jupyter-kernel"
    implementation_version = "0.7.0"

    language = "zig"
    language_version = "0.16.0"

    banner = "Zig Jupyter Kernel 0.7.0"

    language_info = {
        "name": "zig",
        "mimetype": "text/x-zig",
        "file_extension": ".zig",
    }

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # This object lives for as long as this kernel process lives.
        self.zig_session = ZigSession()
        self.native_runtime = NativeRuntime()

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

    async def _native_variable_type(
        self,
        name: str,
    ) -> str:
        response = (
            await self.native_runtime.command(
                f"var-get {name}"
            )
        )

        parts = response.split(
            maxsplit=3
        )

        if (
            len(parts) < 3
            or parts[0] != "VAR"
            or parts[1] != name
        ):
            raise RuntimeError(
                "Unexpected native variable "
                f"response: {response}"
            )

        native_type = parts[2]

        if native_type == "MISSING":
            raise RuntimeError(
                "Persistent variable "
                f"'{name}' does not exist."
            )

        type_map = {
            "I64": "i64",
            "F64": "f64",
            "BOOL": "bool",
        }

        type_name = type_map.get(
            native_type
        )

        if type_name is None:
            raise RuntimeError(
                "Unsupported native variable "
                f"type: {native_type}"
            )

        return type_name


    async def _resolve_bindings(
        self,
        names: tuple[str, ...],
        *,
        exclude: str | None = None,
    ) -> dict[str, str]:
        bindings: dict[str, str] = {}

        for name in names:
            if name == exclude:
                continue

            bindings[name] = (
                await self._native_variable_type(
                    name
                )
            )

        return bindings


    async def _run_natural_source(
        self,
        source: str,
        silent: bool,
    ):
        declaration = parse_declaration(
            source
        )

        update = None
        inspection = None

        if declaration is None:
            update = parse_update(source)

            if update is None:
                inspection = parse_inspection(
                    source
                )

                if inspection is None:
                    return None

        try:
            if not self.native_runtime.running:
                await self.native_runtime.start()

            if inspection is not None:
                response = (
                    await self.native_runtime.command(
                        f"var-get {inspection}"
                    )
                )

                parts = response.split(
                    maxsplit=3
                )

                if (
                    len(parts) < 3
                    or parts[0] != "VAR"
                    or parts[1] != inspection
                ):
                    raise RuntimeError(
                        "Unexpected native variable "
                        f"response: {response}"
                    )

                if parts[2] == "MISSING":
                    raise RuntimeError(
                        "Persistent variable "
                        f"'{inspection}' does "
                        "not exist."
                    )

                if len(parts) < 4:
                    raise RuntimeError(
                        "Native variable value "
                        "was missing."
                    )

                value = parts[3]

                if not silent:
                    self._send_stream(
                        "stdout",
                        value + "\n",
                    )

                return self._ok()

            if declaration is not None:
                references = (
                    expression_identifiers(
                        declaration.value_source
                    )
                )

                bindings = (
                    await self._resolve_bindings(
                        references
                    )
                )

                transformed = (
                    render_native_declaration_with_bindings(
                        declaration,
                        bindings,
                    )
                )

            else:
                update_type = (
                    await self._native_variable_type(
                        update.name
                    )
                )

                references = (
                    expression_identifiers(
                        update.value_source
                    )
                )

                bindings = (
                    await self._resolve_bindings(
                        references,
                        exclude=update.name,
                    )
                )

                transformed = (
                    render_native_update(
                        update,
                        update_type,
                        bindings,
                    )
                )

            await (
                self.native_runtime
                .compile_and_run_cell(
                    transformed
                )
            )

        except (RuntimeError, ValueError) as exc:
            message = str(exc)

            if not silent:
                self._send_stream(
                    "stderr",
                    message + "\n",
                )

            return self._error(
                "NaturalZigError",
                message,
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

        natural_result = (
            await self._run_natural_source(
                stripped,
                silent,
            )
        )

        if natural_result is not None:
            return natural_result

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

        if command == "//%native-start":
            try:
                message = await self.native_runtime.start()
            except RuntimeError as exc:
                message = str(exc)

                if not silent:
                    self._send_stream(
                        "stderr",
                        message + "\n",
                    )

                return self._error(
                    "NativeRuntimeError",
                    message,
                )

            if not silent:
                self._send_stream(
                    "stdout",
                    message + "\n",
                )

            return self._ok()

        if command == "//%native-status":
            if self.native_runtime.running:
                message = (
                    "Native Zig runtime running "
                    f"(pid={self.native_runtime.pid})."
                )
            else:
                message = (
                    "Native Zig runtime is not running."
                )

            if not silent:
                self._send_stream(
                    "stdout",
                    message + "\n",
                )

            return self._ok()

        if command == "//%native-persist":
            try:
                message = (
                    await self.native_runtime.persist_declaration(
                        body
                    )
                )
            except RuntimeError as exc:
                message = str(exc)

                if not silent:
                    self._send_stream(
                        "stderr",
                        message + "\n",
                    )

                return self._error(
                    "NativePersistError",
                    message,
                )

            if not silent:
                self._send_stream(
                    "stdout",
                    message + "\n",
                )

            return self._ok()

        if command == "//%native-show":
            source = (
                self.native_runtime.declarations_source()
            )

            if source:
                message = source
            else:
                message = (
                    "No native Zig declarations stored."
                )

            if not silent:
                self._send_stream(
                    "stdout",
                    message + "\n",
                )

            return self._ok()

        if command == "//%native-clear":
            count = (
                self.native_runtime.declaration_count
            )

            self.native_runtime.clear_declarations()

            message = (
                f"Cleared {count} native Zig "
                "declaration cell(s)."
            )

            if not silent:
                self._send_stream(
                    "stdout",
                    message + "\n",
                )

            return self._ok()

        if command == "//%native-cell":
            try:
                response = (
                    await self.native_runtime.compile_and_run_cell(
                        body
                    )
                )
            except RuntimeError as exc:
                message = str(exc)

                if not silent:
                    self._send_stream(
                        "stderr",
                        message + "\n",
                    )

                return self._error(
                    "NativeCellError",
                    message,
                )

            if not silent:
                self._send_stream(
                    "stdout",
                    response + "\n",
                )

            return self._ok()

        if command.startswith("//%native-var "):
            name = command[
                len("//%native-var "):
            ].strip()

            if not name:
                message = "Variable name is required."

                if not silent:
                    self._send_stream(
                        "stderr",
                        message + "\n",
                    )

                return self._error(
                    "NativeVariableError",
                    message,
                )

            try:
                response = await self.native_runtime.command(
                    f"var-get {name}"
                )
            except RuntimeError as exc:
                message = str(exc)

                if not silent:
                    self._send_stream(
                        "stderr",
                        message + "\n",
                    )

                return self._error(
                    "NativeVariableError",
                    message,
                )

            if not silent:
                self._send_stream(
                    "stdout",
                    response + "\n",
                )

            return self._ok()

        native_commands = {
            "//%native-ping": "ping",
            "//%native-inc": "inc",
            "//%native-get": "get",
            "//%native-reset": "reset",
            "//%native-vars": "vars",
        }

        if command in native_commands:
            try:
                response = await self.native_runtime.command(
                    native_commands[command]
                )
            except RuntimeError as exc:
                message = str(exc)

                if not silent:
                    self._send_stream(
                        "stderr",
                        message + "\n",
                    )

                return self._error(
                    "NativeRuntimeError",
                    message,
                )

            if not silent:
                self._send_stream(
                    "stdout",
                    response + "\n",
                )

            return self._ok()

        if command == "//%native-stop":
            message = await self.native_runtime.stop()

            if not silent:
                self._send_stream(
                    "stdout",
                    message + "\n",
                )

            return self._ok()

        # No notebook command:
        # preserve the old standalone-cell behavior.
        return await self._run_standalone(
            code,
            silent,
        )
