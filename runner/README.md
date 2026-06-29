# runner/

Scripts that provision and operate the self-hosted GitHub Actions runner for this repo.

## Tree

```text
runner/
├── host/
│   ├── 00-create-host-distro.ps1   — Provision fcg-runner-host WSL2 distro (Windows, elevated)
│   ├── 10-bootstrap-host.sh        — Install rootful Podman, create svc-runner user, configure socket
│   ├── 30-autostart.ps1            — Task Scheduler task: start host distro at Windows boot
│   └── 90-bootstrap-build.sh       — One-time: build first runner image directly on host engine
└── supervisor/
    ├── supervisor.sh               — Main loop: pull-if-newer → JIT config → run one container → repeat
    ├── adopt.sh                    — Smoke-check and promote a new image to :current
    ├── prune.sh                    — Periodic image/cache prune (excludes :current and :previous)
    └── supervisor.service          — systemd unit that runs supervisor.sh as svc-runner
```

## Two operating modes

**Run mode (default).** The runner image is already in local Podman storage. For each CI
job the supervisor mints a JIT registration token, starts one ephemeral container from the
local image, lets the baked-in agent take the job, then destroys the container. Nothing is
rebuilt; nothing is cleaned — the immutable image is the clean slate.

**Image-build mode (this repo only).** When `build-image.yml` runs on `main`, the ephemeral
container receives a host-socket mount (`CONTAINER_HOST=unix:///run/podman/podman.sock`).
`bash build.sh` and `bash run_tests.sh` then execute on the persistent host engine with the
warm 35 GB layer cache, and the new images are pushed to GHCR. The supervisor adopts the
new version between jobs via `adopt.sh`.

## Further reading

- **`docs/RUNNER.md`** — operator runbook: bootstrap, PAT rotation, adopt/rollback, disk
  maintenance, security notes, troubleshooting.
- **`docs/runner-handoff.md`** — full design: architecture decisions, the two operating
  modes in depth, bootstrap sequence, security model, and acceptance criteria.
