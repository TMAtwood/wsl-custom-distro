#!/bin/bash
# Pre-commit hook for Dockle container security linting
# Scans the built container image for security issues

set -e

IMAGE="localhost/tmatwood/ubuntu-26.04:latest"

if ! command -v dockle >/dev/null 2>&1; then
    echo "Skipping: dockle not installed (brew install dockle)"
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
    echo "Skipping dockle: Image ${IMAGE} not found"
    exit 0
fi

echo "Running Dockle security scan on ${IMAGE}..."
dockle --exit-code 1 --exit-level warn \
    -i CIS-DI-0001 \
    -i DKL-DI-0006 \
    "${IMAGE}"
