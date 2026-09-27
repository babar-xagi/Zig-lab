from __future__ import annotations

from dataclasses import dataclass
import re


_IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_]*"


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


def render_native_declaration(
    declaration: NaturalDeclaration,
) -> str:
    setter = _SETTERS[declaration.type_name]

    return (
        f'_ = ziglab.{setter}(\n'
        f'    state,\n'
        f'    "{declaration.name}",\n'
        f'    {declaration.value_source},\n'
        f');'
    )


def render_native_update(
    update: NaturalUpdate,
    type_name: str,
) -> str:
    if type_name not in ("i64", "f64"):
        raise ValueError(
            f"{update.operator} is not supported "
            f"for {type_name}."
        )

    getter = _GETTERS[type_name]
    setter = _SETTERS[type_name]

    local_name = (
        f"__ziglab_current_{update.name}"
    )

    return (
        f'const {local_name} =\n'
        f'    ziglab.{getter}(\n'
        f'        state,\n'
        f'        "{update.name}",\n'
        f'    ) orelse return;\n'
        f'\n'
        f'_ = ziglab.{setter}(\n'
        f'    state,\n'
        f'    "{update.name}",\n'
        f'    {local_name} + '
        f'({update.value_source}),\n'
        f');'
    )


def transform_natural_source(
    source: str,
) -> str | None:
    declaration = parse_declaration(source)

    if declaration is None:
        return None

    return render_native_declaration(
        declaration
    )
