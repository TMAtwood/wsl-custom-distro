#!/bin/bash
# Pre-commit hook for Trivy configuration scanning
# Scans Dockerfile and YAML files for misconfigurations

set -e

if ! command -v trivy >/dev/null 2>&1; then
    echo "Skipping: trivy not installed (brew install trivy)"
    exit 0
fi

echo "Running Trivy configuration scan..."
trivy config \
    --exit-code 1 \
    --severity HIGH,CRITICAL \
    --skip-dirs .git \
    --skip-dirs .venv \
    --skip-dirs node_modules \
    --skip-dirs .trunk \
    .
