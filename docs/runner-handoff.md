# Handoff: Self-Hosted Ephemeral Podman Runner (tandem-built, in-repo)

**Audience:** Claude Code, working **inside this repo** (`tmatwood-ubuntu-26.04` Dockerfile project).
**Owner:** Tom (FCG).
**Status:** Final design. Supersedes earlier drafts. Read in full before any code.

> **Follow this repo's working agreement first** (`docs/CLAUDE.md`): think → read the relevant files → write a plan to `tasks/todo.md` as a checklist → **get the plan verified before writing code** → work the checklist with minimal blast radius → root-cause only → end with a review section. This handoff is the *what/why*; the `tasks/todo.md` plan is the *how*, approved before implementation.

---

## 1. The core idea (read this first — it frames everything)

There are **two operating modes**, and they are not the same frequency:

- **Run mode (the default, ~all the time).** The heavy image already exists in GHCR and in local Podman storage. A CI job means: instantiate a **fresh ephemeral container** from that **immutable image**, let the **baked-in JIT agent** take exactly one job, then `--rm` destroy it. Next job = another fresh clone of the *same* image. **Nothing is built. Nothing is cleaned between runs** — the immutable image *is* the clean slate, and destroying the container is the cleanup. This is how every FCG repo and every non-build job uses the runner.

- **Image-build mode (occasional — only this repo).** This repo's *product is the image itself*, so validating a Dockerfile change requires building the image, and **hosted runners can't (≈30 GB ceiling)**. So this one repo's build job runs on the self-hosted box and delegates `podman build` to the **persistent host engine over the socket**, reusing the warm 35 GB layer cache. A tool change in stage 5 rebuilds stages 5–7, not 1–4 — **incremental, not the 20–30 min cold build**. When green, the new image is pushed to GHCR and becomes the next runner image.

> The agent is **baked into the image ahead of time** (the tandem `runner` target, §5). The pulled image is run-ready; nothing is injected at runtime. The supervisor just starts the agent with a fresh JIT config.

So "don't rebuild the 20-minute image every time" is satisfied structurally: **almost nothing builds — it pulls and runs**; the rare rebuild is warm/incremental and confined to this repo.

---

## 2. The model (keep this picture in your head)

```
Windows workstation
└─ WSL2 host distro  "fcg-runner-host"  (dedicated, minimal, systemd on)
   ├─ rootful Podman engine  ← persistent: holds local images + the 35 GB build cache
   │     └─ ubuntu-26.04-runner:current  (pulled from GHCR; reused every run)
   ├─ supervisor.service (systemd)  ← only long-lived process besides the engine
   │     loop:  pull-if-newer (cheap digest check)
   │            → mint JIT config (PAT)
   │            → `podman run --rm` ONE ephemeral container from the local image
   │            → container exits & is destroyed
   │            → loop
   └─ PAT file (0600, supervisor-user-only)

   ephemeral container (one job, then gone) — RUN MODE
   └─ baked agent runs as `dev`; job runs fully inside; no socket, no cleanup

   ephemeral container (one job, then gone) — IMAGE-BUILD MODE (this repo only)
   └─ same image, but CONTAINER_HOST → host engine socket, so
      `bash build.sh` / `bash run_tests.sh` execute on the HOST engine (warm cache)
      → push new version to GHCR
```

Two distinct heavy things, only one is ephemeral:

- **Heavy *environment*** (100+ baked tools) → ephemeral container, fresh per job. The point.
- **Heavy *build cache*** (35 GB of layers) → persistent on the host engine, touched only in image-build mode, never inside a throwaway container.

---

## 3. Decisions locked (do not revisit without flagging)

