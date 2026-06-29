#!/usr/bin/env bash
# ============================================================================
# runner/host/90-bootstrap-build.sh
# ============================================================================
# ONE-TIME bootstrap build — run directly on the fcg-runner-host engine.
#
# PROBLEM SOLVED (chicken-and-egg):
#   The runner image is built from THIS repository, but building requires a
#   runner that does not yet exist, and GitHub-hosted runners cannot handle
#   the ~35 GB build (they cap at ~30 GB).  This script bypasses the chicken-
#   and-egg by running build.sh and run_tests.sh DIRECTLY on the host distro
#   (no container) so the warm Podman layer cache is used from the start.
#   After this completes, the supervisor can self-sustain: every subsequent
#   build runs inside an ephemeral runner container on the same host engine.
#
# WHAT THIS SCRIPT DOES:
#   1. Validates prerequisites (PAT set, Podman running, git + gitversion present)
#   2. Clones the repo (or uses an existing clone at REPO_DIR)
#   3. Runs bash build.sh  — builds both ubuntu-26.04 and ubuntu-26.04-runner
#   4. Runs bash run_tests.sh (tests.yaml) against the distro image
#   5. Runs the runner tests (tests-runner.yaml) against the runner image
#   6. Logs in to GHCR using the PAT from /etc/fcg-runner/pat
#   7. Re-tags local images to ghcr.io/tmatwood/... and pushes:
#        ghcr.io/tmatwood/ubuntu-26.04:<ver>     + :latest
#        ghcr.io/tmatwood/ubuntu-26.04-runner:<ver>  + :current
#
# RUN ONCE, inside fcg-runner-host, as root or a user with sudo + podman access.
# After this run the supervisor will handle all future builds.
#
# USAGE:
#   sudo bash /path/to/runner/host/90-bootstrap-build.sh
#
#   # To use an existing local repo clone instead of cloning fresh:
#   REPO_DIR=/home/dev/wsl-custom-distro \
#     sudo bash /path/to/runner/host/90-bootstrap-build.sh
# ============================================================================

set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────────────
GHCR_OWNER="tmatwood"
GHCR_REGISTRY="ghcr.io"
REPO_URL="https://github.com/TMAtwood/wsl-custom-distro.git"
PAT_FILE="/etc/fcg-runner/pat"

# Where to clone the repo; override via REPO_DIR env var
REPO_DIR="${REPO_DIR:-/var/lib/fcg-runner/bootstrap-build}"

# Local image names produced by build.sh
LOCAL_DISTRO_IMAGE="localhost/tmatwood/ubuntu-26.04"
LOCAL_RUNNER_IMAGE="localhost/tmatwood/ubuntu-26.04-runner"

# GHCR target image names
GHCR_DISTRO_IMAGE="${GHCR_REGISTRY}/${GHCR_OWNER}/ubuntu-26.04"
GHCR_RUNNER_IMAGE="${GHCR_REGISTRY}/${GHCR_OWNER}/ubuntu-26.04-runner"

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo "[INFO]    $*"; }
success() { echo "[SUCCESS] $*"; }
warn()    { echo "[WARN]    $*"; }
err()     { echo "[ERROR]   $*" >&2; exit 1; }

# ============================================================================
# 1. Prerequisites check
# ============================================================================

info "Checking prerequisites..."

# PAT file — must be the real token, not the placeholder
if [[ ! -f "${PAT_FILE}" ]]; then
  err "PAT file not found at ${PAT_FILE}.  Run 10-bootstrap-host.sh first."
fi

PAT="$(head -1 "${PAT_FILE}")"
if [[ -z "${PAT}" ]] || [[ "${PAT}" == REPLACE_ME* ]]; then
  err "PAT placeholder still present at ${PAT_FILE}."$'\n'"      Replace it with your real fine-grained PAT before running this script."$'\n'"      echo 'ghp_yourToken' | sudo tee ${PAT_FILE}"
fi

# Podman
if ! command -v podman &>/dev/null; then
  err "podman not found. Run 10-bootstrap-host.sh first."
fi

# Confirm rootful podman is reachable (not just the binary)
if ! podman info &>/dev/null; then
  err "podman is installed but 'podman info' failed.  Is podman.socket active?"$'\n'"      Try: systemctl start podman.socket"
