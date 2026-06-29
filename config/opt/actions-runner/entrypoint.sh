#!/usr/bin/env bash
# ============================================================================
# JIT entrypoint for the baked GitHub Actions runner agent.
# ============================================================================
# This is PID 1 of the ephemeral runner container. It consumes an encoded
# Just-In-Time (JIT) config from the environment and hands control to the
# agent, which self-registers, takes exactly one job, and exits. JIT mode
# skips config.sh entirely — there is no persistent registration.
# ============================================================================

set -euo pipefail

if [[ -z "${RUNNER_JITCONFIG:-}" ]]; then
  echo "ERROR: RUNNER_JITCONFIG is empty or unset." >&2
  echo "       This image expects an encoded JIT config (from generate-jitconfig)" >&2
  echo "       passed via the RUNNER_JITCONFIG environment variable." >&2
  exit 1
fi

exec /opt/actions-runner/run.sh --jitconfig "${RUNNER_JITCONFIG}"
