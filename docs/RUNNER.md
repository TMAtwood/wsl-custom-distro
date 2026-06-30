# Runner Operator Runbook

Audience: whoever administers the `fcg-runner-host` WSL2 distro and its supervisor service.
Design background: `docs/runner-handoff.md`.

---

## Architecture recap

The self-hosted runner operates in two distinct modes.

**Run mode (the default — nearly all jobs).** The `ubuntu-26.04-runner` image already exists
in GHCR and in local Podman storage. Each CI job causes the supervisor to mint a JIT
registration token, start one ephemeral container from the local image, let the baked-in
agent take exactly one job, then `--rm` destroy it. Nothing is built; nothing is cleaned
between runs — the immutable image is the clean slate.

**Image-build mode (occasional — this repo only).** When a push lands on `main`, the
`build-image.yml` workflow runs on the self-hosted runner and calls `bash build.sh` via the
persistent host Podman socket. This reuses the warm 35 GB layer cache for an incremental
build, then pushes both images to GHCR. The supervisor adopts the new version between jobs.

Two heavy things, only one is ephemeral:

- **Heavy environment** (100+ baked tools) — ephemeral container, fresh per job.
- **Heavy build cache** (35 GB of layers) — persistent on the host engine, touched only
  during image-build mode.

---

## One-time bootstrap

### Prerequisites

- Windows 11 with WSL2 enabled.
- A large data drive with **≥ 200 GB free** (35 GB image + 2–3× transient build cache +
  two retained image versions + headroom).
- Admin access to the GitHub organisation (to create a fine-grained PAT and set the
  `SELF_HOSTED_AVAILABLE` repository variable).
- The repo checked out locally.

### Step 1 — Create the host distro

From an **elevated PowerShell** session on Windows, run:

```powershell
.\runner\host\00-create-host-distro.ps1
```

This provisions a dedicated minimal WSL2 distro named `fcg-runner-host` with systemd
enabled, a sparse VHDX placed on the large data drive, and `/etc/wsl.conf` set to
`[boot] systemd=true`. The host distro is intentionally small — env parity lives in the
runner *container* (`FROM final`); the host only needs Podman and glue.

### Step 2 — Bootstrap the host (inside the distro)

Enter the host distro (`wsl -d fcg-runner-host`) and run:

```bash
sudo bash /path/to/runner/host/10-bootstrap-host.sh
```

This script:

- Installs rootful Podman and enables `podman.socket` at `/run/podman/podman.sock`.
- Installs `git`, `jq`, `curl`, and a GitVersion runner (for the bootstrap build).
- Creates the `svc-runner` system user (the supervisor account).
- Creates `/opt/fcg-runner` (supervisor scripts), `/var/lib/fcg-runner` (working state),
  and `/etc/fcg-runner/` (secrets directory, `0700 root`).

### Step 3 — Place the fine-grained PAT

Create a **fine-grained PAT** in GitHub with the minimum scope:
`Organization > Self-hosted runners: Read and Write`.

Copy it into the host distro:

```bash
sudo install -m 0600 -o svc-runner -g svc-runner /dev/stdin /etc/fcg-runner/pat <<'ENDPAT'
github_pat_XXXXXXXXXXXXXXXXXXXXXXXXXXXX
ENDPAT
```

**The PAT must never appear in the image or in git.** `gitleaks` and `trufflehog` run on
every commit and will catch any accidental inclusion.

### Step 4 — Enable autostart on boot

WSL2 distros do not start on Windows boot by default. From **elevated PowerShell**, run:

```powershell
.\runner\host\30-autostart.ps1
```

This creates a Task Scheduler task that starts `fcg-runner-host` at logon/startup so
systemd can bring up `podman.socket` and `supervisor.service` automatically.

Verify readiness after a reboot:

```powershell
wsl -d fcg-runner-host -- systemctl is-active podman.socket supervisor.service
```

### Step 5 — Bootstrap-build the first runner image

Hosted runners cannot build this image (≈ 36 GB, above the disk ceiling). The first build
must happen directly on the host engine. Inside `fcg-runner-host`, run:

```bash
sudo -u svc-runner bash /opt/fcg-runner/host/90-bootstrap-build.sh
```

This script clones the repo, runs `bash build.sh && bash run_tests.sh` directly on the host
Podman engine (no container wrapper), then logs in to GHCR and pushes both images, tagging
`ubuntu-26.04-runner:current`. From this point the supervisor self-sustains: subsequent
image-build runs happen inside the ephemeral runner container.

### Step 6 — Enable CI

Set the repository variable that lifts the workflow gate:

```bash
gh variable set SELF_HOSTED_AVAILABLE --body true \
  --repo TMAtwood/wsl-custom-distro
```

