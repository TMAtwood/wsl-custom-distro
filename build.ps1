# ============================================================================
# Build Script for WSL Ubuntu 26.04 Development Environment
# ============================================================================
# This script builds the Docker/Podman image with proper error handling
# and version management using GitVersion for semantic versioning.
# ============================================================================

# Enable strict error handling
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Define colors for output
$ColorSuccess = "Green"
$ColorError = "Red"
$ColorWarning = "Yellow"
$ColorInfo = "Cyan"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "[SUCCESS] $Message" $ColorSuccess
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" $ColorError
}

function Write-InfoMsg {
    param([string]$Message)
    Write-ColorOutput "[INFO] $Message" $ColorInfo
}

function Write-WarningMsg {
    param([string]$Message)
    Write-ColorOutput "[WARNING] $Message" $ColorWarning
}

# ============================================================================
# Version Detection
# ============================================================================

function Get-BuildVersion {
    try {
        Write-InfoMsg "Determining version using GitVersion..."

        # Check if gitversion is available
        $gitVersionExists = Get-Command gitversion -ErrorAction SilentlyContinue
        if (-not $gitVersionExists) {
            Write-WarningMsg "GitVersion not found, using default version"
            return "0.0.0-dev"
        }

        # Get version from gitversion
        $gitVersionOutput = gitversion 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-WarningMsg "GitVersion failed with exit code $LASTEXITCODE, using default version"
            return "0.0.0-dev"
        }

        $versionData = $gitVersionOutput | ConvertFrom-Json
        if (-not $versionData.SemVer) {
            throw "GitVersion output does not contain SemVer field"
        }

        $version = $versionData.SemVer
        Write-Success "Version determined: $version"
        return $version

    } catch {
        Write-WarningMsg "Error determining version: $_"
        Write-WarningMsg "Falling back to default version: 0.0.0-dev"
        return "0.0.0-dev"
    }
}

# ============================================================================
# Main Build Process
# ============================================================================

try {
    Write-ColorOutput "`n========================================" $ColorInfo
    Write-ColorOutput "  WSL Ubuntu 26.04 Image Build" $ColorInfo
    Write-ColorOutput "========================================`n" $ColorInfo

    # Get version
    $VERSION = Get-BuildVersion
    $env:VERSION = $VERSION

    # Get build date
    $BUILD_DATE = Get-Date -Format "yyyy-MM-dd"
    $env:BUILD_DATE = $BUILD_DATE
    Write-InfoMsg "Build date: $BUILD_DATE"

    # Define image names
    $IMAGE_NAME = "localhost/tmatwood/ubuntu-26.04"
    $IMAGE_NAME_AND_VERSION = "${IMAGE_NAME}:${VERSION}"
    $IMAGE_NAME_LATEST = "${IMAGE_NAME}:latest"

    Write-InfoMsg "Image name: $IMAGE_NAME"
    Write-InfoMsg "Version tag: $IMAGE_NAME_AND_VERSION"
    Write-InfoMsg "Latest tag: $IMAGE_NAME_LATEST"

    # ========================================================================
    # Check Podman availability
    # ========================================================================
    Write-InfoMsg "`nChecking Podman availability..."

    $podmanExists = Get-Command podman -ErrorAction SilentlyContinue
    if (-not $podmanExists) {
        throw "Podman is not installed or not in PATH"
    }
    Write-Success "Podman found"

    # ========================================================================
    # Start Podman machine (if needed)
    # ========================================================================
    Write-InfoMsg "`nStarting Podman machine..."

    try {
        $machineStatus = podman machine start 2>&1
        if ($LASTEXITCODE -eq 0 -or $machineStatus -like "*already running*") {
            Write-Success "Podman machine is running"
        } else {
            Write-WarningMsg "Podman machine start returned: $machineStatus"
        }
    } catch {
        Write-WarningMsg "Podman machine start encountered an issue: $_"
        Write-InfoMsg "Continuing with build..."
    }

    # ========================================================================
    # Build the image
    # ========================================================================
    Write-InfoMsg "`nBuilding Docker image..."
    Write-ColorOutput "This may take 15-30 minutes depending on your system..." $ColorWarning

    $buildStartTime = Get-Date

    podman build `
        --format docker `
        --dns=1.1.1.1 `
        --dns=8.8.8.8 `
        --platform linux/amd64 `
        --build-arg BUILD_DATE="$BUILD_DATE" `
        -t $IMAGE_NAME_AND_VERSION `
        .

    if ($LASTEXITCODE -ne 0) {
        throw "Podman build failed with exit code $LASTEXITCODE"
    }

    $buildDuration = (Get-Date) - $buildStartTime
    Write-Success ("Image built successfully in {0:F2} minutes" -f $buildDuration.TotalMinutes)

    # ========================================================================
    # Tag the image as latest
    # ========================================================================
    Write-InfoMsg "`nTagging image as latest..."

    podman tag $IMAGE_NAME_AND_VERSION $IMAGE_NAME_LATEST

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to tag image as latest (exit code $LASTEXITCODE)"
    }

    Write-Success "Image tagged as latest"

    # ========================================================================
    # Build Summary
    # ========================================================================
    Write-ColorOutput "`n========================================" $ColorSuccess
    Write-ColorOutput "  Build Completed Successfully!" $ColorSuccess
    Write-ColorOutput "========================================" $ColorSuccess
    Write-ColorOutput "  Version: $VERSION" $ColorInfo
    Write-ColorOutput "  Build Date: $BUILD_DATE" $ColorInfo
    Write-ColorOutput "  Image: $IMAGE_NAME_AND_VERSION" $ColorInfo
    Write-ColorOutput "  Latest: $IMAGE_NAME_LATEST" $ColorInfo
    Write-ColorOutput ("  Duration: {0:F2} minutes" -f $buildDuration.TotalMinutes) $ColorInfo
    Write-ColorOutput "========================================`n" $ColorSuccess

    # ========================================================================
    # Show image info
    # ========================================================================
    Write-InfoMsg "Image information:"
    podman images $IMAGE_NAME

    exit 0

} catch {
    Write-ColorOutput "`n========================================" $ColorError
    Write-ColorOutput "  Build Failed!" $ColorError
    Write-ColorOutput "========================================" $ColorError
    Write-ErrorMsg "Error: $_"
    Write-ColorOutput "========================================`n" $ColorError

    # Show troubleshooting tips
    Write-WarningMsg "Troubleshooting tips:"
    Write-Host "  1. Ensure Podman is installed and running" -ForegroundColor Yellow
    Write-Host "  2. Check if Podman machine is started: podman machine list" -ForegroundColor Yellow
    Write-Host "  3. Verify GitVersion is installed: gitversion --version" -ForegroundColor Yellow
    Write-Host "  4. Check available disk space" -ForegroundColor Yellow
    Write-Host "  5. Review build logs above for specific errors`n" -ForegroundColor Yellow

    exit 1
}
