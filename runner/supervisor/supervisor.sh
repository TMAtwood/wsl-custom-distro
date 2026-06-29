#!/usr/bin/env bash
# ============================================================================
# supervisor.sh — FCG self-hosted ephemeral runner supervisor loop.
# ============================================================================
# Runs as svc-runner under systemd (supervisor.service). Serializes exactly
# ONE ephemeral runner container at a time. Each iteration:
#
#   1. pull-if-newer  — pull ghcr.io/.../ubuntu-26.04-runner:current; if the
#                       digest differs from the local :current, call adopt.sh.
#   2. mint JIT config — POST to the repo-scoped generate-jitconfig endpoint
#                        using the PAT from /etc/fcg-runner/pat.
#   3. run one container — `podman run --rm` from the LOCAL :current image;
#                          wait for it to exit (one job, then destroyed).
#   4. loop.
#
# Handles SIGTERM/SIGINT for graceful systemd stop: finishes the in-flight
# job, then exits. TimeoutStopSec in the unit gives 300 s for this.
#
# Socket note: the rootful Podman socket is mounted into every container so
# build jobs (this repo only) can reach the host engine's 35 GB warm cache.
# The socket grants root-equivalent access to the host engine — intentional
# on this single-tenant private box, documented in docs/RUNNER.md. Run-mode
# jobs for other repos also receive it because the supervisor cannot
# distinguish job type at dispatch time.
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants — edit only if the canonical values in docs/runner-handoff.md change.
# ---------------------------------------------------------------------------
readonly GHCR_IMAGE="ghcr.io/tmatwood/ubuntu-26.04-runner:current"
readonly LOCAL_IMAGE="localhost/tmatwood/ubuntu-26.04-runner:current"
readonly GITHUB_REPO="TMAtwood/wsl-custom-distro"
readonly GITHUB_API="https://api.github.com"
readonly PAT_FILE="/etc/fcg-runner/pat"
readonly PODMAN_SOCKET="/run/podman/podman.sock"
readonly SCRIPT_DIR="/opt/fcg-runner"
readonly STATE_DIR="/var/lib/fcg-runner"
# work_folder is the path the runner agent uses INSIDE the ephemeral container.
# GitHub Actions default; unrelated to STATE_DIR on the host.
readonly RUNNER_WORK_FOLDER="_work"
# self-hosted is auto-applied by GitHub; listing it explicitly is harmless.
readonly RUNNER_LABELS='["self-hosted","fcg-local","wsl-build"]'
# generate-jitconfig requires a runner_group_id. 1 is the repo's "Default" group,
# which is correct for repo-scoped registration. Switch to the org group id from
# infra/ once the org is on GitHub Team/Enterprise (custom groups need it).
readonly RUNNER_GROUP_ID="${RUNNER_GROUP_ID:-1}"

# Route all podman calls from this script through the rootful socket.
# svc-runner must be in the group that owns /run/podman/podman.sock
# (configured by runner/host/10-bootstrap-host.sh).
export CONTAINER_HOST="unix://${PODMAN_SOCKET}"

# ---------------------------------------------------------------------------
# Graceful shutdown state
# ---------------------------------------------------------------------------
_STOP=0
_RUNNER_PID=""

handle_signal() {
    echo "[supervisor] Received stop signal; will exit after current job completes." >&2
    _STOP=1
    if [[ -n "${_RUNNER_PID}" ]]; then
        # Signal the running podman process; the container gets SIGTERM →
        # the runner agent finishes its current step and exits cleanly.
        kill -TERM "${_RUNNER_PID}" 2>/dev/null || true
    fi
}

trap 'handle_signal' SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[supervisor] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2; }
die() { echo "[supervisor] FATAL: $*" >&2; exit 1; }

read_pat() {
    [[ -f "${PAT_FILE}" ]] || die "PAT file not found: ${PAT_FILE}"
    local pat
    pat="$(<"${PAT_FILE}")"
    [[ -n "${pat}" ]] || die "PAT file is empty: ${PAT_FILE}"
    # Return via stdout so callers can capture it without it touching the log.
    printf '%s' "${pat}"
}

