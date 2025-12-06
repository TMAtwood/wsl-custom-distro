#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Install Container Structure Test on Windows

.DESCRIPTION
    This script downloads and installs container-structure-test for Windows.
    It creates a directory structure at C:\tools\container-structure-test,
    downloads the latest release, and configures system environment variables.

    IMPORTANT: This script must be run as Administrator to:
    - Create directories in C:\tools
    - Set system-level environment variables
    - Modify the system PATH

.EXAMPLE
    .\install-container-structure-test.ps1

.NOTES
    Author: Tom Atwood
    Requires: PowerShell 5.1 or later, Administrator privileges
#>

[CmdletBinding()]
param()

# Check if running as Administrator
# This is redundant due to #Requires -RunAsAdministrator but provides a friendly error message
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please right-click PowerShell and select 'Run as Administrator', then run this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Container Structure Test Installation Script" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Define installation paths
$toolsDir = "C:\tools"
$cstDir = "C:\tools\container-structure-test"
$cstExe = "$cstDir\container-structure-test.exe"
$downloadUrl = "https://github.com/GoogleContainerTools/container-structure-test/releases/latest/download/container-structure-test-windows-amd64.exe"

# Step 1: Create the C:\tools directory if it doesn't exist
Write-Host "Step 1: Creating directory structure..." -ForegroundColor Green
if (-not (Test-Path $toolsDir)) {
    Write-Host "  Creating $toolsDir"
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
} else {
    Write-Host "  $toolsDir already exists"
}

# Step 2: Create the container-structure-test subdirectory
Write-Host "  Creating $cstDir"
if (-not (Test-Path $cstDir)) {
    New-Item -ItemType Directory -Path $cstDir -Force | Out-Null
} else {
    Write-Host "  $cstDir already exists"
}
Write-Host ""

# Step 3: Download container-structure-test executable (only if not already present)
Write-Host "Step 2: Checking for existing installation..." -ForegroundColor Green

# Check if executable already exists
if (Test-Path $cstExe) {
    Write-Host "  [INFO] Executable already exists: $cstExe" -ForegroundColor Yellow

    # Try to get version to verify it's working
    try {
        $existingVersion = & $cstExe version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $fileSize = (Get-Item $cstExe).Length / 1MB
            Write-Host "  [OK] Existing installation is working" -ForegroundColor Green
            Write-Host "  File size: $([math]::Round($fileSize, 2)) MB"
            Write-Host "  Current version: $existingVersion" -ForegroundColor Cyan
            Write-Host "  [INFO] Skipping download" -ForegroundColor Yellow
            $skipDownload = $true
        } else {
            Write-Host "  [WARNING] Existing file found but not working properly" -ForegroundColor Yellow
            Write-Host "  [INFO] Will re-download" -ForegroundColor Yellow
            $skipDownload = $false
        }
    } catch {
        Write-Host "  [WARNING] Existing file found but cannot verify version" -ForegroundColor Yellow
        Write-Host "  [INFO] Will re-download" -ForegroundColor Yellow
        $skipDownload = $false
    }
} else {
    Write-Host "  [INFO] No existing installation found" -ForegroundColor Yellow
    $skipDownload = $false
}

