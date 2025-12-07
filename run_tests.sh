#!/bin/bash

# Run Container Structure Tests against the built image
# Image name should match what's built in build.ps1 or build-podman.sh

IMAGE_NAME="${IMAGE_NAME:-localhost/tmatwood/ubuntu-24.04:latest}"

echo "Running Container Structure Tests..."
echo "Image: ${IMAGE_NAME}"
echo "Config: tests.yaml"
echo ""

container-structure-test test --image "${IMAGE_NAME}" --config tests.yaml

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ All tests passed!"
else
    echo ""
    echo "❌ Tests failed with exit code: $exit_code"
fi

exit $exit_code
