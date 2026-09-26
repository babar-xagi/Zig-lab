# Zig Lab ⚡

An experimental Jupyter kernel for Zig.

## Current Status

Zig Lab can currently:

- Register Zig as a Jupyter kernel
- Receive Zig code from JupyterLab cells
- Create a temporary `.zig` source file for each cell
- Compile and execute the cell using `zig run`
- Capture stdout and stderr
- Display Zig compiler errors directly in Jupyter

## Architecture

JupyterLab sends the contents of a notebook cell to the custom Python kernel.

The current execution flow is:

    JupyterLab
        |
        v
    Zig Jupyter Kernel
        |
        v
    Temporary cell.zig
        |
        v
    zig run
        |
        v
    stdout / stderr
        |
        v
    JupyterLab

## Current Limitation

Each cell is currently compiled and executed as an independent Zig program.

State is not yet preserved between cells.

Persistent native Zig notebook state is a future goal.

## Development Environment

Currently tested with:

- Zig 0.16.0
- Python 3.14
- JupyterLab 4
- uv
- Linux / WSL2

## Project Status

Experimental and under active development.
