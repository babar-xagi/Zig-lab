from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Mapping


_IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_]*"

_IDENTIFIER_RE = re.compile(
    _IDENTIFIER
)


_DECLARATION_RE = re.compile(
    rf"""
    ^\s*
    var
    \s+
    (?P<name>{_IDENTIFIER})
    \s*:\s*
    (?P<type>i64|f64|bool)
    \s*=\s*
    (?P<value>.+?)
    \s*;
    \s*$
    """,
    re.VERBOSE | re.DOTALL,
)


_UPDATE_RE = re.compile(
    rf"""
    ^\s*
    (?P<name>{_IDENTIFIER})
    \s*
    (?P<operator>\+=)
    \s*
    (?P<value>.+?)
    \s*;
    \s*$
    """,
    re.VERBOSE | re.DOTALL,
)


_SIMPLE_TOKEN_RE = re.compile(
    rf"""
    \s*
    (
        (?:
            \d(?:_?\d)*
            (?:
                \.
                \d(?:_?\d)*
            )?
            (?:
                [eE]
                [+-]?
                \d(?:_?\d)*
            )?
        )
        |
        {_IDENTIFIER}
        |
        [()+\-*/%]
    )
    """,
    re.VERBOSE,
)


_SETTERS = {
    "i64": "setI64",
    "f64": "setF64",
    "bool": "setBool",
}


_GETTERS = {
    "i64": "getI64",
    "f64": "getF64",
    "bool": "getBool",
}


_NON_VARIABLE_IDENTIFIERS = {
    "true",
    "false",
}


_INSPECTION_RE = re.compile(
    rf"""
    ^\s*
    (?P<name>{_IDENTIFIER})
    \s*;?
    \s*$
    """,
    re.VERBOSE,
)


@dataclass(frozen=True)
class NaturalDeclaration:
    name: str
    type_name: str
    value_source: str


@dataclass(frozen=True)
class NaturalUpdate:
    name: str
    operator: str
    value_source: str


def parse_inspection(
    source: str,
) -> str | None:
    match = _INSPECTION_RE.fullmatch(
        source
    )

    if match is None:
        return None

    name = match.group("name")

    if name in _NON_VARIABLE_IDENTIFIERS:
        return None

    return name


def parse_declaration(
    source: str,
) -> NaturalDeclaration | None:
    match = _DECLARATION_RE.fullmatch(source)

    if match is None:
        return None

    return NaturalDeclaration(
        name=match.group("name"),
        type_name=match.group("type"),
        value_source=match.group("value").strip(),
    )


def parse_update(
    source: str,
) -> NaturalUpdate | None:
    match = _UPDATE_RE.fullmatch(source)

    if match is None:
        return None

    return NaturalUpdate(
        name=match.group("name"),
        operator=match.group("operator"),
        value_source=match.group("value").strip(),
    )


def validate_simple_expression(
    expression: str,
) -> None:
    position = 0

    while position < len(expression):
        match = _SIMPLE_TOKEN_RE.match(
            expression,
            position,
        )

        if match is None:
            remaining = expression[position:]

            if remaining.strip() == "":
                return

            raise ValueError(
                "Step 012D currently supports only "
                "persistent variable names, numeric "
                "literals, true/false, parentheses, "
                "and + - * / % operators."
            )

        position = match.end()


def expression_identifiers(
    expression: str,
) -> tuple[str, ...]:
    validate_simple_expression(expression)

    result: list[str] = []
    seen: set[str] = set()

    for match in _IDENTIFIER_RE.finditer(
        expression
    ):
        name = match.group(0)

        if name in _NON_VARIABLE_IDENTIFIERS:
            continue

        if name in seen:
            continue

        seen.add(name)
        result.append(name)

    return tuple(result)


def render_native_declaration(
    declaration: NaturalDeclaration,
) -> str:
    setter = _SETTERS[
        declaration.type_name
    ]

    return (
        f'_ = ziglab.{setter}(\n'
        f'    state,\n'
        f'    "{declaration.name}",\n'
        f'    {declaration.value_source},\n'
        f');'
    )


def _render_binding(
    name: str,
    type_name: str,
) -> str:
    getter = _GETTERS[type_name]

    return (
        f'const __ziglab_ref_{name} =\n'
        f'    ziglab.{getter}(\n'
        f'        state,\n'
        f'        "{name}",\n'
        f'    ) orelse return;'
    )


def _rewrite_expression(
    expression: str,
    replacements: Mapping[str, str],
) -> str:
    validate_simple_expression(expression)

    def replace_identifier(
        match: re.Match[str],
    ) -> str:
        name = match.group(0)

        return replacements.get(
            name,
            name,
        )

    return _IDENTIFIER_RE.sub(
        replace_identifier,
        expression,
    )


def render_native_declaration_with_bindings(
    declaration: NaturalDeclaration,
    bindings: Mapping[str, str],
) -> str:
    setter = _SETTERS[
        declaration.type_name
    ]

    references = expression_identifiers(
        declaration.value_source
    )

    prelude: list[str] = []
    replacements: dict[str, str] = {}

    for name in references:
        type_name = bindings.get(name)

        if type_name is None:
            raise ValueError(
                "Missing native type for "
                f"persistent variable '{name}'."
            )

        prelude.append(
            _render_binding(
                name,
                type_name,
            )
        )

        replacements[name] = (
            f"__ziglab_ref_{name}"
        )

    expression = _rewrite_expression(
        declaration.value_source,
        replacements,
    )

    setter_source = (
        f'_ = ziglab.{setter}(\n'
        f'    state,\n'
        f'    "{declaration.name}",\n'
        f'    {expression},\n'
        f');'
    )

    if not prelude:
        return setter_source

    return (
        "\n\n".join(prelude)
        + "\n\n"
        + setter_source
    )


def render_native_update(
    update: NaturalUpdate,
    type_name: str,
    bindings: Mapping[str, str] | None = None,
) -> str:
    if type_name not in ("i64", "f64"):
        raise ValueError(
            f"{update.operator} is not supported "
            f"for {type_name}."
        )

    if bindings is None:
        bindings = {}

    getter = _GETTERS[type_name]
    setter = _SETTERS[type_name]

    current_name = (
        f"__ziglab_current_{update.name}"
    )

    prelude = [
        (
            f'const {current_name} =\n'
            f'    ziglab.{getter}(\n'
            f'        state,\n'
            f'        "{update.name}",\n'
            f'    ) orelse return;'
        )
    ]

    replacements = {
        update.name: current_name
    }

    for name in expression_identifiers(
        update.value_source
    ):
        if name == update.name:
            continue

        ref_type = bindings.get(name)

        if ref_type is None:
            raise ValueError(
                "Missing native type for "
                f"persistent variable '{name}'."
            )

        prelude.append(
            _render_binding(
                name,
                ref_type,
            )
        )

        replacements[name] = (
            f"__ziglab_ref_{name}"
        )

    expression = _rewrite_expression(
        update.value_source,
        replacements,
    )

    update_source = (
        f'_ = ziglab.{setter}(\n'
        f'    state,\n'
        f'    "{update.name}",\n'
        f'    {current_name} + '
        f'({expression}),\n'
        f');'
    )

    return (
        "\n\n".join(prelude)
        + "\n\n"
        + update_source
    )


def transform_natural_source(
    source: str,
) -> str | None:
    declaration = parse_declaration(source)

    if declaration is None:
        return None

    references = expression_identifiers(
        declaration.value_source
    )

    if references:
        return None

    return render_native_declaration(
        declaration
    )