| # | Decision | Why |
| --- | --- | --- |
| 1 | **Pull-and-run is the default**; the image is immutable, the container is disposable (`--rm`) | No per-build image rebuild, no per-job cleanup. The image is the clean slate. |
| 2 | **Runner image = a `runner` stage `FROM final`**, agent baked in, built in the **same `podman build`** as the distro | Structural zero-drift: CI env == shipped env, same layers, same invocation. Pulled image is run-ready. |
| 3 | **Ephemeral containers** via **JIT config** (`generate-jitconfig` → `run.sh --jitconfig`) | Clean runner FS per job; no carryover/persistence surface. |
| 4 | **Persistent rootful Podman engine** on a dedicated WSL2 host distro holds the local image + cache | Reuse the same local image every run; keep the 35 GB cache warm for the occasional rebuild. Podman (not Docker) per repo's deliberate rootful-Podman choice. |
| 5 | **Only the image-build job touches the host engine over the socket**; all run-mode jobs are self-contained | Socket coupling is the rare exception, not the norm. |
| 6 | **GHCR is the promotion/distribution channel**: build pushes new version; supervisor **pull-if-newer**, else runs local; previous version pinned for rollback | Cleaner than local tag juggling; works for recovery and any future second host. |
| 7 | **Leapfrog, no hosted fallback** — but only when *this repo* cuts a new image version | Hosted can't build (30 GB). `vN` runner builds/tests `vN+1`; promotes on green. Not a per-commit event for other repos. |
| 8 | **Fine-grained PAT**, org **self-hosted runners: read/write**, `0600` host-only | Minimum persistent secret to mint JIT configs. Off-image, off-git. |
| 9 | **Everything in this repo**: `runner` build target + a `runner/` ops tree | "Build in tandem" only holds if they build together. |

---

## 4. Files to add (additions only — minimal blast radius)

```
.
├─ Dockerfile                         # ADD a `runner` stage FROM final (§5)
├─ build.sh / build.ps1               # EXTEND to also build --target runner (§6)
├─ tests-runner.yaml                  # NEW: container-structure-test cases for the runner image (§6)
├─ config/
│  └─ opt/actions-runner/entrypoint.sh # NEW: COPY'd into runner stage; JIT entrypoint (§5)
├─ runner/
│  ├─ host/
│  │  ├─ 00-create-host-distro.ps1    # dedicated WSL2 host distro: systemd, sparse VHD, relocate VHDX
│  │  ├─ 10-bootstrap-host.sh         # rootful podman + socket + supervisor user + deps + PAT
│  │  ├─ 30-autostart.ps1             # Task Scheduler: start host distro at boot (WSL doesn't auto-start)
│  │  └─ 90-bootstrap-build.sh        # ONE-TIME: build the first runner image on the host (§13)
│  ├─ supervisor/
│  │  ├─ supervisor.sh                # loop: pull-if-newer → jitconfig → run one → destroy → loop
│  │  ├─ adopt.sh                     # pull new version, smoke-check, set :current, keep :previous
│  │  ├─ prune.sh                     # PERIODIC image/cache prune, EXCLUDING current+previous (§11)
│  │  └─ supervisor.service           # systemd unit (or Podman Quadlet)
│  └─ README.md
├─ infra/                             # OpenTofu — just the runner group (§12)
│  ├─ backend.tf  providers.tf  variables.tf  runner_group.tf  outputs.tf
│  └─ terraform.tfvars.example
├─ docs/RUNNER.md                     # runbook: bootstrap, adopt/rollback, rotate PAT, disk (§§10,13)
└─ .github/workflows/build-image.yml  # self-hosted build/test/publish (§9); ci.yml stays for non-build checks
```

> Respect repo conventions in every file: **LF** except `.ps1`/`.bat`/`.cmd` (CRLF); **no heredocs** in the Dockerfile (`printf`, not `tee <<EOF`); inline `# hadolint ignore=RULE`; **`feature/*`** branch (the `no-commit-to-branch` hook blocks protected branches); full pre-commit scanner suite runs on commit.

---

## 5. Dockerfile — the `runner` stage (only product-image change)

After `final`:

