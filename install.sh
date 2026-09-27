#!/usr/bin/env bash

set -euo pipefail

REPO="git+https://github.com/babar-xagi/Zig-lab.git"
PACKAGE="zig-jupyter-kernel"
REQUIRED_ZIG="0.16.0"

echo
echo "⚡ ZigLab Installer"
echo "=================="
echo

# --------------------------------------------------
# 1. Make sure ~/.local/bin is available
# --------------------------------------------------

export PATH="$HOME/.local/bin:$PATH"

# --------------------------------------------------
# 2. Install uv if missing
# --------------------------------------------------

if ! command -v uv >/dev/null 2>&1; then
    echo "Installing uv..."

    if ! command -v curl >/dev/null 2>&1; then
        echo "ERROR: curl is required."
        exit 1
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh

    export PATH="$HOME/.local/bin:$PATH"
fi

echo "✓ uv: $(uv --version)"

# --------------------------------------------------
# 3. Check Zig
# --------------------------------------------------

if ! command -v zig >/dev/null 2>&1; then
    echo
    echo "Zig was not found."
    echo
    echo "For this installer version, install Zig"
    echo "$REQUIRED_ZIG first."
    echo
    echo "Automatic Zig installation is the next"
    echo "ZigLab deployment step."
    exit 1
fi

ZIG_VERSION="$(zig version)"

echo "✓ Zig: $ZIG_VERSION"

if [ "$ZIG_VERSION" != "$REQUIRED_ZIG" ]; then
    echo
    echo "WARNING:"
    echo "ZigLab is currently tested with Zig $REQUIRED_ZIG."
    echo "Detected Zig $ZIG_VERSION."
    echo
fi

# --------------------------------------------------
# 4. Install / upgrade ZigLab
# --------------------------------------------------

echo
echo "Installing ZigLab..."

uv tool install \
    --force \
    --from "$REPO" \
    "$PACKAGE"

export PATH="$HOME/.local/bin:$PATH"

# --------------------------------------------------
# 5. Install Jupyter kernelspec
# --------------------------------------------------

echo
echo "Registering ZigLab kernel..."

ziglab install

# --------------------------------------------------
# 6. Verify installation
# --------------------------------------------------

echo
echo "Running ZigLab Doctor..."
echo

ziglab doctor

echo
echo "=================================="
echo "⚡ ZigLab installation complete!"
echo "=================================="
echo
echo "Start with:"
echo
echo "    ziglab lab"
echo