fi
success "rootful Podman: $(podman --version)"

# git
if ! command -v git &>/dev/null; then
  err "git not found. Run 10-bootstrap-host.sh first."
fi

# GitVersion (optional but strongly recommended; build.sh falls back to 0.0.0-dev)
if ! command -v gitversion &>/dev/null; then
  warn "gitversion not found — version tag will be '0.0.0-dev'."
  warn "  Run 10-bootstrap-host.sh to install GitVersion, or set SKIP_GITVERSION=1 to suppress this warning."
else
  info "gitversion: $(gitversion /version 2>/dev/null | head -1 || echo 'available')"
fi

# container-structure-test (required for run_tests.sh)
if ! command -v container-structure-test &>/dev/null; then
  info "container-structure-test not found — installing..."
  CST_VERSION="v1.19.3"
  curl -fsSL \
    "https://github.com/GoogleContainerTools/container-structure-test/releases/download/${CST_VERSION}/container-structure-test-linux-amd64" \
    -o /usr/local/bin/container-structure-test
  chmod +x /usr/local/bin/container-structure-test
  success "container-structure-test installed."
fi

success "All prerequisites satisfied."

# ============================================================================
# 2. Clone or refresh the repo
# ============================================================================

if [[ -d "${REPO_DIR}/.git" ]]; then
  warn "Repo already present at ${REPO_DIR} — pulling latest from origin..."
  git -C "${REPO_DIR}" fetch --all
  git -C "${REPO_DIR}" checkout main
  git -C "${REPO_DIR}" pull --ff-only origin main
  success "Repo updated."
else
  info "Cloning ${REPO_URL}..."
  info "  into: ${REPO_DIR}"
  # Full history required: GitVersion traverses the full graph to compute SemVer.
  git clone "${REPO_URL}" "${REPO_DIR}"
  success "Repo cloned."
fi

cd "${REPO_DIR}"
info "Working directory: $(pwd)"
info "HEAD commit: $(git log -1 --oneline)"

# ============================================================================
# 3. Build both images
#
#    build.sh builds:
#      localhost/tmatwood/ubuntu-26.04:<ver>         (--target final)
#      localhost/tmatwood/ubuntu-26.04:<ver>:latest  (tag)
#      localhost/tmatwood/ubuntu-26.04-runner:<ver>  (--target runner)
#      localhost/tmatwood/ubuntu-26.04-runner:current (tag)
#
#    Warm layer cache: stages 1-5 of the distro image will likely already be
#    present from previous runs; only changed layers are rebuilt.
# ============================================================================

info "=================================================================="
info " Building both images (ubuntu-26.04 + ubuntu-26.04-runner)..."
info " This may take 20-30 min on a cold cache, or a few minutes warm."
info "=================================================================="

bash build.sh
success "build.sh completed."

# ─── Capture the version GitVersion (or build.sh fallback) produced ───────────
if command -v gitversion &>/dev/null; then
  VERSION="$(gitversion 2>/dev/null | jq -r '.SemVer // "0.0.0-dev"')"
else
  VERSION="0.0.0-dev"
fi
info "Version tag: ${VERSION}"

LOCAL_DISTRO_VERSIONED="${LOCAL_DISTRO_IMAGE}:${VERSION}"
LOCAL_RUNNER_VERSIONED="${LOCAL_RUNNER_IMAGE}:${VERSION}"

# Sanity: confirm both images exist locally
if ! podman image exists "${LOCAL_DISTRO_VERSIONED}"; then
  err "Expected image not found after build: ${LOCAL_DISTRO_VERSIONED}"
fi
if ! podman image exists "${LOCAL_RUNNER_VERSIONED}"; then
  err "Expected runner image not found after build: ${LOCAL_RUNNER_VERSIONED}"
fi

success "Both local images confirmed present."

# ============================================================================
# 4. Test the distro image (tests.yaml)
# ============================================================================

info "Running distro image tests (tests.yaml)..."
IMAGE_NAME="${LOCAL_DISTRO_VERSIONED}" bash run_tests.sh
success "Distro tests passed."

# ============================================================================
# 5. Test the runner image (tests-runner.yaml)
# ============================================================================