The `build-image.yml` and `ci.yml` workflows skip the self-hosted jobs (and remain green)
when this variable is absent or not `'true'`. Set it to `'false'` to take the runner
offline without disabling the workflows.

---

## Day-to-day operations

### How the supervisor works

`supervisor.service` (systemd, running as `svc-runner`) loops continuously:

1. **Pull-if-newer** — `podman pull ghcr.io/tmatwood/ubuntu-26.04-runner:current`. A digest
   check makes this a no-op when the local image matches; only deltas are fetched on an
   actual new push.
2. **Adopt** — if a genuinely new digest is pulled, hand off to `adopt.sh` before the next
   run (see below).
3. **Mint a JIT config** — `POST /orgs/TMAtwood/actions/runners/generate-jitconfig` using
   the PAT. Returns a single-use `encoded_jit_config`.
4. **Run one ephemeral container** — `podman run --rm -e RUNNER_JITCONFIG=<encoded> ...`
   The agent self-registers from the JIT config, takes one job, exits. `--rm` destroys it.
5. Loop.

Build-mode jobs receive an additional socket mount so `CONTAINER_HOST` inside the container
reaches the host engine. Run-mode jobs receive no socket.

### Adopt — promoting a newly built image

After `build-image.yml` pushes a new version, the supervisor pulls it and calls
`runner/supervisor/adopt.sh` before the next job starts. The adopt script:

1. **Smoke-check** — `podman run --rm <new> /opt/actions-runner/run.sh --version`. An image
   that builds but cannot launch the agent is the failure mode this catches.
2. On **pass** — retag `:current → :previous`, `<new> → :current`. Next job runs on the new
   image.
3. On **fail** — leave `:current` intact, surface an error loudly, retain `<new>` for
   inspection. The runner stays up on the prior version.

Adoption is always between jobs, never mid-job.

### Rollback

If `:current` is broken after adoption, restore the prior version:

```bash
# Inside fcg-runner-host, as svc-runner
systemctl stop supervisor.service
podman tag ghcr.io/tmatwood/ubuntu-26.04-runner:previous \
           ghcr.io/tmatwood/ubuntu-26.04-runner:current
systemctl start supervisor.service
```

Both `:current` and `:previous` are always kept on the host (and in GHCR). `prune.sh`
explicitly excludes them. If both are ever lost, recovery requires a manual host build via
`90-bootstrap-build.sh`.

---

## PAT rotation

The PAT at `/etc/fcg-runner/pat` is the sole long-lived secret. Rotate it on a documented
cadence (recommend: 90 days) or immediately if a potential leak is detected.

1. Create a replacement fine-grained PAT (same scope: org self-hosted runners read/write).
2. Write it into the host:

   ```bash
   sudo install -m 0600 -o svc-runner -g svc-runner /dev/stdin /etc/fcg-runner/pat <<'ENDPAT'
   github_pat_NEW_VALUE_HERE
   ENDPAT
   ```

3. Revoke the old PAT in GitHub.
4. Verify the supervisor picks it up on the next loop iteration (no restart needed — the
   script reads the file on each JIT-config request).

---

## Disk maintenance

### Periodic prune

Run `runner/supervisor/prune.sh` periodically (e.g. via a systemd timer or cron) to reclaim
space from dangling images and build-cache layers:

```bash
sudo -u svc-runner bash /opt/fcg-runner/supervisor/prune.sh
```

The script prunes dangling images and trims build cache to a ceiling while **explicitly
excluding** `:current`, `:previous`, and their `final` parent layers. Never use
`podman system prune -af` — it will remove images needed for recovery.

Standing rule: always retain enough disk to rebuild from `:previous`.

### VHDX compaction (reclaim Windows host space)

Podman deletions shrink the ext4 filesystem inside the VHDX but do not automatically shrink
the VHDX file on the Windows host. Compact periodically:

```powershell
# 1. Stop the host distro so the VHDX is not open.
wsl --shutdown

# 2a. Compact using Optimize-VHD (requires Hyper-V tools; fastest):
Optimize-VHD -Path "D:\WSL\fcg-runner-host\ext4.vhdx" -Mode Full

# 2b. Alternatively, use diskpart (no Hyper-V required):
#   diskpart
#   select vdisk file="D:\WSL\fcg-runner-host\ext4.vhdx"
#   compact vdisk
#   exit

# 3. Restart the host distro.
wsl -d fcg-runner-host -- systemctl is-active podman.socket
```

Budget the full disk maintenance window: `wsl --shutdown` terminates all running WSL
instances, including your daily `tmatwood-ubuntu-26.04` distro.

---

## Security notes

These apply even on a single-tenant private setup.

