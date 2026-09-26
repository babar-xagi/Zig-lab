import asyncio
import shutil
import tempfile
from pathlib import Path

from ipykernel.kernelbase import Kernel


class ZigKernel(Kernel):
    implementation = "zig-jupyter-kernel"
    implementation_version = "0.1.0"

    language = "zig"
    language_version = "0.16.0"

    banner = "Zig Jupyter Kernel 0.1.0"

    language_info = {
        "name": "zig",
        "mimetype": "text/x-zig",
        "file_extension": ".zig",
    }

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
        # Empty cell: nothing to execute.
        if not code.strip():
            return {
                "status": "ok",
                "execution_count": self.execution_count,
                "payload": [],
                "user_expressions": {},
            }

        # Find the Zig compiler installed on the system.
        zig = shutil.which("zig")

        if zig is None:
            error_text = "Zig compiler was not found in PATH."

            if not silent:
                self.send_response(
                    self.iopub_socket,
                    "stream",
                    {
                        "name": "stderr",
                        "text": error_text + "\n",
                    },
                )

            return {
                "status": "error",
                "execution_count": self.execution_count,
                "ename": "ZigNotFound",
                "evalue": error_text,
                "traceback": [],
            }

        # Create a temporary directory for this notebook cell.
        with tempfile.TemporaryDirectory(
            prefix="zig-jupyter-"
        ) as temp_dir:

            source_file = Path(temp_dir) / "cell.zig"

            # Write the Jupyter cell into a real Zig source file.
            source_file.write_text(
                code,
                encoding="utf-8",
            )

            # Equivalent to:
            #
            #     zig run cell.zig
            #
            process = await asyncio.create_subprocess_exec(
                zig,
                "run",
                str(source_file),
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

        # Send normal program output to Jupyter.
        if not silent and stdout:
            self.send_response(
                self.iopub_socket,
                "stream",
                {
                    "name": "stdout",
                    "text": stdout,
                },
            )

        # Zig compiler errors and std.debug.print normally use stderr.
        if not silent and stderr:
            self.send_response(
                self.iopub_socket,
                "stream",
                {
                    "name": "stderr",
                    "text": stderr,
                },
            )

        # zig returned an error.
        if process.returncode != 0:
            return {
                "status": "error",
                "execution_count": self.execution_count,
                "ename": "ZigError",
                "evalue": f"zig exited with code {process.returncode}",
                "traceback": [],
            }

        return {
            "status": "ok",
            "execution_count": self.execution_count,
            "payload": [],
            "user_expressions": {},
        }
