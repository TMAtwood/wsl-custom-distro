#!/bin/bash
# Pre-commit hook for container structure tests
# Validates container image structure and installed software

set -e

IMAGE="localhost/tmatwood/ubuntu-26.04:latest"
CONFIG="tests.yaml"

if ! command -v container-structure-test >/dev/null 2>&1; then
    echo "Skipping: container-structure-test not installed"
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
    echo "Skipping: Image ${IMAGE} not built"
    exit 0
fi

echo "Running container structure tests on ${IMAGE}..."
container-structure-test test --image "${IMAGE}" --config "${CONFIG}"
