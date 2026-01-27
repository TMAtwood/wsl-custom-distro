#!/bin/bash
# ============================================================================
# Build Script for WSL Ubuntu 24.04 Development Environment
# ============================================================================
# This script builds the Podman image with proper error handling
# and version management using GitVersion for semantic versioning.
# ============================================================================

set -euo pipefail

# Define colors for output
COLOR_SUCCESS='\033[0;32m'
COLOR_ERROR='\033[0;31m'
COLOR_WARNING='\033[0;33m'
COLOR_INFO='\033[0;36m'
COLOR_RESET='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

write_success() {
  echo -e "${COLOR_SUCCESS}[SUCCESS]${COLOR_RESET} $1"
}

write_error() {
  echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $1" >&2
}

write_info() {
  echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $1"
}

write_warning() {
  echo -e "${COLOR_WARNING}[WARNING]${COLOR_RESET} $1"
}

# ============================================================================
# Version Detection
# ============================================================================

get_build_version() {
  write_info "Determining version using GitVersion..." >&2

  # Check if gitversion is available
  if ! command -v gitversion &> /dev/null; then
    write_warning "GitVersion not found, using default version" >&2
    echo "0.0.0-dev"
    return 0
  fi

  # Get version from gitversion
  if ! gitversion_output=$(gitversion 2>&1); then
    write_warning "GitVersion failed, using default version" >&2
    echo "0.0.0-dev"
    return 0
  fi

  # Parse SemVer from JSON output
  if ! version=$(echo "$gitversion_output" | jq -r .SemVer 2>/dev/null); then
    write_warning "Failed to parse GitVersion output, using default version" >&2
    echo "0.0.0-dev"
    return 0
  fi

  if [ -z "$version" ] || [ "$version" = "null" ]; then
    write_warning "GitVersion returned empty SemVer, using default version" >&2
    echo "0.0.0-dev"
    return 0
  fi

  write_success "Version determined: $version" >&2
  echo "$version"
}

# ============================================================================
# Main Build Process
# ============================================================================

main() {
  echo -e "\n${COLOR_INFO}========================================"
  echo "  WSL Ubuntu 24.04 Image Build"
  echo -e "========================================${COLOR_RESET}\n"

  # Get version
  VERSION=$(get_build_version)
  export VERSION

  # Get build date
  BUILD_DATE=$(date '+%Y-%m-%d')
  export BUILD_DATE
  write_info "Build date: $BUILD_DATE"

  # Define image names
  IMAGE_NAME="localhost/tmatwood/ubuntu-24.04"
  IMAGE_NAME_AND_VERSION="${IMAGE_NAME}:${VERSION}"
  IMAGE_NAME_LATEST="${IMAGE_NAME}:latest"

  write_info "Image name: $IMAGE_NAME"
  write_info "Version tag: $IMAGE_NAME_AND_VERSION"
  write_info "Latest tag: $IMAGE_NAME_LATEST"

  # ========================================================================
  # Check Podman availability
  # ========================================================================
  write_info "\nChecking Podman availability..."

  # Check common locations for podman
  PODMAN_CMD=""
  if command -v podman &> /dev/null; then
    PODMAN_CMD="podman"
    write_success "Podman found in PATH"
  elif [ -x "/usr/bin/podman" ]; then
    PODMAN_CMD="/usr/bin/podman"
    write_success "Podman found at /usr/bin/podman"
  elif [ -x "$HOME/.local/bin/podman" ]; then
    PODMAN_CMD="$HOME/.local/bin/podman"
    write_success "Podman found at ~/.local/bin/podman"
  else
    write_error "Podman is not installed or not in PATH"
    write_warning "Install Podman using: sudo apt-get install -y podman"
    write_warning "Or run this script from within the container environment"
    exit 1
  fi

  # ========================================================================
  # Check if running in WSL
  # ========================================================================
  if grep -qi microsoft /proc/version 2>/dev/null; then
    write_info "Running in WSL environment"
  else
    write_info "Running in native Linux environment"
  fi

  # ========================================================================
  # Build the image
  # ========================================================================
  write_info "\nBuilding Docker image..."
  write_warning "This may take 15-30 minutes depending on your system..."

  BUILD_START_TIME=$(date +%s)

  if ! $PODMAN_CMD build \
    --format docker \
    --dns=1.1.1.1 \
    --dns=8.8.8.8 \
    --platform linux/amd64 \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    -t "$IMAGE_NAME_AND_VERSION" \
    .; then
    write_error "Podman build failed"
    exit 1
  fi

  BUILD_END_TIME=$(date +%s)
  BUILD_DURATION_SEC=$((BUILD_END_TIME - BUILD_START_TIME))
  BUILD_DURATION_DECIMAL=$(awk "BEGIN {printf \"%.2f\", $BUILD_DURATION_SEC / 60}")

  write_success "Image built successfully in ${BUILD_DURATION_DECIMAL} minutes"

  # ========================================================================
  # Tag the image as latest
  # ========================================================================
  write_info "\nTagging image as latest..."

  if ! $PODMAN_CMD tag "$IMAGE_NAME_AND_VERSION" "$IMAGE_NAME_LATEST"; then
    write_error "Failed to tag image as latest"
    exit 1
  fi

  write_success "Image tagged as latest"

  # ========================================================================
  # Build Summary
  # ========================================================================
  echo -e "\n${COLOR_SUCCESS}========================================"
  echo "  Build Completed Successfully!"
  echo "========================================"
  echo -e "${COLOR_INFO}  Version: ${VERSION}"
  echo "  Build Date: ${BUILD_DATE}"
  echo "  Image: ${IMAGE_NAME_AND_VERSION}"
  echo "  Latest: ${IMAGE_NAME_LATEST}"
  echo "  Duration: ${BUILD_DURATION_DECIMAL} minutes"
  echo -e "========================================${COLOR_RESET}\n"

  # ========================================================================
  # Show image info
  # ========================================================================
  write_info "Image information:"
  $PODMAN_CMD images "$IMAGE_NAME"

  exit 0
}

# ============================================================================
# Error Handler
# ============================================================================

error_handler() {
  echo -e "\n${COLOR_ERROR}========================================"
  echo "  Build Failed!"
  echo "========================================"
  echo "Error on line $1"
  echo -e "========================================${COLOR_RESET}"

  # Show troubleshooting tips
  write_warning "Troubleshooting tips:"
  echo -e "${COLOR_WARNING}  1. Ensure Podman is installed and running"
  echo "  2. Check if Podman service is running: systemctl --user status podman"
  echo "  3. Verify GitVersion is installed: gitversion --version"
  echo "  4. Check available disk space: df -h"
  echo "  5. Review build logs above for specific errors"
  echo -e "  6. Try cleaning up old images: podman system prune${COLOR_RESET}\n"

  exit 1
}

trap 'error_handler $LINENO' ERR

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