info "Running runner image tests (tests-runner.yaml)..."
CONFIG_FILE="tests-runner.yaml" IMAGE_NAME="${LOCAL_RUNNER_VERSIONED}" bash run_tests.sh
success "Runner tests passed."

# ============================================================================
# 6. GHCR login
# ============================================================================

info "Logging in to ${GHCR_REGISTRY} as ${GHCR_OWNER}..."
echo "${PAT}" | podman login "${GHCR_REGISTRY}" --username "${GHCR_OWNER}" --password-stdin
success "GHCR login successful."

# ============================================================================
# 7. Re-tag local images to GHCR names and push
#
#    Distro image:
#      ghcr.io/tmatwood/ubuntu-26.04:<ver>   (versioned)
#      ghcr.io/tmatwood/ubuntu-26.04:latest  (moving latest)
#
#    Runner image:
#      ghcr.io/tmatwood/ubuntu-26.04-runner:<ver>     (versioned)
#      ghcr.io/tmatwood/ubuntu-26.04-runner:current   (moving current — supervisor tracks this)
# ============================================================================

info "Tagging and pushing distro image..."

GHCR_DISTRO_VERSIONED="${GHCR_DISTRO_IMAGE}:${VERSION}"
GHCR_DISTRO_LATEST="${GHCR_DISTRO_IMAGE}:latest"

podman tag "${LOCAL_DISTRO_VERSIONED}" "${GHCR_DISTRO_VERSIONED}"
podman tag "${LOCAL_DISTRO_VERSIONED}" "${GHCR_DISTRO_LATEST}"

podman push "${GHCR_DISTRO_VERSIONED}"
success "Pushed: ${GHCR_DISTRO_VERSIONED}"

podman push "${GHCR_DISTRO_LATEST}"
success "Pushed: ${GHCR_DISTRO_LATEST}"

info "Tagging and pushing runner image..."

GHCR_RUNNER_VERSIONED="${GHCR_RUNNER_IMAGE}:${VERSION}"
GHCR_RUNNER_CURRENT="${GHCR_RUNNER_IMAGE}:current"

podman tag "${LOCAL_RUNNER_VERSIONED}" "${GHCR_RUNNER_VERSIONED}"
podman tag "${LOCAL_RUNNER_VERSIONED}" "${GHCR_RUNNER_CURRENT}"

podman push "${GHCR_RUNNER_VERSIONED}"
success "Pushed: ${GHCR_RUNNER_VERSIONED}"

podman push "${GHCR_RUNNER_CURRENT}"
success "Pushed: ${GHCR_RUNNER_CURRENT}"

# ============================================================================
# 8. Done
# ============================================================================

echo ""
success "=================================================================="
success " Bootstrap build complete!"
success "=================================================================="
echo ""
info "Images built and pushed:"
info "  ${GHCR_DISTRO_VERSIONED}"
info "  ${GHCR_DISTRO_LATEST}"
info "  ${GHCR_RUNNER_VERSIONED}"
info "  ${GHCR_RUNNER_CURRENT}"
echo ""
info "Next steps:"
info "  1. Create the runner group (infra/ or manually in GitHub org settings)."
info "     Scope visibility to 'selected' and add allowed repositories."
echo ""
info "  2. Note the runner_group_id — the supervisor needs it to mint JIT configs."
echo ""
info "  3. Install runner/supervisor/ scripts into /opt/fcg-runner/:"
info "       sudo cp runner/supervisor/supervisor.sh /opt/fcg-runner/"
info "       sudo cp runner/supervisor/adopt.sh      /opt/fcg-runner/"
info "       sudo cp runner/supervisor/prune.sh      /opt/fcg-runner/"
info "       sudo chmod 0750 /opt/fcg-runner/*.sh"
echo ""
info "  4. Install and enable supervisor.service:"
info "       sudo cp runner/supervisor/supervisor.service /etc/systemd/system/"
info "       sudo systemctl daemon-reload"
info "       sudo systemctl enable --now supervisor.service"
echo ""
info "  The supervisor will pull-if-newer from ${GHCR_RUNNER_CURRENT},"
info "  mint a JIT config, and run one ephemeral container per CI job."
echo ""
warn "From this point forward, image builds run INSIDE ephemeral runner"
warn "containers (via build-image.yml), not directly on the host.  This"
warn "script is a one-time bootstrap only."
echo ""
