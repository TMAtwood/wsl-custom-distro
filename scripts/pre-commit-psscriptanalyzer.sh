#!/bin/bash
# Pre-commit hook for PowerShell Script Analyzer
# Analyzes PowerShell scripts for best practices and potential issues

set -e

if ! command -v pwsh >/dev/null 2>&1; then
    echo "Skipping: PowerShell not installed"
    exit 0
fi

# Check if PSScriptAnalyzer module is installed
if ! pwsh -NoProfile -Command "Get-Module -ListAvailable -Name PSScriptAnalyzer" >/dev/null 2>&1; then
    echo "Skipping: PSScriptAnalyzer module not installed"
    echo "Install with: pwsh -Command 'Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser'"
    exit 0
fi

echo "Running PowerShell Script Analyzer..."

# Find all .ps1 files and analyze them
exit_code=0
while IFS= read -r -d '' file; do
    echo "Analyzing: $file"
    if ! pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path '$file' -Severity Warning -EnableExit"; then
        exit_code=1
    fi
done < <(find . -name "*.ps1" -type f -not -path "./.git/*" -not -path "./.venv/*" -print0)

exit $exit_code
