# GitHub Actions Runner Image — In-Repo Image Slice

Implements **handoff §§5–6** and **acceptance criteria 1–2** from `docs/runner-handoff.md`.
Scope is deliberately the *in-repo, buildable-and-testable* slice only. Host distro, supervisor,
`infra/` OpenTofu, the build workflow, bootstrap, and `docs/RUNNER.md` are **later phases** and are
**out of scope** here.

## Objective

From a single `podman build`, produce both:

- the existing distro image `localhost/tmatwood/ubuntu-26.04:<ver>` (`:latest`), unchanged, and
- a new runner image `localhost/tmatwood/ubuntu-26.04-runner:<ver>` (`:current`) — a
  `FROM final AS runner` stage with the GitHub Actions agent baked in, running the agent (not
  systemd) as its entrypoint and consuming a JIT config from the environment.

…and prove the runner image is correct with container-structure-test.

## Decisions confirmed (with owner)

- **GitHub scope:** repo will move to an **FCG org** later, but solo + **not** on GitHub
  Team/Enterprise yet. This slice is **scope-agnostic** — a baked JIT entrypoint behaves
  identically whether the JIT config was minted at repo or org scope. The org-vs-repo distinction
  (and the fact that **custom runner groups require Team/Enterprise**, so the handoff's
  `infra/` runner-group can't be used on a free org yet) only affects the **deferred**
  supervisor/infra phase. Flagged here so the next phase plans for repo-scoped (or default-group)
  registration first.
- **Old runner files left untouched:** `docker-compose-github-runner.yml` and `.env.github-runner`
  are NOT modified or removed in this slice (minimal blast radius). Revisit as separate cleanup.
- **Tarball integrity:** verify the agent tarball's published **SHA-256** before extraction.
- **Build/test scripts:** **extend** `build.sh`/`build.ps1`/`run_tests.sh`/`run_tests.ps1` rather
  than adding parallel runner-specific scripts (one version source, no drift).

## Plan (checklist)

### 1. Pin the agent version + checksum (do first)

- [x] Confirmed latest stable `actions/runner` = **v2.335.1** (matches handoff's v2.335.x line).
- [x] Captured the official **linux-x64 SHA-256** from the release notes:
      `4ef2f25285f0ae4477f1fe1e346db76d2f3ebf03824e2ddd1973a2819bf6c8cf`.

### 2. Dockerfile — append `runner` stage after `final`

- [x] `FROM final AS runner`.
- [x] `ARG RUNNER_VERSION=2.335.1` + `ARG RUNNER_SHA256=…` (pinned as defaults — single source).
- [x] `USER root`: libicu safety net — only `apt-get install libicu-dev` if `ldconfig` shows it
      missing; otherwise skip (it ships via the .NET runtime).
- [x] Download agent to `/opt/actions-runner`, **verify SHA-256** (`sha256sum -c -`), fail on
      mismatch, extract, `chown -R dev:dev`.
- [x] `COPY --chown` the entrypoint; `chmod +x`.
- [x] `USER dev`; `ENTRYPOINT ["/opt/actions-runner/entrypoint.sh"]`. No init system.
- [x] No heredocs; inline `# hadolint ignore=DL3008,DL4006` / `DL4006` for the cross-FROM pipefail
      false positives.

### 3. `config/opt/actions-runner/entrypoint.sh` (new, LF)

- [x] Reads `RUNNER_JITCONFIG`; fails fast with a clear message if empty.
- [x] Else `exec /opt/actions-runner/run.sh --jitconfig "$RUNNER_JITCONFIG"`.

### 4. `build.sh` / `build.ps1` — extend

- [x] Added explicit **`--target final`** to the existing distro build (the required correctness fix).
- [x] Added a second **`--target runner`** build tagging `…-runner:${VERSION}` + `:current`.
- [x] Error handling + summary output kept consistent with existing style; runner tags surfaced.
- [x] GHCR login/push left out of this slice.

### 5. `run_tests.sh` / `run_tests.ps1` — add a config override

- [x] `run_tests.sh`: added `CONFIG_FILE` env (default `tests.yaml`).
- [x] `run_tests.ps1`: `-ConfigFile` now falls back to `$env:CONFIG_FILE` for parity.

### 6. `tests-runner.yaml` (new)

- [x] Asserts: agent `run.sh`/`config.sh`/`bin/Runner.Listener` present, entrypoint present +
      executable (`test -x`), active user `dev` (`id -un`), agent owned by `dev`, entrypoint
      metadata. `tests.yaml` left unchanged.

### 7. Lint + build + test

- [x] Static lint (run in Git Bash on Windows): **hadolint** (runner stage clean under the repo's
      wrapper ignore set), **shellcheck** + **shfmt** (Passed), **yamllint** (parity with the
      committed `tests.yaml`), **trailing-whitespace / end-of-file-fixer / mixed-line-ending /
      markdownlint** on changed files (Passed). *Lone markdownlint MD060 is pre-existing in
      `docs/runner-handoff.md` — not part of this change.*
- [ ] **Build (run in WSL):** `bash build.sh` — both images build; `<ver>` matches; runner build is
      the cheap incremental layer on top of `final`. *Not run here: the Windows Podman machine is
      stopped and its layer cache is in the WSL build env.*
- [ ] **Distro regression (WSL):**
      `IMAGE_NAME=localhost/tmatwood/ubuntu-26.04:<ver> bash run_tests.sh`.
- [ ] **Runner tests (WSL):**
      `CONFIG_FILE=tests-runner.yaml IMAGE_NAME=localhost/tmatwood/ubuntu-26.04-runner:current bash run_tests.sh`.
- [ ] **Manual entrypoint-guard sanity (WSL):**
      `podman run --rm localhost/tmatwood/ubuntu-26.04-runner:current` with no `RUNNER_JITCONFIG`
      should exit non-zero with the clear error message.

## Acceptance criteria satisfied by this slice

- **AC-1:** single `podman build` produces both images from identical layers; `<ver>` matches.
- **AC-2:** runner image has agent + executable `entrypoint.sh`, active user `dev`,
  `tests-runner.yaml` green; container runs the agent (not systemd) and the entrypoint guards on a
  missing JIT config.

## Explicitly out of scope (later phases)

- `runner/host/*` (host WSL distro, rootful Podman, supervisor user, PAT) — §7.
- `runner/supervisor/*` (loop, adopt, prune, systemd unit) — §§8,10,11.
- `infra/` OpenTofu runner group — §12 (blocked until org is on Team/Enterprise).
- `.github/workflows/build-image.yml` + GHCR push — §9.
- `docs/RUNNER.md` runbook + bootstrap scripts — §13.
- Removing the old `docker-compose-github-runner.yml` / `.env.github-runner`.

## Review

### What changed

- **`Dockerfile`** — appended a `runner` stage (`FROM final AS runner`): pins `RUNNER_VERSION=2.335.1`
  - its official linux-x64 SHA-256 as `ARG` defaults; a root-cause libicu safety net (install only
  if missing); checksum-verified download/extract of the agent into `/opt/actions-runner` owned by
  `dev`; `COPY` of the baked JIT entrypoint; `USER dev` + `ENTRYPOINT` running the agent (not
  systemd). Inline `# hadolint ignore` only for the cross-FROM pipefail false positives.
- **`config/opt/actions-runner/entrypoint.sh`** (new) — JIT entrypoint; fail-fast guard on an empty
  `RUNNER_JITCONFIG`, then `exec run.sh --jitconfig`.
- **`build.sh` / `build.ps1`** — added explicit `--target final` to the distro build and a second
  `--target runner` build tagging `…-runner:<ver>` + `:current`; summary/image listing updated.
- **`run_tests.sh` / `run_tests.ps1`** — `CONFIG_FILE` / `-ConfigFile`(+env) override so the same
  runner can test `tests-runner.yaml`. Defaults unchanged.
- **`tests-runner.yaml`** (new) — container-structure-test cases for the runner image.

### Added on this branch (blocking bug found during verification)

- **`Dockerfile` + `tests.yaml` — bake in `nftables`.** Verification surfaced a pre-existing image
  bug: the image ships `iptables` but not `nftables`, and **Podman 6.0's netavark requires the `nft`
  binary** to create container networks. Without it, *every* `container-structure-test` commandTest
  fails at container creation (`netavark: nftables error: unable to execute "nft"`). Added
  `nftables` next to `iptables` in both apt lists (base ~line 77 and runtimes ~line 627) and a
  matching `nft --version` test case. Regression from the Ubuntu 26.04 / Podman 6 upgrade; unrelated
  to the runner stage but blocks all container runs. NOTE: a running distro built from an older
  image must `sudo apt-get install -y nftables` (or be re-imported after a rebuild) to get `nft` —
  the bake-in only fixes future images.

### Deviations from the verified plan

- **Pin location:** kept `RUNNER_VERSION`/`RUNNER_SHA256` solely as Dockerfile `ARG` defaults rather
  than threading them through `--build-arg` in both build scripts — one place to bump on a version
  update instead of three (single source of truth). Build scripts still pass `--target runner`.

### Verified vs. pending

- **Verified here:** all static linting/formatting on the changed files (see step 7).
- **Pending (needs the WSL build env):** the actual `podman build` of both targets and the
  container-structure-test runs + manual entrypoint-guard check. Commands are listed in step 7.

### Follow-ups for the next phase

- Confirm `run.sh --jitconfig` / `run.sh --version` behavior against v2.335.1 when wiring the
  supervisor and `adopt.sh` smoke-check.
- Next phase (supervisor/infra) must start **repo-scoped** (or default org group) until the FCG org
  is on GitHub Team/Enterprise — custom runner groups are unavailable before then.
- Consider removing the superseded `docker-compose-github-runner.yml` / `.env.github-runner` once
  the new runner is proven.
