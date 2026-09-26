from textwrap import indent


class ZigSession:
    """
    Stores Zig source declarations across Jupyter cells.

    This is source-level persistence.

    It does NOT yet preserve live runtime memory between executions.
    """

    def __init__(self) -> None:
        self._declarations: list[str] = []

    @property
    def declaration_count(self) -> int:
        return len(self._declarations)

    def add_declaration(self, code: str) -> None:
        self._declarations.append(code.strip())

    def remove_last_declaration(self) -> None:
        if self._declarations:
            self._declarations.pop()

    def reset(self) -> None:
        self._declarations.clear()

    def declarations_source(self) -> str:
        return "\n\n".join(self._declarations)

    def render_validation_program(self, candidate: str) -> str:
        parts = list(self._declarations)
        parts.append(candidate.strip())

        declarations = "\n\n".join(parts)

        return (
            declarations
            + "\n\n"
            + "pub fn main() void {}\n"
        )

    def render_run_program(self, body: str) -> str:
        declarations = self.declarations_source()

        main_function = (
            "pub fn main() !void {\n"
            + indent(body.strip(), "    ")
            + "\n}\n"
        )

        if declarations:
            return declarations + "\n\n" + main_function

        return main_function