- `FROM final AS runner`
- `USER root`: install only what the agent needs that isn't already present (`libicu` is the usual gap — verify; the image is tool-heavy). Pin a `RUNNER_VERSION` ARG (**v2.335.x** line — confirm latest `actions/runner` at implementation).
- Download + extract the agent to `/opt/actions-runner`, `chown` to `dev`.
- `COPY config/opt/actions-runner/entrypoint.sh /opt/actions-runner/entrypoint.sh` (edit under `config/`, don't `printf` it — matches the "baked config lives in `config/`" rule).
- `USER dev`; `ENTRYPOINT ["/opt/actions-runner/entrypoint.sh"]`

**Critical:** the container runs the **agent as its entrypoint — it does NOT boot systemd.** Being `FROM final` it inherits the baked units (`clamonacc`, `wsl-vpnkit`, `make-root-shared`), but they never start because the container's PID 1 is the agent, not systemd. Intended: VPN bridging / on-access AV / root-share are pointless in ephemeral CI, and scanning is already covered by trivy/grype in pre-commit. Do not add an init system to this stage.

`entrypoint.sh` (in `config/`): read the encoded JIT config from env (`RUNNER_JITCONFIG`), then `exec /opt/actions-runner/run.sh --jitconfig "$RUNNER_JITCONFIG"` (JIT skips `config.sh`; agent self-configures ephemerally and exits after one job). Fail fast with a clear message if empty.

Tags: distro `ghcr.io/<owner>/ubuntu-26.04:<ver>`; runner `ghcr.io/<owner>/ubuntu-26.04-runner:<ver>` (same GitVersion `<ver>`, `-runner` suffix), plus a moving `:current`.

---

## 6. Build / test / publish wiring (image-build mode)

**`build.sh` / `build.ps1`:** after the existing `--target final` build, add a `--target runner` build tagging `ubuntu-26.04-runner:<ver>` + `:current`. Cheap — reuses all of `final`'s cached layers, adds only the agent layer. Same GitVersion `<ver>` across both.

**Tests:** `tests-runner.yaml` (container-structure-test) asserts on the runner image: agent present (`/opt/actions-runner/run.sh`), `entrypoint.sh` present + executable, active user `dev`. Run via the existing pattern (`IMAGE_NAME=...-runner:<ver> bash run_tests.sh` pointed at `tests-runner.yaml`). Distro image keeps `tests.yaml` unchanged.

**Where it executes:** inside the ephemeral container during the build job, but against the **host engine** via `CONTAINER_HOST` (§9) so build/test/login/push run on the host engine with warm cache. `actions/checkout` with `fetch-depth: 0` — **GitVersion needs full history**.

---

## 7. Host distro + persistent Podman engine

`runner/host/00-create-host-distro.ps1`: dedicated **minimal** WSL2 distro `fcg-runner-host` (plain Ubuntu base, *not* an instance of the 35 GB image — env parity lives in the runner *container*, which is `FROM` your image; the host only needs Podman + glue). Keeps cache and any runaway build off your daily `tmatwood-ubuntu-26.04` distro. `/etc/wsl.conf`: `[boot] systemd=true`. Enable sparse VHD, place the VHDX on a large data drive. Budget **≥ 200 GB free** (35 GB image + 2–3× transient build cache + two retained versions sharing most layers + headroom).

`runner/host/10-bootstrap-host.sh` (in-distro, once): install **rootful Podman**; `systemctl enable --now podman.socket` (`/run/podman/podman.sock`); install `git`, `jq`, `curl`, and a GitVersion runner (container or dotnet tool) for bootstrap; create a dedicated **`supervisor`** user; place the **fine-grained PAT** at `/etc/fcg-runner/pat` (`0600`, supervisor-owned). Never in image/git (gitleaks/trufflehog will catch slips).

`runner/host/30-autostart.ps1`: WSL2 distros don't start on boot — Task Scheduler (at startup/logon) starts `fcg-runner-host` so systemd brings up `podman.socket` + `supervisor.service`. Validate readiness after a host reboot.

---

## 8. Supervisor loop (run mode — the common path)

`runner/supervisor/supervisor.sh` (systemd, as `supervisor`), each iteration:

1. **Pull-if-newer:** `podman pull ghcr.io/<owner>/ubuntu-26.04-runner:current`. No-op when the local digest matches; pulls only the delta when a new version was pushed. (On this single host, an image just built locally is already present, so this mainly matters for recovery / future hosts.) On a genuinely new digest, hand off to `adopt.sh` (smoke-check, set `:current`, keep prior as `:previous`).
2. **Mint a JIT config** via the PAT, org-scoped so it lands in the runner group:
   `POST /orgs/<org>/actions/runners/generate-jitconfig` with `name`, `runner_group_id` (from `infra/`), `labels` (`fcg-local,wsl-build`), `work_folder`; capture `.encoded_jit_config`.
3. **Run ONE ephemeral container** from the local image:
   `podman run --rm -e RUNNER_JITCONFIG=<encoded> [socket mount ONLY for image-build jobs] ghcr.io/<owner>/ubuntu-26.04-runner:current`
   Agent self-registers from the JIT config, takes one job, exits; `--rm` destroys it. **No filesystem cleanup needed** — the next run is a fresh clone of the immutable image.
4. Loop.

Notes: one concurrent runner to start (single box; serialize the rare 35 GB build). A second light runner can be added later with a different label. Pass the JIT config by **env var** (off the process list; still readable on a single-tenant box — noted). The PAT is the **one long-lived secret**; rotation documented in `docs/RUNNER.md`.

---

## 9. The build workflow — `.github/workflows/build-image.yml` (image-build mode)

- `runs-on: [self-hosted, fcg-local, wsl-build]`; `permissions: { contents: read, packages: write }`.
- `concurrency:` keyed to the workflow (never two 35 GB builds at once); generous bounded `timeout-minutes`.
- Steps: `actions/checkout@v4` (`fetch-depth: 0`) → set `CONTAINER_HOST=unix:///run/podman/podman.sock` (socket mounted by the supervisor for build jobs); verify `podman --remote info` → `bash build.sh` (both targets, warm host cache) → `bash run_tests.sh` (`tests.yaml`) + runner `tests-runner.yaml` → `podman login ghcr.io` (`GITHUB_TOKEN`) + `podman push` both images (`:<ver>` + `:current`).
- `ci.yml` stays for non-build PR checks (lint/scan). It **cannot** build the image (30 GB), so any job needing the built image is self-hosted; don't try to revive the Buildx build path as a fallback.

**Socket-access detail to solve:** the rootful host socket is root-owned, container runs as `dev` (passwordless sudo per the repo's user model). Grant `dev` access via a group on the mounted socket or sudo'd podman — least-privilege option that works, documented.

---

## 10. Promotion / rollback (`adopt.sh`) — occasional, this repo only

The build job runs on the **current** runner (`vN`) and produces `vN+1`; it can't tear itself down mid-build to become `vN+1`. So it pushes `vN+1` to GHCR (and it's already in host-local storage), and **the supervisor adopts it between jobs**, one job behind. Never mid-job; don't attempt a hot-swap.

`adopt.sh`: **smoke-check first** — `podman run --rm <new> /opt/actions-runner/run.sh --version` (an image that builds but can't launch the agent is the failure that bites). On pass: retag `current → previous`, `<new> → current`. On fail: leave `current`, surface loudly, keep `<new>` for inspection.

**Recovery = the pinned `:previous` on the host** (and in GHCR), **not GitHub.** Always retain `current` + `previous` (runner + their `final` parents) and exclude from prune (§11). If both are ever lost, recovery is a manual host build (`90-bootstrap-build.sh`, §13) — there is no hosted fallback.

---

## 11. Disk maintenance (`prune.sh`) — periodic, NOT per-job

Run-mode needs **no per-job cleanup** (`--rm` + immutable image). The only disk work is **periodic**:

- Prune dangling images and trim build cache to a ceiling, **excluding** `:current`, `:previous` (runner) and their `final` parents. Use an explicit keep-list or labels; never blanket `podman system prune -af`.
- Reclaim VHDX space periodically (sparse VHD doesn't auto-shrink): documented compaction (`wsl --shutdown` + `Optimize-VHD`/`diskpart`).
- Standing rule: never prune to the point you can't rebuild on `:previous`.

---

## 12. `infra/` (OpenTofu — deliberately tiny)

azurerm (Azure Blob) backend per FCG standard; `integrations/github` provider. `github_actions_runner_group "fcg_local"`, **`visibility = "selected"`**, `selected_repository_ids` = the repos allowed to offload (start with this repo; add others as they adopt the runner). Output `runner_group_id` for the supervisor's `generate-jitconfig`. No Azure OIDC/storage — GHCR is the publish target. A one-time manual group is acceptable, but keeping it in `infra/` makes the allowlist reviewable.

---

## 13. Bootstrap (one time)

The runner image is built *from* this project, but building needs a runner that doesn't exist yet, and hosted can't help (30 GB). So bootstrap **once, manually, on the host distro**:

1. Stand up host distro + rootful Podman (`00`, `10`).
2. `runner/host/90-bootstrap-build.sh`: clone the repo on the host, run `bash build.sh && bash run_tests.sh` **directly on the host engine** (no container) → both images; `podman login` + push to GHCR; tag runner `:current`.
3. Create the runner group (`infra/` or manual); place the PAT.
4. Enable `supervisor.service`. From here it self-sustains: subsequent builds run inside the ephemeral runner and adopt on green; everything else just pulls-and-runs.

---

## 14. Security checklist (single-tenant, private repos — still enforce)

- Runner group **`selected`**, explicit repo allowlist.
- **PAT**: fine-grained, org self-hosted-runners **read/write** only, `0600` supervisor-owned, off-image/off-git, rotated on a documented cadence. Sole long-lived secret.
- **JIT + ephemeral + immutable image** → fresh FS per job, no carryover.
- **Socket coupling is the build job's exception, not the rule.** Mounting the rootful Podman socket is root-equivalent to the host engine — a compromised build job could poison the host cache. Acceptable for solo/private; **must be a runbook line.** Run-mode jobs get no socket.
- Container runs as `dev` (heavy image, passwordless sudo, docker group) — trusted because it's your own image on your own box; documented.
- No nested virtualization needed: WSL2 is already the VM; engine + containers live inside that one VM. (A microVM-per-job boundary would fully close the shared-engine caveat but is overkill here.)
- Protect `:current`/`:previous` from prune — losing both is the one unrecoverable state.

---

## 15. Acceptance criteria (verify all before handing back)

1. Single `podman build` produces both `ubuntu-26.04:<ver>` and `ubuntu-26.04-runner:<ver>` from identical layers; `<ver>` matches.
2. Runner image: agent + `entrypoint.sh` present, active user `dev`, `tests-runner.yaml` green; container runs the agent (not systemd) and exits after one job.
3. Host distro dedicated, systemd up, rootful `podman.socket` healthy; survives reboot via Task Scheduler.
4. **Run mode:** supervisor pulls-if-newer (no-op when current), mints a JIT config, runs one ephemeral container that appears **ready** in `<org>` runner settings (labels `fcg-local,wsl-build`), takes a job, is destroyed; a second job runs a fresh container from the **same local image** with **no rebuild and no cleanup step**.
5. **Image-build mode:** `build-image.yml` builds both targets on the host engine over the socket (warm cache demonstrably reused on a second run), tests pass, both images push to GHCR.
6. **Adopt:** after a green build, the supervisor smoke-checks and promotes the new version to `:current`, retains `:previous`; the *next* job runs on the new image. Never mid-job.
7. **Recovery:** with `:current` deliberately broken, a rebuild succeeds on `:previous`; prune never removes `:current`/`:previous`.
8. No secrets in image or git; PAT `0600` host-only.
9. `tofu plan` clean; runner group scoped to the allowlist.

---

## 16. Defaults applied (object now if any are wrong)

Pull-and-run is default; no per-job cleanup. Runner stage `FROM final`, agent baked ahead of time, runs as `dev`, entrypoint **skips all systemd units**. **1 concurrent runner**, label-gated. `tests-runner.yaml` asserts agent+entrypoint+user. GHCR auth via `GITHUB_TOKEN`/`packages: write`. Host distro **dedicated & minimal**. JIT config by env var. Promotion supervisor-driven, one job behind, GHCR as the channel.

---

### Quick reference (verified for this handoff)

- JIT: `POST /orgs/{org}/actions/runners/generate-jitconfig` → `run.sh --jitconfig <encoded>`; ephemeral, one job, no `config.sh`.
- Agent line currently **v2.335.x** — pin `RUNNER_VERSION`, confirm latest at build time.
- Hosted runners cap ~30 GB → cannot build this image; self-hosted is the only builder (hence leapfrog + pinned-prior recovery) — but that's image-build mode only; run mode just pulls and runs.
- Repo guardrails: no Dockerfile heredocs (`printf`), inline `hadolint ignore`, LF (CRLF for Windows scripts), `feature/*`, GitVersion/GitFlow, full pre-commit scanner suite.
