#!/bin/bash
# Pre-commit hook for Trivy container image vulnerability scanning
# Scans the built container image for critical vulnerabilities

set -e

IMAGE="localhost/tmatwood/ubuntu-26.04:latest"

if ! command -v trivy >/dev/null 2>&1; then
    echo "Skipping: trivy not installed (brew install trivy)"
    exit 0
fi

# Check if image exists (try podman first, then docker)
image_exists=false
if command -v podman >/dev/null 2>&1; then
    if podman images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "^${IMAGE}$"; then
        image_exists=true
    fi
fi

if [ "$image_exists" = false ] && command -v docker >/dev/null 2>&1; then
    if docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "^${IMAGE}$"; then
        image_exists=true
    fi
fi

if [ "$image_exists" = false ]; then
    echo "Skipping trivy image scan: Image ${IMAGE} not found"
    exit 0
fi

echo "Running Trivy vulnerability scan on ${IMAGE}..."
trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed "${IMAGE}"
