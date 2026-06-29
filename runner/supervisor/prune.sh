#!/usr/bin/env bash
# ============================================================================
# prune.sh — Periodic image/cache prune for the FCG runner host.
# ============================================================================
# Run PERIODICALLY (e.g. weekly via systemd timer or cron).
# NOT per-job — run-mode is cleanup-free: --rm + immutable image is the slate.
#
# Removes dangling (untagged, unreferenced) images and prune stopped
# containers. Checks storage against a ceiling and warns if over.
#
# KEEP-LIST — never prune these images or any layer they depend on:
#   localhost/tmatwood/ubuntu-26.04-runner:current
#   localhost/tmatwood/ubuntu-26.04-runner:previous
#   localhost/tmatwood/ubuntu-26.04:current     (final parent of runner:current)
#   localhost/tmatwood/ubuntu-26.04:previous    (final parent of runner:previous)
#
# Safety rule: never run 'podman system prune -af'. That would destroy the
# 35 GB build cache AND the retained runner versions, leaving no recovery path
# (there is no hosted fallback — see docs/RUNNER.md §Recovery).
#
# VHDX compaction note:
#   Pruning images frees inodes/layers inside the WSL2 distro but does NOT
#   shrink the VHDX file on the Windows host. To reclaim host disk space after
#   a large prune, compact the VHDX manually — see docs/RUNNER.md (requires
#   `wsl --shutdown` then `Optimize-VHD` or `diskpart`). This is a separate,
#   Windows-side, manual step; it is NOT automated here.
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Warn (but do not abort) if Podman storage exceeds this threshold.
readonly CACHE_CEILING_GIB=50

# Images whose layers must never be pruned.
readonly -a KEEP_IMAGES=(
    "localhost/tmatwood/ubuntu-26.04-runner:current"
    "localhost/tmatwood/ubuntu-26.04-runner:previous"
    "localhost/tmatwood/ubuntu-26.04:current"
    "localhost/tmatwood/ubuntu-26.04:previous"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[prune] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2; }

image_exists() {
    podman image exists "$1" 2>/dev/null
}

# Approximate storage used by Podman's storage root, in GiB.
storage_gib() {
    local kb=0
    if [[ -d /var/lib/containers/storage ]]; then
        kb="$(du -sk /var/lib/containers/storage 2>/dev/null | awk '{print $1}')" || kb=0
    fi
    echo $(( ${kb:-0} / 1024 / 1024 ))
}

# ---------------------------------------------------------------------------
# Verify keep-list before pruning
# ---------------------------------------------------------------------------
log "Verifying keep-list …"
for img in "${KEEP_IMAGES[@]}"; do
    if image_exists "${img}"; then
        local_id
        local_id="$(podman image inspect --format '{{.Id}}' "${img}" 2>/dev/null | cut -c1-12)"
        log "  KEEP  ${img}  (id: ${local_id}…)"
    else
        log "  NOTE  ${img} not present in local storage (skipped)."
    fi
done

# ---------------------------------------------------------------------------
# Step 1: Prune dangling (untagged, unreferenced) images.
#
# Dangling images are leftover intermediate layers from builds that were
# superseded. They have no tag and no container referencing them.
# 'podman image prune' without -a only removes dangling images — safe.
#
# The keep-list images cannot be dangling (they are tagged), so this step
# cannot remove them regardless.
# ---------------------------------------------------------------------------
log "Pruning dangling images (untagged, unreferenced) …"
if ! podman image prune --force 2>&1; then
    log "WARNING: 'podman image prune' returned non-zero; continuing."
fi

# ---------------------------------------------------------------------------
# Step 2: Prune stopped containers.
#
# Ephemeral --rm containers are destroyed on exit, so this is belt-and-
# suspenders for any containers left behind by crashes or manual runs.
# ---------------------------------------------------------------------------
log "Pruning stopped containers …"
if ! podman container prune --force 2>&1; then
    log "WARNING: 'podman container prune' returned non-zero; continuing."
fi

# ---------------------------------------------------------------------------
# Step 3: Report storage and warn if above ceiling.
# ---------------------------------------------------------------------------
current_gib="$(storage_gib)"
log "Current Podman storage: ~${current_gib} GiB (ceiling: ${CACHE_CEILING_GIB} GiB)."

if [[ "${current_gib}" -gt "${CACHE_CEILING_GIB}" ]]; then
    log "WARNING: Storage (${current_gib} GiB) exceeds ceiling (${CACHE_CEILING_GIB} GiB)."
    log "         This is expected when the build cache holds warm layers."
    log "         To inspect: 'podman system df' and 'podman image ls'"
    log "         To free more: manually remove unused TAGGED images that are"
    log "         NOT in the keep-list above (old version tags, test images, etc.)."
    log "         To compact the VHDX: see docs/RUNNER.md (Windows-side step)."
fi

log "Prune complete."
