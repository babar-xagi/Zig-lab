#!/usr/bin/env bash

set -euo pipefail

REPO="git+https://github.com/babar-xagi/Zig-lab.git"
PACKAGE="zig-jupyter-kernel"

echo
echo "⚡ ZigLab Installer"
echo "=================="
echo

export PATH="$HOME/.local/bin:$PATH"

# --------------------------------------------------
# 1. Install uv if needed
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

echo "✓ $(uv --version)"

# --------------------------------------------------
# 2. Install / upgrade ZigLab
# --------------------------------------------------

echo
echo "Installing ZigLab..."

uv tool install \
    --force \
    --from "$REPO" \
    "$PACKAGE"

export PATH="$HOME/.local/bin:$PATH"

# --------------------------------------------------
# 3. Register ZigLab Jupyter kernel
# --------------------------------------------------

echo
echo "Registering ZigLab kernel..."

ziglab install

# --------------------------------------------------
# 4. Verify everything
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
echo "Start ZigLab with:"
echo
echo "    ziglab lab"
echo
