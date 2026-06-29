#!/usr/bin/env bash
# ============================================================================
# runner/host/10-bootstrap-host.sh
# ============================================================================
# Run ONCE, INSIDE the fcg-runner-host WSL2 distro, as root (or via sudo).
#
# What this does:
#   1. Installs rootful Podman + enables podman.socket via systemd
#   2. Installs git, curl, jq (core deps)
#   3. Installs GitVersion as a self-contained native binary (no .NET required)
#   4. Creates the 'svc-runner' system service user (no login shell)
#   5. Creates /etc/fcg-runner, /opt/fcg-runner, /var/lib/fcg-runner
#   6. Places a 0600 PAT placeholder at /etc/fcg-runner/pat (svc-runner-owned)
#   7. Grants svc-runner least-privilege access to the rootful Podman socket
#      via a dedicated 'podman-socket' group and a systemd socket drop-in
#
# USAGE (from Windows, after running 00-create-host-distro.ps1):
#   wsl -d fcg-runner-host -- bash /mnt/c/path/to/runner/host/10-bootstrap-host.sh
# OR (from inside the distro):
#   sudo bash /path/to/runner/host/10-bootstrap-host.sh
#
# IDEMPOTENT: safe to re-run; existing users, dirs, and the PAT file are
# preserved on repeat invocations.
# ============================================================================

set -euo pipefail

# ─── Guard: must be root ──────────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
  echo "[ERROR] This script must be run as root or via sudo." >&2
  exit 1
fi

# ─── Constants ────────────────────────────────────────────────────────────────
RUNNER_SVC_USER="svc-runner"
FCG_CONFIG_DIR="/etc/fcg-runner"
FCG_SCRIPTS_DIR="/opt/fcg-runner"
FCG_WORK_DIR="/var/lib/fcg-runner"
PAT_FILE="${FCG_CONFIG_DIR}/pat"
PODMAN_SOCKET="/run/podman/podman.sock"
PODMAN_SOCKET_GROUP="podman-socket"

# GitVersion native Linux binary (self-contained, no .NET runtime required)
# Pinned version — update deliberately and test after.
GITVERSION_VERSION="6.0.7"
GITVERSION_URL="https://github.com/GitTools/GitVersion/releases/download/${GITVERSION_VERSION}/gitversion-linux-x64-${GITVERSION_VERSION}.tar.gz"
GITVERSION_BIN="/usr/local/bin/gitversion"

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo "[INFO]    $*"; }
success() { echo "[SUCCESS] $*"; }
warn()    { echo "[WARN]    $*"; }
err()     { echo "[ERROR]   $*" >&2; }

# ============================================================================
# 1. System update + core dependencies
# ============================================================================

info "Updating apt package index..."
apt-get update -y -q

info "Installing core dependencies (curl, git, jq, ca-certificates)..."
apt-get install -y -q --no-install-recommends \
  curl \
  git \
  jq \
  ca-certificates \
  gnupg

success "Core dependencies installed."

# ============================================================================
# 2. Install rootful Podman
# ============================================================================

if command -v podman &>/dev/null; then
  warn "Podman already installed: $(podman --version) — skipping apt install."
else
  info "Installing rootful Podman..."
  apt-get install -y -q --no-install-recommends podman

  if ! command -v podman &>/dev/null; then
    err "Podman not found after install."
    exit 1
  fi
  success "Podman installed: $(podman --version)"
fi

# ============================================================================
# 3. Enable rootful podman.socket
#    /run/podman/podman.sock — persistent via systemd; brings up on distro start
# ============================================================================

info "Enabling rootful podman.socket..."

# systemd must be running (fcg-runner-host has systemd=true in wsl.conf)
if ! systemctl is-system-running --quiet 2>/dev/null; then
  warn "systemd does not appear to be the init system, or is still starting."
  warn "Proceeding; enable podman.socket manually if needed: systemctl enable --now podman.socket"
else
  systemctl enable --now podman.socket
  success "podman.socket enabled and started."

  # Give the socket a moment
  sleep 1
  if [[ -S "${PODMAN_SOCKET}" ]]; then
    success "Podman socket active: ${PODMAN_SOCKET}"
  else
    warn "${PODMAN_SOCKET} not yet present — it will appear after a full boot."
  fi
fi

# ============================================================================
# 4. Install GitVersion native binary (for bootstrap build — see 90-bootstrap-build.sh)
#    This is a self-contained Linux amd64 binary; no .NET runtime needed.
#    Pinned to GITVERSION_VERSION above.
# ============================================================================

