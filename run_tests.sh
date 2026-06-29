#!/bin/bash

# Run Container Structure Tests against the built image
# Image name should match what's built in build.ps1 or build-podman.sh

IMAGE_NAME="${IMAGE_NAME:-localhost/tmatwood/ubuntu-26.04:latest}"
# Override to test other images, e.g. the runner image:
#   CONFIG_FILE=tests-runner.yaml \
#   IMAGE_NAME=localhost/tmatwood/ubuntu-26.04-runner:current bash run_tests.sh
CONFIG_FILE="${CONFIG_FILE:-tests.yaml}"

echo "Running Container Structure Tests..."
echo "Image: ${IMAGE_NAME}"
echo "Config: ${CONFIG_FILE}"
echo ""

container-structure-test test --image "${IMAGE_NAME}" --config "${CONFIG_FILE}"

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ All tests passed!"
else
    echo ""
    echo "❌ Tests failed with exit code: $exit_code"
fi

exit $exit_code