# Download if needed
if (-not $skipDownload) {
    Write-Host ""
    Write-Host "  Downloading container-structure-test..." -ForegroundColor Green
    Write-Host "  URL: $downloadUrl"
    Write-Host "  Destination: $cstExe"

    try {
        # Use TLS 1.2 for secure downloads
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Download the file with progress
        $ProgressPreference = 'SilentlyContinue'  # Speed up download
        Invoke-WebRequest -Uri $downloadUrl -OutFile $cstExe -UseBasicParsing
        $ProgressPreference = 'Continue'

        Write-Host "  [OK] Download completed successfully" -ForegroundColor Green

        # Verify the downloaded file
        if (Test-Path $cstExe) {
            $fileSize = (Get-Item $cstExe).Length / 1MB
            Write-Host "  [OK] File verified: $cstExe" -ForegroundColor Green
            Write-Host "  File size: $([math]::Round($fileSize, 2)) MB"
        } else {
            Write-Host "  [ERROR] Downloaded file not found!" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "  [ERROR] Failed to download container-structure-test" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# Step 5: Set CST_HOME environment variable (System-level) - only if not already set or different
Write-Host "Step 3: Configuring environment variables..." -ForegroundColor Green

# Check current CST_HOME value
$currentCstHome = [System.Environment]::GetEnvironmentVariable("CST_HOME", [System.EnvironmentVariableTarget]::Machine)

if ($currentCstHome -eq $cstDir) {
    Write-Host "  [INFO] CST_HOME is already set correctly to: $cstDir" -ForegroundColor Yellow
    Write-Host "  [INFO] Skipping CST_HOME configuration" -ForegroundColor Yellow
} else {
    if ($currentCstHome) {
        Write-Host "  [INFO] CST_HOME is currently set to: $currentCstHome" -ForegroundColor Yellow
        Write-Host "  [INFO] Updating to: $cstDir" -ForegroundColor Yellow
    } else {
        Write-Host "  [INFO] CST_HOME is not set" -ForegroundColor Yellow
        Write-Host "  [INFO] Setting CST_HOME = $cstDir" -ForegroundColor Yellow
    }

    try {
        # Set system environment variable CST_HOME
        [System.Environment]::SetEnvironmentVariable(
            "CST_HOME",
            $cstDir,
            [System.EnvironmentVariableTarget]::Machine
        )
        Write-Host "  [OK] CST_HOME environment variable set successfully" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Failed to set CST_HOME environment variable" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# Step 6: Add %CST_HOME% to system PATH if not already present
Write-Host "Step 4: Configuring system PATH..." -ForegroundColor Green

try {
    # Get current system PATH
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

    # Check if %CST_HOME% or the actual path is already in PATH
    $pathEntries = $currentPath -split ';'
    $cstInPath = $pathEntries | Where-Object {
        $_ -eq '%CST_HOME%' -or $_ -eq $cstDir
    }

    if ($cstInPath) {
        Write-Host "  [INFO] CST_HOME is already in system PATH" -ForegroundColor Yellow
        Write-Host "  [INFO] Skipping PATH configuration" -ForegroundColor Yellow
    } else {
        Write-Host "  [INFO] Adding %CST_HOME% to system PATH" -ForegroundColor Yellow

        # Add %CST_HOME% to PATH (using variable reference for flexibility)
        $newPath = $currentPath.TrimEnd(';') + ";%CST_HOME%"

        [System.Environment]::SetEnvironmentVariable(
            "Path",
            $newPath,
            [System.EnvironmentVariableTarget]::Machine
        )

        Write-Host "  [OK] Added %CST_HOME% to system PATH" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERROR] Failed to update system PATH" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 7: Refresh environment variables for current session
Write-Host "Step 5: Refreshing environment variables for current session..." -ForegroundColor Green
# Update PATH for current session (so we can test immediately)
$env:CST_HOME = $cstDir
# Only add to current PATH if not already there
if ($env:Path -notlike "*$cstDir*") {
    $env:Path = "$env:Path;$cstDir"
    Write-Host "  [OK] Environment refreshed for current session" -ForegroundColor Green
} else {
    Write-Host "  [INFO] Path already includes CST directory in current session" -ForegroundColor Yellow
}
Write-Host ""

# Step 8: Test the installation
Write-Host "Step 6: Testing installation..." -ForegroundColor Green
Write-Host "  Running: container-structure-test version"

try {
    $versionOutput = & $cstExe version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Container Structure Test is working!" -ForegroundColor Green
        Write-Host "  Version info:" -ForegroundColor Cyan
        Write-Host "  $versionOutput"
    } else {
        Write-Host "  [WARNING] Executable exists but returned exit code $LASTEXITCODE" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARNING] Could not run version check" -ForegroundColor Yellow
    Write-Host "  Error: $_" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installation Summary:" -ForegroundColor White
Write-Host "  Installation Directory: $cstDir" -ForegroundColor White
Write-Host "  Executable: $cstExe" -ForegroundColor White
Write-Host "  CST_HOME Variable: $cstDir" -ForegroundColor White
Write-Host "  Added to System PATH: Yes" -ForegroundColor White
Write-Host ""
Write-Host "[WARNING] IMPORTANT: You may need to restart your PowerShell session" -ForegroundColor Yellow
Write-Host "         or terminal for the PATH changes to take effect in new windows." -ForegroundColor Yellow
Write-Host ""
Write-Host "To verify the installation in a new terminal, run:" -ForegroundColor Cyan
Write-Host "  container-structure-test version" -ForegroundColor White
Write-Host ""
Write-Host "To run tests, use:" -ForegroundColor Cyan
Write-Host "  container-structure-test test --image IMAGE_NAME --config tests.yaml" -ForegroundColor White
Write-Host ""
Write-Host "[SUCCESS] Installation completed successfully!" -ForegroundColor Green
