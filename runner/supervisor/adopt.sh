#!/usr/bin/env bash
# ============================================================================
# adopt.sh — Smoke-check and promote a new runner image to :current.
# ============================================================================
# Usage: adopt.sh <new-image>
#
#   <new-image>  Image ref to promote (typically the just-pulled GHCR tag:
#                ghcr.io/tmatwood/ubuntu-26.04-runner:current).
#
# Called by supervisor.sh BETWEEN jobs — never mid-job (the supervisor
# serializes and only calls this after the previous container has exited).
#
# On PASS:
#   localhost/.../ubuntu-26.04-runner:current  → :previous  (retained for rollback)
#   <new-image>                                → :current   (promoted)
#
# On FAIL:
#   :current left unchanged.
#   <new-image> left in local storage for manual inspection.
#   Supervisor continues running on the existing :current.
#
# Recovery note: if :current and :previous are both lost, the only recovery
# path is a manual host build (runner/host/90-bootstrap-build.sh). There is
# no hosted fallback — hosted runners cannot build this image (30 GB ceiling).
# See docs/RUNNER.md.
# ============================================================================

set -euo pipefail

readonly LOCAL_CURRENT="localhost/tmatwood/ubuntu-26.04-runner:current"
readonly LOCAL_PREVIOUS="localhost/tmatwood/ubuntu-26.04-runner:previous"

log() { echo "[adopt] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2; }
die() { echo "[adopt] FATAL: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "Usage: adopt.sh <new-image>"
readonly NEW_IMAGE="$1"

[[ -n "${NEW_IMAGE}" ]] || die "<new-image> argument is empty."

# ---------------------------------------------------------------------------
# Smoke-check: the runner binary must be able to report its version.
# An image that compiles but can't launch the agent is the worst failure mode
# (it would take the JIT slot, fail immediately, and leave the runner
# de-registered from GitHub with no job completion).
# ---------------------------------------------------------------------------
log "Smoke-checking: ${NEW_IMAGE} — running /opt/actions-runner/run.sh --version …"

if ! podman run \
        --rm \
        --name "fcg-adopt-smokecheck-$$" \
        "${NEW_IMAGE}" \
        /opt/actions-runner/run.sh --version 2>&1; then
    log "ERROR: Smoke-check FAILED for ${NEW_IMAGE}." >&2
    log "       :current is unchanged. ${NEW_IMAGE} remains in local storage for inspection." >&2
    log "       Run 'podman image inspect ${NEW_IMAGE}' to investigate." >&2
    exit 1
fi

log "Smoke-check passed."

# ---------------------------------------------------------------------------
# Promote: retag current → previous, new → current.
# Both retag operations use the same underlying layers; no data is duplicated.
# ---------------------------------------------------------------------------
if podman image exists "${LOCAL_CURRENT}"; then
    log "Retagging ${LOCAL_CURRENT} → ${LOCAL_PREVIOUS} (retained for rollback) …"
    podman tag "${LOCAL_CURRENT}" "${LOCAL_PREVIOUS}"
    # Remove the old :current tag so storage doesn't keep a dangling reference.
    podman rmi --force "${LOCAL_CURRENT}" 2>/dev/null || true
else
    log "WARNING: No existing :current image found; skipping :previous tag (first adoption)."
fi

log "Promoting ${NEW_IMAGE} → ${LOCAL_CURRENT} …"
podman tag "${NEW_IMAGE}" "${LOCAL_CURRENT}"

log "Adoption complete. Next job will run on ${LOCAL_CURRENT}."
log "Rollback image: ${LOCAL_PREVIOUS} (if it existed before this promotion)."