local_current_digest() {
    podman image inspect --format '{{.Digest}}' "${LOCAL_IMAGE}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Step 1: pull-if-newer
# ---------------------------------------------------------------------------
pull_if_newer() {
    log "Checking for image updates from GHCR …"

    local before_digest
    before_digest="$(local_current_digest)"

    # podman pull is a no-op when the remote digest matches local storage.
    if ! podman pull "${GHCR_IMAGE}" 2>&1; then
        log "WARNING: pull failed; continuing with existing local image."
        return 0
    fi

    local ghcr_digest
    ghcr_digest="$(podman image inspect --format '{{.Digest}}' "${GHCR_IMAGE}" 2>/dev/null || true)"

    if [[ -z "${ghcr_digest}" ]]; then
        log "WARNING: could not inspect pulled image; skipping adoption check."
        return 0
    fi

    if [[ "${before_digest}" != "${ghcr_digest}" ]]; then
        log "New image digest (${ghcr_digest:0:24}…); invoking adopt.sh."
        "${SCRIPT_DIR}/adopt.sh" "${GHCR_IMAGE}" || {
            log "WARNING: adopt.sh failed; staying on current image."
        }
    else
        log "Local image is current (${ghcr_digest:0:24}…); no adoption needed."
    fi
}

# ---------------------------------------------------------------------------
# Step 2: mint JIT config
# ---------------------------------------------------------------------------
mint_jitconfig() {
    local pat name payload response jitconfig
    pat="$(read_pat)"
    # Unique name: host short-name + UTC timestamp + PID (survives rapid restarts).
    name="fcg-runner-$(hostname -s)-$(date -u +%Y%m%dT%H%M%SZ)-$$"

    payload="$(printf '{"name":"%s","runner_group_id":%s,"labels":%s,"work_folder":"%s"}' \
        "${name}" "${RUNNER_GROUP_ID}" "${RUNNER_LABELS}" "${RUNNER_WORK_FOLDER}")"

    log "Minting JIT config for runner '${name}' …"

    # The PAT is passed via Authorization header; it never touches stdout/logs.
    response="$(curl \
        --silent \
        --show-error \
        --fail \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${pat}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        "${GITHUB_API}/repos/${GITHUB_REPO}/actions/runners/generate-jitconfig")"

    jitconfig="$(printf '%s' "${response}" | jq -r '.encoded_jit_config')"

    if [[ -z "${jitconfig}" || "${jitconfig}" == "null" ]]; then
        # Log the response for diagnosis (no PAT in it); exit non-zero.
        log "ERROR: generate-jitconfig did not return encoded_jit_config." >&2
        log "Response (truncated): ${response:0:400}" >&2
        return 1
    fi

    # Return the config via stdout; caller must never log the returned value.
    printf '%s' "${jitconfig}"
}

# ---------------------------------------------------------------------------
# Step 3: run one ephemeral container
# ---------------------------------------------------------------------------
run_ephemeral() {
    local jitconfig="$1"

    log "Launching ephemeral runner container from ${LOCAL_IMAGE} …"

    # Build the argument array so every value is safely quoted.
    local container_name
    container_name="fcg-runner-$(date -u +%s)-$$"

    # shellcheck disable=SC2206   # array intentionally split on spaces below
    local -a run_args=(
        "--rm"
        "--name"          "${container_name}"
        # JIT config: passed via env var (off process list; still readable via
        # /proc/PID/environ on a single-tenant host — accepted risk, documented).
        "-e"              "RUNNER_JITCONFIG=${jitconfig}"
        # Mount the rootful Podman socket so build jobs can reach the host
        # engine with its warm 35 GB layer cache. See security note at top.
        "-v"              "${PODMAN_SOCKET}:${PODMAN_SOCKET}"
        "-e"              "CONTAINER_HOST=unix://${PODMAN_SOCKET}"
        "${LOCAL_IMAGE}"
    )

    podman run "${run_args[@]}" &
    _RUNNER_PID=$!

    # Wait for the container to finish (blocks until job complete or SIGTERM).
    if ! wait "${_RUNNER_PID}"; then
        local exit_code=$?
        log "Runner container '${container_name}' exited with status ${exit_code}."
    else
        log "Runner container '${container_name}' exited cleanly."
    fi
    _RUNNER_PID=""
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
log "Supervisor starting. SCRIPT_DIR=${SCRIPT_DIR} STATE_DIR=${STATE_DIR}"

mkdir -p "${STATE_DIR}"

while [[ "${_STOP}" -eq 0 ]]; do

    # -- 1. Pull-if-newer (cheap digest check; no-op when already current) ----
    pull_if_newer || log "WARNING: pull_if_newer error; continuing."

    [[ "${_STOP}" -eq 0 ]] || break

    # -- 2. Mint JIT config ----------------------------------------------------
    local_jitconfig=""
    if ! local_jitconfig="$(mint_jitconfig)"; then
        log "WARNING: Failed to mint JIT config; sleeping 30 s before retry."
        sleep 30 &
        wait $! 2>/dev/null || true
        continue
    fi

    # -- 3. Run exactly one ephemeral container (serialized) -------------------
    run_ephemeral "${local_jitconfig}"

    # Scrub the config from local scope immediately after use.
    unset local_jitconfig

done

log "Supervisor stopped cleanly."
