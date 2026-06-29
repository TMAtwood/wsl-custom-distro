# ============================================================================
# runner/host/00-create-host-distro.ps1
# ============================================================================
# Creates a dedicated, MINIMAL WSL2 distro named fcg-runner-host.
# This is NOT a clone of the 35 GB development image.  The host distro only
# needs Podman + glue; env parity lives in the runner *container* (FROM your
# image).  Keeping them separate protects your daily dev distro from runaway
# build cache and provides a clean service environment.
#
# DISK BUDGET: -VhdxPath must have >= 200 GB free.
#   35 GB image + 2-3x transient build cache + two retained versions
#   (current + previous, which share most layers) + general headroom.
#   Place it on a large data drive, NOT the OS drive (C:\).
#
# PREREQUISITES:
#   - Run as Administrator on Windows 11 with WSL2 enabled
#   - wsl.exe in PATH
#
# USAGE (from an elevated PowerShell prompt):
#   .\00-create-host-distro.ps1 -VhdxPath "D:\WSL\fcg-runner-host"
#
#   # Supply a pre-downloaded tarball to skip the download step:
#   .\00-create-host-distro.ps1 -VhdxPath "D:\WSL\fcg-runner-host" `
#       -BaseTarball "C:\Downloads\ubuntu-noble-wsl-amd64.tar.gz"
#
# AFTER THIS SCRIPT:
#   Run 10-bootstrap-host.sh inside the new distro to install Podman + deps.
# ============================================================================

param(
    [Parameter(Mandatory = $true,
        HelpMessage = "Directory on a large drive where the VHDX will be stored (>= 200 GB free).")]
    [string]$VhdxPath,

    [Parameter(Mandatory = $false,
        HelpMessage = "Path or HTTPS URL to a minimal Ubuntu rootfs tarball. " +
            "Defaults to Ubuntu 24.04 LTS (Noble) WSL image from cloud-images.ubuntu.com.")]
    [string]$BaseTarball = "https://cloud-images.ubuntu.com/wsl/noble/current/ubuntu-noble-wsl-amd64-ubuntu.tar.gz"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ─── Constants ───────────────────────────────────────────────────────────────
$DistroName = "fcg-runner-host"
$TaskName   = "FCG-Runner-HostStart"   # used by 30-autostart.ps1 too

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Write-Info    { param([string]$M); Write-Host "[INFO]    $M" -ForegroundColor Cyan }
function Write-Success { param([string]$M); Write-Host "[SUCCESS] $M" -ForegroundColor Green }
function Write-Warn    { param([string]$M); Write-Host "[WARN]    $M" -ForegroundColor Yellow }
function Write-Err     { param([string]$M); Write-Host "[ERROR]   $M" -ForegroundColor Red }

# ─── Guard: must be Administrator ────────────────────────────────────────────
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script must be run as Administrator."
    Write-Err "Right-click PowerShell -> 'Run as administrator', then retry."
    exit 1
}

# ─── Guard: wsl.exe available ────────────────────────────────────────────────
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Err "wsl.exe not found. Enable WSL2 first: 'wsl --install'"
    exit 1
}

# ─── Idempotency check ───────────────────────────────────────────────────────
Write-Info "Checking for existing distro '$DistroName'..."

# wsl --list --quiet outputs names (with possible NUL padding on older builds)
$existingNames = (wsl.exe --list --quiet 2>$null) -split "`n" |
    ForEach-Object { $_.Trim().TrimEnd([char]0) } |
    Where-Object { $_ -ne "" }

if ($existingNames -contains $DistroName) {
    Write-Warn "Distro '$DistroName' already exists — nothing to do."
    Write-Info ""
    Write-Info "To re-create from scratch:"
    Write-Info "  wsl --unregister $DistroName"
    Write-Info "  .\00-create-host-distro.ps1 -VhdxPath '$VhdxPath'"
    Write-Info ""
    Write-Info "To check the distro status:"
    Write-Info "  wsl --list --verbose"
    exit 0
}

# ─── Disk budget reminder ─────────────────────────────────────────────────────
Write-Host ""
Write-Warn "=================================================================="
Write-Warn " DISK BUDGET CHECK"
Write-Warn " Target: $VhdxPath"
Write-Warn " Required: >= 200 GB free"
Write-Warn "   35 GB build image  +  2-3x transient build cache"
Write-Warn "   +  two retained image versions  +  headroom"
Write-Warn " Verify free space before continuing."
Write-Warn "=================================================================="
Write-Host ""