if [[ -x "${GITVERSION_BIN}" ]]; then
  warn "GitVersion already at ${GITVERSION_BIN} — skipping download."
  info "  Installed: $("${GITVERSION_BIN}" /version 2>/dev/null | head -1 || echo 'unknown')"
else
  info "Downloading GitVersion ${GITVERSION_VERSION} (native Linux amd64)..."
  GITVERSION_TMP="$(mktemp -d)"
  curl -fsSL "${GITVERSION_URL}" -o "${GITVERSION_TMP}/gitversion.tar.gz"
  tar -xzf "${GITVERSION_TMP}/gitversion.tar.gz" -C "${GITVERSION_TMP}"
  install -m 0755 "${GITVERSION_TMP}/gitversion" "${GITVERSION_BIN}"
  rm -rf "${GITVERSION_TMP}"
  success "GitVersion installed: $("${GITVERSION_BIN}" /version 2>/dev/null | head -1 || echo 'installed')"
fi

# ============================================================================
# 5. Create 'svc-runner' system user
#    - system account (UID in system range)
#    - no home directory
#    - /usr/sbin/nologin shell (cannot log in interactively)
# ============================================================================

if id "${RUNNER_SVC_USER}" &>/dev/null; then
  warn "User '${RUNNER_SVC_USER}' already exists — skipping creation."
else
  info "Creating system user '${RUNNER_SVC_USER}'..."
  useradd \
    --system \
    --no-create-home \
    --shell /usr/sbin/nologin \
    --comment "FCG runner supervisor service account" \
    "${RUNNER_SVC_USER}"
  success "User '${RUNNER_SVC_USER}' created."
fi

# ============================================================================
# 6. Create runner directories
#
#   /etc/fcg-runner     0700  svc-runner  — sensitive config (PAT lives here)
#   /opt/fcg-runner     0755  root        — supervisor scripts (world-readable)
#   /var/lib/fcg-runner 0750  svc-runner  — working data
# ============================================================================

info "Creating runner directories..."

install -d -m 0700 -o "${RUNNER_SVC_USER}" -g "${RUNNER_SVC_USER}" "${FCG_CONFIG_DIR}"
install -d -m 0755 -o root -g root "${FCG_SCRIPTS_DIR}"
install -d -m 0750 -o "${RUNNER_SVC_USER}" -g "${RUNNER_SVC_USER}" "${FCG_WORK_DIR}"

success "Runner directories created:"
info "  ${FCG_CONFIG_DIR}  (0700 ${RUNNER_SVC_USER})"
info "  ${FCG_SCRIPTS_DIR}  (0755 root)"
info "  ${FCG_WORK_DIR}  (0750 ${RUNNER_SVC_USER})"

# ============================================================================
# 7. PAT placeholder at /etc/fcg-runner/pat
#
#    MODE:  0600
#    OWNER: svc-runner
#    CONTENT: placeholder ONLY — a real PAT is placed manually by the operator.
#
#    Required PAT scopes (fine-grained, org-level):
#      Organization self-hosted runners: Read and Write
#
#    To set the real PAT after bootstrap:
#      echo "ghp_yourTokenHere" | sudo tee /etc/fcg-runner/pat
#      sudo chown svc-runner:svc-runner /etc/fcg-runner/pat
#      sudo chmod 0600 /etc/fcg-runner/pat
#
#    NEVER commit this file or embed a real token here.
# ============================================================================

if [[ -f "${PAT_FILE}" ]]; then
  warn "PAT file already exists at ${PAT_FILE} — not overwriting."
  warn "  Verify it contains a real token before starting the supervisor."
else
  info "Writing PAT placeholder at ${PAT_FILE}..."

  # The supervisor reads only the FIRST non-comment line of this file.
  # Replace the REPLACE_ME line with the real token; leave comments intact.
  cat > "${PAT_FILE}" <<'EOF'
REPLACE_ME_WITH_REAL_FINE_GRAINED_PAT
# ===========================================================================
# /etc/fcg-runner/pat — GitHub fine-grained PAT for the runner supervisor.
#
# REQUIRED SCOPES (fine-grained, org-level):
#   Organization self-hosted runners: Read and Write
#
# The supervisor reads only the FIRST line of this file (the token itself).
# Replace the REPLACE_ME line above with your real PAT.
#
# To update:
#   echo "ghp_yourTokenHere" | sudo tee /etc/fcg-runner/pat
#   sudo chown svc-runner:svc-runner /etc/fcg-runner/pat
#   sudo chmod 0600 /etc/fcg-runner/pat
#
# NEVER check this file into git. NEVER pass as a build arg.
# Rotate on a documented cadence (see docs/RUNNER.md).
# ===========================================================================
EOF

  chown "${RUNNER_SVC_USER}:${RUNNER_SVC_USER}" "${PAT_FILE}"
  chmod 0600 "${PAT_FILE}"
  success "PAT placeholder written (mode 0600, owner ${RUNNER_SVC_USER})."
