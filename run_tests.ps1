#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run Container Structure Tests against the built image

.DESCRIPTION
    This script runs container-structure-test against the specified image.
    Image name should match what's built in build.ps1 or build-podman.sh

.PARAMETER ImageName
    The name of the container image to test. Defaults to localhost/tmatwood/ubuntu-24.04:latest

.PARAMETER ConfigFile
    The path to the test configuration file. Defaults to tests.yaml

.EXAMPLE
    .\run_tests.ps1

.EXAMPLE
    .\run_tests.ps1 -ImageName localhost/tmatwood/ubuntu-24.04:0.1.0

.EXAMPLE
    $env:IMAGE_NAME = "localhost/tmatwood/ubuntu-24.04:0.1.0"
    .\run_tests.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ImageName = $env:IMAGE_NAME,

    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "tests.yaml"
)

# Set default image name if not provided
if ([string]::IsNullOrEmpty($ImageName)) {
    $ImageName = "localhost/tmatwood/ubuntu-24.04:latest"
}

Write-Host "Running Container Structure Tests..." -ForegroundColor Cyan
Write-Host "Image: $ImageName" -ForegroundColor White
Write-Host "Config: $ConfigFile" -ForegroundColor White
Write-Host ""

# Run the tests
container-structure-test test --image "$ImageName" --config $ConfigFile

$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "✅ All tests passed!" -ForegroundColor Green
} else {
    Write-Host "❌ Tests failed with exit code: $exitCode" -ForegroundColor Red
}

exit $exitCode