# ─── Resolve / download the base tarball ─────────────────────────────────────
$tarballPath = $BaseTarball

if ($BaseTarball -match "^https?://") {
    $fileName    = [System.IO.Path]::GetFileName(([System.Uri]$BaseTarball).LocalPath)
    $tarballPath = Join-Path $env:TEMP $fileName

    if (Test-Path $tarballPath) {
        Write-Info "Tarball already cached at: $tarballPath  (delete to re-download)"
    } else {
        Write-Info "Downloading base tarball:"
        Write-Info "  From : $BaseTarball"
        Write-Info "  To   : $tarballPath"
        try {
            Invoke-WebRequest -Uri $BaseTarball -OutFile $tarballPath -UseBasicParsing
            Write-Success "Download complete."
        } catch {
            Write-Err "Download failed: $_"
            exit 1
        }
    }
} else {
    if (-not (Test-Path $tarballPath)) {
        Write-Err "Local tarball not found: $tarballPath"
        exit 1
    }
    Write-Info "Using local tarball: $tarballPath"
}

# ─── Create VHDX install directory ───────────────────────────────────────────
if (-not (Test-Path $VhdxPath)) {
    Write-Info "Creating VHDX directory: $VhdxPath"
    New-Item -ItemType Directory -Force -Path $VhdxPath | Out-Null
}

# ─── Import the distro ───────────────────────────────────────────────────────
Write-Info "Importing '$DistroName'..."
Write-Info "  Source  : $tarballPath"
Write-Info "  Install : $VhdxPath"

wsl.exe --import $DistroName $VhdxPath $tarballPath --version 2
if ($LASTEXITCODE -ne 0) {
    Write-Err "wsl --import failed (exit code $LASTEXITCODE)."
    exit 1
}

Write-Success "Distro '$DistroName' imported."

# ─── Enable sparse VHDX ──────────────────────────────────────────────────────
# Sparse VHDXs reclaim disk as the layer cache shrinks (prune.sh).
# Requires WSL >= 2.0.14; older builds silently ignore or error — safe to skip.
Write-Info "Enabling sparse VHDX (WSL 2.0.14+)..."
wsl.exe --manage $DistroName --set-sparse true 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Sparse VHDX not enabled — WSL version may be below 2.0.14.  Safe to ignore."
} else {
    Write-Success "Sparse VHDX enabled."
}

# ─── Write /etc/wsl.conf  — systemd=true is mandatory ───────────────────────
# Systemd brings up podman.socket and supervisor.service on distro start.
# default=root keeps the host distro straightforward for admin tasks;
# the supervisor runs as svc-runner via systemd, not as the WSL login user.
Write-Info "Writing /etc/wsl.conf (systemd=true)..."

$wslConfContent = "[boot]`nsystemd=true`n`n[user]`ndefault=root`n"
$wslConfContent | wsl.exe -d $DistroName -- tee /etc/wsl.conf | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to write /etc/wsl.conf inside '$DistroName'."
    exit 1
}

Write-Success "/etc/wsl.conf written."

# ─── Terminate so wsl.conf is re-read on next start ──────────────────────────
Write-Info "Terminating '$DistroName' to apply wsl.conf on next boot..."
wsl.exe --terminate $DistroName 2>$null
Start-Sleep -Seconds 2
Write-Success "Distro terminated; wsl.conf will be read on next start."

# ─── Done ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Success "=================================================================="
Write-Success " '$DistroName' created successfully."
Write-Success "  VHDX location : $VhdxPath"
Write-Success "=================================================================="
Write-Host ""
Write-Info "Next steps:"
Write-Info "  1. Copy the repo's runner/host/ scripts to a location accessible"
Write-Info "     inside the distro (e.g. a Windows path under /mnt/c/)."
Write-Info ""
Write-Info "  2. Run the bootstrap script INSIDE the distro as root:"
Write-Info "       wsl -d $DistroName -- bash /mnt/c/path/to/runner/host/10-bootstrap-host.sh"
Write-Info ""
Write-Info "  3. Place your fine-grained PAT in /etc/fcg-runner/pat (0600, svc-runner)."
Write-Info ""
Write-Info "  4. Register the autostart task (from an elevated prompt on Windows):"
Write-Info "       .\30-autostart.ps1"
Write-Host ""