- **Runner group scoped** — the GitHub Actions runner group has `visibility = "selected"` and
  an explicit `selected_repository_ids` list (managed in `infra/`). Only listed repos can
  dispatch jobs to this runner.
- **PAT** — fine-grained, org self-hosted runners read/write only; `0600`, owned by
  `svc-runner`; off-image, off-git. Rotate on a documented cadence. The only long-lived
  secret.
- **JIT + ephemeral + immutable image** — fresh container filesystem per job; no carryover
  between jobs. The image is the clean slate.
- **Socket coupling is the exception, not the rule.** The rootful Podman socket is mounted
  only for image-build jobs (`build-image.yml`). Mounting it is root-equivalent access to
  the host engine — a compromised build job could poison the host layer cache. Acceptable
  for solo/private; must remain a rare, explicit exception. Run-mode jobs get no socket.
- **Container runs as `dev`** — the image's primary dev user (passwordless sudo, docker
  group). Trusted because it is your own image on your own box. Documented for auditability.
- **Never lose both `:current` and `:previous`** — that is the one unrecoverable state
  (no hosted fallback for a 36 GB build). `prune.sh` always excludes both.

---

## Troubleshooting

### Supervisor fails to mint a JIT config

```
Error: 401 Unauthorized
```

The PAT has expired or been revoked. Rotate it (see PAT rotation above).

```
Error: runner group not found / runner_group_id unknown
```

The runner group ID in the supervisor config does not match the group in GitHub. Check
`infra/` outputs (`tofu output runner_group_id`) and update `/opt/fcg-runner/supervisor.sh`.

### `podman info` fails in the build workflow

```
Error: unable to connect to Podman socket
```

The supervisor did not mount the socket for this job — or `podman.socket` is not active on
the host. Check inside `fcg-runner-host`:

```bash
systemctl status podman.socket
ls -la /run/podman/podman.sock
```

If the socket does not exist, start it:

```bash
systemctl start podman.socket
```

For the socket to be mounted in the build container, verify the supervisor's `podman run`
command includes `-v /run/podman/podman.sock:/run/podman/podman.sock` for build-mode jobs.

### Host distro did not start after reboot

Check the Task Scheduler task created by `30-autostart.ps1`:

```powershell
Get-ScheduledTask -TaskName "Start fcg-runner-host" | Select-Object State, LastRunTime
```

Start the distro manually if needed:

```powershell
wsl -d fcg-runner-host -- echo ready
```

Then verify systemd services:

```bash
wsl -d fcg-runner-host -- systemctl status podman.socket supervisor.service
```

### Disk full — build cache overflow

If `bash build.sh` fails with no-space errors, first check disk usage:

```bash
podman system df
df -h /var/lib/containers
```

Run `prune.sh` to trim dangling images and excess build cache, then compact the VHDX
(see Disk maintenance above). If still tight, verify the VHDX is on the large data drive
(not the Windows system drive).

### Adopt fails — smoke-check rejected the new image

The new image built and was pushed to GHCR but the agent binary cannot execute:

```
Error: runner agent smoke-check failed
```

Inspect the new image:

```bash
podman run --rm ghcr.io/tmatwood/ubuntu-26.04-runner:<ver> \
  /opt/actions-runner/run.sh --version
```

The runner stays on `:current` (prior version) until the issue is fixed and a new version
is built and pushed. The broken image remains as `<ver>` for inspection; it is not tagged
`:current` or `:previous`.

---

## Quick reference

| Path | Purpose |
| --- | --- |
| `/etc/fcg-runner/pat` | Fine-grained PAT (0600, svc-runner) |
| `/opt/fcg-runner/` | Supervisor scripts deployed from `runner/` |
| `/var/lib/fcg-runner/` | Runtime state (current version tracking) |
| `/run/podman/podman.sock` | Rootful Podman socket (build-mode mount point) |

| Image tag | Meaning |
| --- | --- |
| `ghcr.io/tmatwood/ubuntu-26.04-runner:current` | The version the supervisor runs |
| `ghcr.io/tmatwood/ubuntu-26.04-runner:previous` | Retained for rollback |
| `ghcr.io/tmatwood/ubuntu-26.04-runner:<ver>` | Immutable versioned release |
| `ghcr.io/tmatwood/ubuntu-26.04:current` | Matching distro image |

| Command | Effect |
| --- | --- |
| `gh variable set SELF_HOSTED_AVAILABLE --body true` | Enable CI gate |
| `gh variable set SELF_HOSTED_AVAILABLE --body false` | Take runner offline (workflows stay green/skipped) |
| `systemctl restart supervisor.service` | Restart the supervisor loop |
| `wsl --shutdown && Optimize-VHD -Path ... -Mode Full` | Compact VHDX |
