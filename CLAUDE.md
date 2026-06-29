# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

There is **no application code here.** This repo builds a single ~1300-line `Dockerfile` into an
Ubuntu 26.04 container image packed with 100+ dev tools, then exports that image to a tarball and
imports it as a WSL2 distro (`tmatwood-ubuntu-26.04`). "The product" is the image. Almost all work
is editing the `Dockerfile`, its baked-in `config/` files, and the `tests.yaml` test suite.

## Working agreement (from `docs/CLAUDE.md`)

The owner expects a strict workflow for non-trivial changes:

1. Think → read relevant files → write a plan to `tasks/todo.md` as a checklist.
2. **Get the plan verified before writing code.**
3. Work the checklist, marking items done; give a high-level note per step.
4. Keep every change as small and isolated as possible — minimal blast radius, no large refactors.
5. Root-cause fixes only; no temporary patches.
6. End with a review section in `tasks/todo.md` summarizing what changed.

## Core commands

| Task | Command (WSL/bash, preferred) | Windows (PowerShell) |
| --- | --- | --- |
| Build image | `bash build.sh` | `.\build.ps1` |
| Run all tests | `bash run_tests.sh` | `.\run_tests.ps1` |
| Test a specific image | `IMAGE_NAME=localhost/tmatwood/ubuntu-26.04:0.1.0 bash run_tests.sh` | `.\run_tests.ps1 -ImageName ...` |
| Run all lint/security hooks | `pre-commit run --all-files` | — |
| Run one hook | `pre-commit run hadolint --all-files` | — |
| Reproduce CI locally | `act -j build-and-test` | — |
| Import image into WSL | — | `.\setup-wsl.ps1` (run from Windows, as admin) |

- **Build** uses **Podman with `--format docker`** (not Docker), `--platform linux/amd64`, and
  GitVersion for the SemVer tag. Output: `localhost/tmatwood/ubuntu-26.04:<version>` and `:latest`.
  A full build takes ~15–30 min.
- **Tests** are [container-structure-test](https://github.com/GoogleContainerTools/container-structure-test)
  cases in `tests.yaml`, run against the built image. There is no per-test selector — the runner
  executes the whole `tests.yaml`. To narrow scope while iterating, temporarily comment out test
  blocks or point `--config` at a trimmed copy.
- **CI** (`.github/workflows/ci.yml`) builds with **Docker Buildx** (not Podman), versions with
  GitVersion, runs the same `tests.yaml`, and on `main` pushes to `ghcr.io`. `act` runs detect local
  execution and fall back to legacy docker build.

## Dockerfile architecture (the thing you'll edit most)

Six stages, ordered for layer-cache efficiency. **Package managers are installed in stage 3, but the
packages they install land in stages 4–5** — keep that split when adding tools.

1. `base` — apt packages, three-user setup, PPAs, WSL config.
2. `build-tools` — verifies compilers (gcc/g++/make).
3. `package-managers` — installs Homebrew, NVM, git config. **Setup only, no packages yet.**
4. `runtimes` — language runtimes via apt/brew (Python, Node, Java, .NET, ClamAV, browsers).
5. `dev-tools` — CLI tooling via Homebrew (helm, k9s, terraform, trivy, grype, act, …).
6. `final` — Podman config, systemd services, final user setup.

**Three-user model — `USER` switches many times per stage; always track who is active before editing:**

- `root` (UID 0) — system admin, apt installs, service config.
- `linuxbrew` — owns `/home/linuxbrew/.linuxbrew`, runs Homebrew installs.
- `dev` (UID 1001, the default WSL login) — primary dev user; passwordless sudo; in sudo/adm/docker/audio/video.

### When adding a tool

1. Pick the right stage (runtime vs dev-tool) and the right manager (apt / brew / pip / npm).
2. Add a matching case to `tests.yaml` — use `--version` for CLIs, but `which` for GUI apps
   (firefox, vlc, obs, pavucontrol — they need X11/Wayland and can't run `--version` in the test sandbox).
3. Update `README.md`'s tool list, run `pre-commit run --all-files`, then `bash build.sh && bash run_tests.sh`.

### Multi-version runtimes

Several runtimes ship multiple versions selected via `update-alternatives`-backed switcher scripts:

- Python **3.12 / 3.13 / 3.14** (default **3.14**): `/usr/bin/set-python-{12,13,14}.sh`
- Java **8 / 11 / 17 / 21 / 25** (default **21**): `/usr/bin/set-java-{8,11,17,21,25}.sh`
- .NET **8.0 / 9.0**; Node.js via **NVM**.

## Dockerfile constraints that bite

- **No heredocs.** `hadolint`'s parser chokes on `tee file <<'EOF'` with `unexpected '['`. Write
  multi-line files with `printf '...\n...'` instead (see how the switcher scripts and configs are written).
- Suppress intentional lint violations inline with `# hadolint ignore=RULE`. Commonly ignored here:
  `DL3002` (trailing `USER root`), `DL3005` (apt upgrade), `DL3008/3013/3016/3062` (unpinned versions —
  this env intentionally wants latest), `SC2086` (deliberate word-splitting).
- `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` — pipelines fail on any stage's error.
- **Rootful Podman** is used deliberately (rootless breaks `act`'s Docker compatibility). The socket
  is configured in `dev`'s `.bashrc`.
- Several tools are installed from non-26.04 sources because upstream hasn't published a "resolute"
  (26.04) apt suite yet (Azure CLI, PowerShell, HashiCorp, wslu). Expect manual key/repo handling in
  those `RUN` blocks, not clean PPAs.

## Baked-in config

Files under `config/` mirror the target filesystem and are `COPY`'d into the image
(e.g. `config/etc/wsl.conf` → `/etc/wsl.conf`, `config/home/dev/.config/starship.toml` → the dev
user's home). Edit these rather than emitting the same content via `printf` in the Dockerfile.

systemd services baked in: `wsl-vpnkit.service` (VPN network bridging), `make-root-shared.service`,
`clamonacc.service` (ClamAV on-access scan).

## Conventions

- **Line endings: LF everywhere**, except Windows scripts (`.ps1`/`.bat`/`.cmd`) which are CRLF —
  enforced by `.gitattributes` and the `mixed-line-ending` pre-commit hook.
- Versioning is **GitFlow via GitVersion** (`GitVersion.yml`). The `no-commit-to-branch` pre-commit
  hook blocks direct commits to protected branches — work on `feature/*`.
- The pre-commit pipeline runs many scanners (hadolint, dockle, trivy config+image, shellcheck, shfmt,
  actionlint, prettier, ruff, yamllint, markdownlint, gitleaks, trufflehog, detect-secrets); expect
  any Dockerfile/script/YAML edit to be linted on commit.

## Where to read more

- `docs/ARCHITECTURE.md` — detailed system architecture.
- `docs/TESTING.md` — test categories and full tool inventory.
- `docs/TROUBLESHOOTING.md`, `docs/PERFORMANCE.md`, `docs/GITHUB_ACTIONS.md`, `docs/ACT_QUICKSTART.md`.
- `docs/CLAUDE.md` — the working-agreement "commandments" in full.
- `.github/copilot-instructions.md` — overlapping guidance (note: some version numbers there lag the
  Dockerfile; trust the Dockerfile).