fi

# ============================================================================
# 8. Grant svc-runner least-privilege access to the rootful Podman socket
#
#    Strategy:
#      a) Create a dedicated system group 'podman-socket'
#      b) Add svc-runner to that group
#      c) Install a systemd drop-in on podman.socket that sets SocketGroup and
#         SocketMode so the socket file is group-readable/writable on each boot
#
#    This avoids giving svc-runner passwordless sudo for podman, and avoids
#    making the socket world-readable.  The group drop-in persists across
#    reboots; no manual chgrp/chmod needed after each start.
# ============================================================================

info "Configuring Podman socket group access for '${RUNNER_SVC_USER}'..."

# a) Create the group if it does not exist
if getent group "${PODMAN_SOCKET_GROUP}" &>/dev/null; then
  warn "Group '${PODMAN_SOCKET_GROUP}' already exists."
else
  groupadd --system "${PODMAN_SOCKET_GROUP}"
  success "Group '${PODMAN_SOCKET_GROUP}' created."
fi

# b) Add svc-runner to the group
usermod -aG "${PODMAN_SOCKET_GROUP}" "${RUNNER_SVC_USER}"
success "'${RUNNER_SVC_USER}' added to group '${PODMAN_SOCKET_GROUP}'."

# c) systemd drop-in: set SocketGroup + SocketMode on the socket unit
DROPIN_DIR="/etc/systemd/system/podman.socket.d"
DROPIN_FILE="${DROPIN_DIR}/socket-group.conf"

install -d -m 0755 "${DROPIN_DIR}"

cat > "${DROPIN_FILE}" <<EOF
# Managed by 10-bootstrap-host.sh — do not edit manually.
# Sets the group and mode on /run/podman/podman.sock so that members of
# '${PODMAN_SOCKET_GROUP}' can reach the rootful Podman engine without sudo.
[Socket]
SocketGroup=${PODMAN_SOCKET_GROUP}
SocketMode=0660
EOF

systemctl daemon-reload
if systemctl is-active --quiet podman.socket 2>/dev/null; then
  systemctl restart podman.socket
  success "podman.socket restarted with group=${PODMAN_SOCKET_GROUP} mode=0660."
else
  warn "podman.socket not currently active; drop-in will apply on next start."
fi

# ============================================================================
# 9. Done
# ============================================================================

echo ""
success "============================================================"
success " Bootstrap complete for fcg-runner-host."
success "============================================================"
echo ""
info "Summary of changes:"
info "  Packages  : podman, curl, git, jq, ca-certificates"
info "  GitVersion: ${GITVERSION_BIN} (v${GITVERSION_VERSION}, native binary)"
info "  Service   : rootful podman.socket enabled via systemd"
info "  User      : ${RUNNER_SVC_USER} (system, no login)"
info "  Dirs      : ${FCG_CONFIG_DIR} (0700)  ${FCG_SCRIPTS_DIR} (0755)  ${FCG_WORK_DIR} (0750)"
info "  PAT       : ${PAT_FILE} (0600 ${RUNNER_SVC_USER}) — placeholder only"
info "  Socket    : ${PODMAN_SOCKET_GROUP} group + systemd drop-in for 0660"
echo ""
warn "BEFORE STARTING THE SUPERVISOR — ACTION REQUIRED:"
warn "  1. Replace PAT placeholder:"
warn "       echo 'ghp_REAL_TOKEN' | sudo tee ${PAT_FILE}"
warn "       sudo chown ${RUNNER_SVC_USER}:${RUNNER_SVC_USER} ${PAT_FILE}"
warn "       sudo chmod 0600 ${PAT_FILE}"
warn ""
warn "  2. Install supervisor scripts (runner/supervisor/) into ${FCG_SCRIPTS_DIR}/"
warn "     and enable supervisor.service."
warn ""
warn "  3. Register Windows autostart task from an elevated PowerShell prompt:"
warn "       .\\30-autostart.ps1"
warn ""
warn "  4. For the very first image build (bootstrap chicken-and-egg):"
warn "       sudo bash runner/host/90-bootstrap-build.sh"
echo ""
