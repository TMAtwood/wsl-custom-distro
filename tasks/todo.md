# PLAT-181 — Deploy the self-hosted ephemeral Podman runner (in-repo tooling)

Executes the **deferred operational half** of the runner initiative (`docs/runner-handoff.md`
§§7–14). PLAT-178 shipped the runner *image*; this delivers the host bring-up scripts, supervisor
loop, `infra/` runner group, the self-hosted build/publish workflow, and the runbook.

> Implementation authored by **Sonnet 4.6** subagents (per `/goal`), orchestrated here. Physical host
> bring-up (creating the WSL distro, placing the real PAT, first bootstrap build) is an **owner-only
> manual runbook step** — documented in `docs/RUNNER.md`, not executable from here.

## Shared constants (every file uses these verbatim)

| Thing | Value |
| --- | --- |
| GitHub repo | `TMAtwood/wsl-custom-distro` (owner `TMAtwood`) |
| Distro image (GHCR) | `ghcr.io/tmatwood/ubuntu-26.04` |
| Runner image (GHCR) | `ghcr.io/tmatwood/ubuntu-26.04-runner`, moving tags `:current` / `:previous` |
| Local build tags | `localhost/tmatwood/ubuntu-26.04[-runner]:<ver>` (+ `:latest` / `:current`) |
| Runner agent version | `2.335.1` (matches Dockerfile `ARG RUNNER_VERSION`) |
| Host WSL distro | `fcg-runner-host` (dedicated, minimal, systemd on) |
| Runner labels | `self-hosted, fcg-local, wsl-build` |
| Supervisor user | `svc-runner` (system user, no login) |
| Paths | scripts `/opt/fcg-runner`, work `/var/lib/fcg-runner`, PAT `/etc/fcg-runner/pat` (0600 `svc-runner`) |
| Podman socket | `/run/podman/podman.sock` → `CONTAINER_HOST=unix:///run/podman/podman.sock` |
| JIT scope | **repo-scoped** default (`POST /repos/TMAtwood/wsl-custom-distro/actions/runners/generate-jitconfig`); org runner group deferred until Team/Enterprise |

## Plan (checklist)

- [ ] **Host** (`runner/host/*`) — `00-create-host-distro.ps1`, `10-bootstrap-host.sh`,
      `30-autostart.ps1`, `90-bootstrap-build.sh`.
- [ ] **Supervisor** (`runner/supervisor/*`) — `supervisor.sh`, `adopt.sh`, `prune.sh`,
      `supervisor.service`.
- [ ] **Infra** (`infra/*`) — `backend.tf`, `providers.tf`, `variables.tf`, `runner_group.tf`,
      `outputs.tf`, `terraform.tfvars.example`.
- [ ] **Workflow + docs** — `.github/workflows/build-image.yml` (self-hosted build+test+publish on
      `main`), `docs/RUNNER.md` runbook, `runner/README.md`; dedupe `ci.yml` triggers so main builds
      only via `build-image.yml`.
- [ ] **Verify** — shellcheck + shfmt (bash), actionlint + yamllint (workflow), `tofu fmt`/`validate`
      (infra), markdownlint (docs); consistency pass on shared constants.
- [ ] **Ship** — commit, push, PR → main, merge.

## Out of scope (owner-manual / later)

- Physically standing up `fcg-runner-host`, placing the PAT, running the first bootstrap build.
- Removing `docker-compose-github-runner.yml` / `.env.github-runner` — only "once the new runner is
  proven" (not yet deployed); left in place.
- Org-scoped custom runner group — blocked until the org is on GitHub Team/Enterprise.

## Review

### What was built (all 15 files)

- **`runner/host/`** — `00-create-host-distro.ps1` (import minimal `fcg-runner-host` WSL distro,
  systemd on, sparse VHDX), `10-bootstrap-host.sh` (rootful Podman + `podman.socket`, `svc-runner`
  user, `podman-socket` group for least-priv socket access, PAT placeholder 0600), `30-autostart.ps1`
  (Scheduled Task to wake the distro at boot/logon), `90-bootstrap-build.sh` (one-time chicken-and-egg
  build+push on the host engine).
- **`runner/supervisor/`** — `supervisor.sh` (pull-if-newer → adopt → repo-scoped JIT mint → one
  ephemeral `podman run --rm` → loop, SIGTERM-safe), `adopt.sh` (smoke-check + `:current`/`:previous`
  promotion), `prune.sh` (periodic, keep-list excludes current/previous), `supervisor.service`
  (hardened systemd unit, `User=svc-runner`, `After=podman.socket`).
- **`infra/`** — OpenTofu runner group, **guarded `enable_runner_group=false`** → zero resources by
  default (custom groups need Team/Enterprise).
- **`.github/workflows/build-image.yml`** — self-hosted build+test+GHCR-publish on `main`, gated by
  `SELF_HOSTED_AVAILABLE`, with a `publish-status` green gate; **`ci.yml`** push trigger now excludes
  `main` (handled here) to avoid double builds.
- **`docs/RUNNER.md`** + **`runner/README.md`** — operator runbook and tree overview.
- **`.gitignore`** — added Terraform state/tfvars and the PAT file so no secret/state can be committed.

### Orchestration & fixes

- Authored by four **Sonnet 4.6** subagents in parallel (disjoint dirs), orchestrated from the main
  session. Post-authoring fixes by the orchestrator:
  - `supervisor.sh`: added `runner_group_id` (Default `1`) to the JIT payload — repo-scoped
    `generate-jitconfig` requires it (overridable via env for the org group later).
  - `00-create-host-distro.ps1`: normalized param-block indentation to satisfy editorconfig.
  - Marked the `.sh` scripts executable in git.

### Verification

- [x] **pre-commit (all hooks) green** on every file: shellcheck, shfmt, actionlint, yamllint,
      markdownlint, editorconfig, executable-shebang checks, detect-secrets / gitleaks / TruffleHog
      (no PAT leaked), Trivy config, codespell.
- [x] Cross-file consistency: image names (`ghcr.io/tmatwood/...`), labels (`fcg-local,wsl-build`),
      `svc-runner`, socket path — all consistent.
- [ ] `tofu validate` — not run (OpenTofu unavailable in this env; module is guarded to zero
      resources). Run before any `enable_runner_group=true` apply. Manually reviewed: correct.
- [ ] **Owner-manual (cannot be automated):** physically create `fcg-runner-host`, place the real
      PAT, run `90-bootstrap-build.sh`, then `gh variable set SELF_HOSTED_AVAILABLE --body true`.
      Runbook: `docs/RUNNER.md`.
