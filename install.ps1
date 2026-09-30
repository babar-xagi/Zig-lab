$ErrorActionPreference = "Stop"

$Repo = "git+https://github.com/babar-xagi/Zig-lab.git"
$Package = "zig-jupyter-kernel"

Write-Host ""
Write-Host "⚡ ZigLab Installer"
Write-Host "=================="
Write-Host ""

# --------------------------------------------------
# 1. Install uv if needed
# --------------------------------------------------

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "Installing uv..."

    Invoke-RestMethod `
        https://astral.sh/uv/install.ps1 |
        Invoke-Expression

    $env:Path = "$HOME\.local\bin;$env:Path"
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    $UvCandidate = Join-Path `
        $HOME `
        ".local\bin\uv.exe"

    if (Test-Path $UvCandidate) {
        $env:Path = `
            "$(Split-Path $UvCandidate);$env:Path"
    }
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv installation failed or uv is not on PATH."
}

Write-Host "✓ $(uv --version)"

# --------------------------------------------------
# 2. Install / upgrade ZigLab
# --------------------------------------------------

Write-Host ""
Write-Host "Installing ZigLab..."

uv tool install `
    --force `
    --from $Repo `
    $Package

# --------------------------------------------------
# 3. Make uv tool commands available
# --------------------------------------------------

$ToolBin = (uv tool dir --bin).Trim()

if ($ToolBin) {
    $env:Path = "$ToolBin;$env:Path"
}

try {
    uv tool update-shell | Out-Null
}
catch {
    Write-Host `
        "Note: reopen PowerShell if ziglab is not found later."
}

if (-not (Get-Command ziglab -ErrorAction SilentlyContinue)) {
    throw "ZigLab installed but ziglab command was not found."
}

# --------------------------------------------------
# 4. Register Jupyter kernel
# --------------------------------------------------

Write-Host ""
Write-Host "Registering ZigLab kernel..."

ziglab install

# --------------------------------------------------
# 5. Verify installation
# --------------------------------------------------

Write-Host ""
Write-Host "Running ZigLab Doctor..."
Write-Host ""

ziglab doctor

if ($LASTEXITCODE -ne 0) {
    throw "ZigLab Doctor reported a problem."
}

Write-Host ""
Write-Host "=================================="
Write-Host "⚡ ZigLab installation complete!"
Write-Host "=================================="
Write-Host ""
Write-Host "Start ZigLab with:"
Write-Host ""
Write-Host "    ziglab lab"
Write-Host ""
