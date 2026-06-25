# Spec: Upgrade Base Image to Ubuntu 26.04 LTS

- **Jira:** [PLAT-165](https://tmatwood.atlassian.net/browse/PLAT-165)
- **Branch:** `feature/PLAT-165` (based on `feature/PLAT-2`)
- **Status:** Draft / Proposed
- **Author:** Tom Atwood
- **Date:** 2026-06-25

---

## 1. Summary

Upgrade the WSL2 custom development distro container image from **Ubuntu 24.04 LTS
(Noble Numbat)** to **Ubuntu 26.04 LTS (Resolute Raccoon)**.

This is primarily a base-image bump (`FROM ubuntu:24.04` → `FROM ubuntu:26.04`),
but because the image pins release-specific apt repositories, ABI-versioned
library packages (the `t64` set), third-party PPAs, and language-runtime
versions, the upgrade touches the `Dockerfile`, the build/import scripts, CI,
the test suite, and the docs. The bulk of the engineering risk is **not** the
base image itself — it is third-party repository/PPA availability for the new
release codename and the Ubuntu 26.04 switch to **`sudo-rs`** as the default
`sudo`.

### Target release facts (verified against Ubuntu release notes)

| Property | 24.04 (current) | 26.04 (target) |
| --- | --- | --- |
| Codename | Noble Numbat | **Resolute Raccoon** |
| apt repo suite name | `noble` | `resolute` |
| Released | 2024-04 | 2026-04-23 |
| Default Python 3 | 3.12 | **3.14** |
| GCC | 14 | **15.2** |
| glibc | 2.39 | **2.43** |
| binutils | 2.42 | **2.46** |
| Default OpenJDK LTS | 21 | **25** (8/11/17/21 still available) |
| .NET | 8 / 9 | **10** now available |
| APT | 2.7 | **3.1** (now links OpenSSL, not GnuTLS) |
| systemd | 255 | **259** |
| Default `sudo` | classic `sudo` | **`sudo-rs`** (classic renamed `sudo.ws`) |

> Sources: Ubuntu 26.04 LTS release notes and "Summary for LTS users"
> (documentation.ubuntu.com/release-notes/26.04).

---

## 2. Goals / Non-Goals

### Goals

- Image builds cleanly from `ubuntu:26.04` via `build.sh`, `build.ps1`, and CI.
- All `container-structure-test` cases in `tests.yaml` pass (updated for any
  version-bumped tooling, e.g. Python default, GCC).
- `setup-wsl.ps1` imports and boots the distro under WSL2 with **systemd and
  passwordless sudo working**.
- No stale `24.04` / `noble` references remain except where intentionally kept
  as a documented fallback.
- Naming/branding (image name, distro name, docs) updated to 26.04.

### Non-Goals

- No change to the 6-stage build architecture (`base → build-tools →
  package-managers → runtimes → dev-tools → final`).
- No new tooling beyond what a version bump requires (e.g. adding `dotnet-sdk-10`
  is in scope as a runtime bump; adding unrelated new tools is not).
- No migration off Podman, Homebrew, NVM, or Gobrew.

---

## 3. Risk Register (read this first)

These are the items most likely to break the build. **Phase 0 recon was
completed on 2026-06-25** against a live `ubuntu:26.04` container (podman) — the
"Status" column records the verified outcome and §3.1 has the raw evidence.
Severities below are **post-verification**.

| # | Risk | Where | Severity | Status / Mitigation |
| --- | --- | --- | --- | --- |
| R1 | **`sudo-rs` is the new default sudo.** The base `ubuntu:26.04` image ships *no* sudo; installing the `sudo` package lands the classic binary as `/usr/bin/sudo.ws` **and** pulls `sudo-rs`, which wins the `update-alternatives` selection for `/usr/bin/sudo`. | `Dockerfile:107-121`, `Dockerfile:235-236` | ✅ **VERIFIED OK — Low.** sudo-rs 0.2.13 correctly enforces both `NOPASSWD:ALL` and per-command allow-lists (granted cmd passes, non-granted cmd blocked). The image's sudoers usage works as-is. **Optional hardening:** if you want classic sudo for maximum sudoers-grammar compatibility, add `update-alternatives --set sudo /usr/bin/sudo.ws`. Add a `sudo -n true` structure test regardless. |
| R2 | **Third-party PPAs may not publish for `resolute`.** | `Dockerfile:145-148`, `Dockerfile:512` | ⚠️ **MOSTLY OK — one gap.** `deadsnakes` ✅, `cappelikan` ✅, `dotnet/backports` ✅, `mozillateam` ✅ all publish `resolute`. **`kubescape` ❌ 404 on `resolute`** (noble exists). Mitigation: pin the kubescape PPA to the `noble` suite as a documented fallback, or install kubescape via the Homebrew formula already used elsewhere (`brew install kubescape` appears at `Dockerfile:852`) and drop the apt PPA. |
| R3 | **`t64` ABI library pins.** | `Dockerfile:595,596,600` | ⚠️ **ONE CHANGE.** `libssl3t64` (3.5.5) and `liblttng-ust1t64` (2.14.0) are **unchanged** — still present with the `t64` suffix on 26.04. Only **`libicu74` → `libicu78`** needs updating (ICU 78 is the 26.04 runtime). |
| R4 | **Python stack.** | `Dockerfile:420-445`, `tests.yaml` | ✅ **VERIFIED — matrix achievable.** `python3.14`/`-full` is in **main** (3.14.4-1). `python3.12`/`3.13` are **not** in main but **are** in deadsnakes `resolute` (`3.12.13-1+resolute1`, `3.13.14-1+resolute1`). Keep deadsnakes for 3.12/3.13; 3.14 needs no PPA. Update `update-alternatives` priorities + `set-python-*.sh` helpers. |
| R5 | **HashiCorp apt repo hard-codes `noble`.** | `Dockerfile:163` | ✅ **FIXED BY EDIT.** `resolute` suite exists (200). Change `noble` → `resolute`. |
| R6 | **Microsoft prod `packages-microsoft-prod.deb`.** | `Dockerfile:170-177` | ✅ **VERIFIED OK.** `config/ubuntu/26.04/packages-microsoft-prod.deb` exists (200). The dynamic `$VERSION_ID` fetch works unchanged — no edit needed. |
| R7 | **`jammy` (22.04) Azure CLI workaround.** | `Dockerfile:517-518` | ⚠️ **UPDATE SUITE.** Azure CLI repo has **no `resolute`** (404); `noble` ✅ and `jammy` ✅ both exist. Replace the `jammy` shim with **`noble`** (one LTS back vs. three) — or re-test whether `az` installs cleanly from the dynamic repo without any shim. |
| R8 | **Toolchain bumps** (GCC 15.2, glibc 2.43, binutils 2.46) can surface compile/ABI issues in from-source builds (Homebrew bootstrap, `cargo`, CUDA gcc). | Stage 3–5 | 🔎 **BUILD-TIME — Low/Med.** Not probe-able without a full build. Validate in Phase 3. Watch `nvidia-cuda-toolkit-gcc` vs GCC 15. |
| R9 | **OpenJDK 8/11/17/21/25 co-installability.** | `Dockerfile:659-685`, `tests.yaml:640-653` | ✅ **VERIFIED OK.** All five JDKs have `~26.04` candidates (8u492, 11.0.31, 17.0.19, 21.0.11, 25.0.3). Default 25 unchanged. No edit needed beyond confirming tests. |
| R10 | **APT 3.2** (probed; release notes said 3.1) now links OpenSSL; output/UX changed. | Throughout | ✅ **LOW.** `apt-get update`/`install`/`add-apt-repository` all worked non-interactively in recon. Spot-check the retry loops in Phase 2. |
| R12 | **Stage 4 main-list package renames / removals on 26.04.** Several apt names changed or were dropped. *(Discovered during Phase 2 dry-run probing.)* | `Dockerfile` runtimes stage | ⚠️ **FIXED — Med.** Renames: `libncurses5-dev`→`libncurses-dev`, `dnsutils`→`bind9-dnsutils` (still provides `dig`+`nslookup`), `p7zip-full`→`7zip` (still provides `7z`), `policykit-1`→`polkitd`+`pkexec`. Dropped: `powershell` (apt) — **but note:** the pre-existing `dotnet tool install -g powershell` is *broken* (ships no `DotnetToolSettings.xml`), so pwsh is now installed from the official PowerShell GitHub release **tarball** (`pwsh 7.6.3`, verified in-build); `nuget` (apt) — removed from archive, use `dotnet nuget` (test update needed, see D6); `blobfuse2` — no 26.04-compatible upstream build (see D5). k6 signing key rotated → fetch from `https://dl.k6.io/key.gpg`. Azure CLI repo pinned to `noble` (the `jammy` shim is removed). **Verified:** full 724-package main-list dry-run install resolves with zero conflicts. |
| R11 | **`wslu` removed from the 26.04 archive.** It provides `wslview` (used for `BROWSER=wslview` at `Dockerfile:745`), `wslpath`, `wslsys`. `wsl-setup` and `ubuntu-wsl` remain, but `ubuntu-wsl` no longer pulls `wslu`. *(Discovered during Phase 1 base build, not initial recon.)* | `Dockerfile:92` (foundation apt list), `Dockerfile:745` | ⚠️ **FIXED — Med.** Dropped `wslu` from the apt list; install the upstream `wslu` `.deb` from the wslutilities PPA pool (built for `noble`, runs on `resolute`; deps `bc`/`desktop-file-utils`/`psmisc` are in 26.04 main). The PPA has no `resolute` suite and GitHub ships no `.deb`. **Verified:** base build installs it and `/usr/bin/wslview` resolves. |

### 3.1 Phase 0 recon evidence (2026-06-25, `podman run ubuntu:26.04`)

- **OS:** `ID=ubuntu VERSION_ID=26.04 VERSION_CODENAME=resolute`; **APT 3.2.0**.
- **Default Python:** `python3 => 3.14.3-0ubuntu2`.
- **t64 / ICU:** `libicu74 <none>` → **`libicu78`** present; `libssl3t64 3.5.5-1ubuntu3.2` ✅; `liblttng-ust1t64 2.14.0-1.1` ✅ (both keep `t64`); plain `libssl3`/`liblttng-ust1` not available.
- **Python (main):** `python3.14` & `-full` = `3.14.4-1`; `python3.12`/`3.13` = `<none>` in main.
- **Python (deadsnakes `resolute`):** `python3.12 = 3.12.13-1+resolute1`, `python3.13 = 3.13.14-1+resolute1`.
- **OpenJDK candidates:** 8 `8u492-ga~us2-0ubuntu1~26.04.1`, 11 `11.0.31`, 17 `17.0.19`, 21 `21.0.11`, 25 `25.0.3` (all `~26.04`).
- **sudo:** base image has none; `sudo` pkg = classic `1.9.17p2` installed as `/usr/bin/sudo.ws`; `sudo-rs 0.2.13` is the default alternative. Both enforce `NOPASSWD:ALL` and per-command rules correctly.
- **PPA `resolute` Release probe:** deadsnakes ✅, cappelikan ✅, dotnet/backports ✅, mozillateam ✅, **kubescape ❌ 404**.
- **Vendor repos:** HashiCorp `resolute` ✅; MS prod `26.04` `.deb` ✅; Azure CLI `resolute` ❌ 404 (noble/jammy ✅); MS Edge `stable` ✅ (codename-agnostic).

**Net:** the only hard blockers requiring a workaround are **kubescape PPA (R2)**
and **Azure CLI suite (R7)**; the rest is mechanical (`libicu74→78`,
`noble→resolute` for HashiCorp, keep deadsnakes for 3.12/3.13). The feared
`sudo-rs` and `t64`/Microsoft issues did **not** materialize.

---

## 4. Detailed Change Inventory

### 4.1 `Dockerfile` (primary)

| Location | Current | Change |
| --- | --- | --- |
| `Dockerfile:9` | `FROM ubuntu:24.04 AS base` | `FROM ubuntu:26.04 AS base` |
| `Dockerfile:15` | `LABEL org.opencontainers.image.version=24.04` | `=26.04` |
| `Dockerfile:163` | HashiCorp repo `... noble main` | **`... resolute main`** — `resolute` confirmed available (R5) |
| `Dockerfile:170-177` | Microsoft prod via `$VERSION_ID` | **No change** — 26.04 `.deb` confirmed present; dynamic fetch works (R6) |
| `Dockerfile:145-148` | PPAs: kubescape, deadsnakes, cappelikan, dotnet/backports | Keep all except **kubescape** → pin its PPA to `noble` or drop it for the existing `brew install kubescape` (R2) |
| `Dockerfile:420-445` | `python3.12/3.13/3.14-full` + alternatives | Keep deadsnakes for **3.12/3.13**; **3.14 comes from main** (no PPA). Update alternatives priorities + `set-python-*.sh` (R4) |
| `Dockerfile:511-513` | Mozilla PPA for Firefox (24.04 snap workaround) | `mozillateam` `resolute` confirmed ✅; re-verify the Firefox snap-transitional situation still applies on 26.04, keep PPA otherwise (R2) |
| `Dockerfile:517-518` | `jammy` suite shim for Azure CLI | **Change `jammy` → `noble`** (azure-cli has no `resolute` repo); or re-test install with no shim (R7) |
| `Dockerfile:556-557` | `dotnet-sdk-8.0`, `dotnet-sdk-9.0` | Consider adding `dotnet-sdk-10.0` (now available) — see D3 |
| `Dockerfile:595,596,600` | `libicu74`, `liblttng-ust1t64`, `libssl3t64` | **Only `libicu74` → `libicu78`.** `libssl3t64`/`liblttng-ust1t64` unchanged on 26.04 (R3) |
| `Dockerfile:659-685` | OpenJDK 8/11/17/21/25, default 25 | **No change** — all five confirmed available with `~26.04` builds (R9) |
| `Dockerfile:107-121`, `235-236` | sudo + sudoers.d rules | **No change required** — sudo-rs enforces the rules correctly. Optional: pin classic via `update-alternatives --set sudo /usr/bin/sudo.ws` (R1) |
| `Dockerfile:92` (`wslu` in apt list) | `wslu \` in foundation apt install | **Removed from apt list**; added a dedicated RUN that installs the upstream `wslu` `.deb` from the wslutilities PPA pool (R11) |

> **Phase 3 status (✅ DONE 2026-06-25):** The **full image** builds end-to-end
> on 26.04 (`podman build --target final` succeeds; all 6 stages, final stage
> 34/34 + COMMIT). **No Dockerfile changes were required** — the Homebrew tool
> installs (≈50 formulae), the GitHub-release tarballs (Flyway/Liquibase/CodeQL),
> the `antigravity` apt package (1.23.2), and the pip packages on Python 3.14
> (checkov/detect-secrets/podman-compose/pre-commit/pyright/uv, all cp314 wheels)
> all build unmodified. Verified in the image: OS = "Ubuntu 26.04 LTS (resolute)",
> all brew tools, flyway/liquibase/codeql, opentofu (tenv), pwsh 7.6.3. The pip
> "packaging 23.2 vs wheel" message is a pre-existing non-fatal resolver warning.
>
> **Phase 2 status (✅ DONE 2026-06-25):** Stages 2–4 build end-to-end on 26.04
> (`podman build --target runtimes` succeeds). Verified in the built image:
> `7z`, `dig`, `nslookup`, `az`, `k6 v2.0.0`, `pwsh 7.6.3`, Python 3.12/3.13/3.14,
> Java 25 default. Renames + azure-cli(noble) + k6-key + pwsh-tarball committed.
> **Phase 4 follow-ups:** update the `nuget` test to `dotnet nuget` and remove the
> `blobfuse2` test (D5/D6).
>
> **Phase 1 status (✅ DONE 2026-06-25):** `FROM`/labels, HashiCorp `resolute`,
> `libicu74`→`libicu78`, kubescape-PPA removal, and the wslu fix are committed.
> The `base` target builds end-to-end on 26.04 (`podman build --target base`
> succeeds; `wslview` resolves). Stages 2–6 remain (Phases 2–3).

> **Note on comments:** several inline comments reference "Ubuntu 24.04" (e.g.
> `Dockerfile:511`). Update comment text alongside the code so the rationale
> stays accurate.

### 4.2 Build & import scripts

| File | Lines | Change |
| --- | --- | --- |
| `build.sh` | 3, 82, 95 | Banner text + `IMAGE_NAME="localhost/tmatwood/ubuntu-26.04"` |
| `build.ps1` | 2, 94, 107 | Banner text + `$IMAGE_NAME = "localhost/tmatwood/ubuntu-26.04"` |
| `setup-wsl.ps1` | 5, 8, 11, 14-28 | All `tmatwood-ubuntu-24.04` distro/dir/image names → `26.04` |
| `docker-compose-github-runner.yml` | 22 | Default image `...ubuntu-24.04:latest` → `26.04` |

> **Decision needed (D1):** do we rename the image/distro to `ubuntu-26.04`
> (matches current scheme) or move to a version-agnostic name (e.g.
> `tmatwood-wsl-dev`) to avoid renaming every future upgrade? Recommendation:
> rename to `26.04` now for consistency; consider version-agnostic naming as a
> separate follow-up ticket.

### 4.3 CI

| File | Lines | Change |
| --- | --- | --- |
| `.github/workflows/ci.yml` | 20 | `IMAGE_NAME: wsl-ubuntu-24.04` → `wsl-ubuntu-26.04` |

GHCR push paths derive from `IMAGE_NAME`, so they follow automatically. No other
CI logic changes are expected.

### 4.4 Test suite (`tests.yaml`)

| Lines | Current assertion | Change |
| --- | --- | --- |
| 118-125, 608-611 | Python 3.12 / 3.13 / 3.14 present | Align with the chosen Python matrix (R4) |
| 209 | default `openjdk 25` | No change expected (25 is the default on 26.04 too) — verify |
| 640-653 | java 8/11/17/21 paths | Verify paths still resolve on 26.04 |
| (new) | — | Add: `lsb_release -rs` == `26.04`; `sudo -n true` succeeds for `dev` (R1); GCC major == 15 |

The README advertises "242 automated tests" — keep the count accurate after
edits.

### 4.5 Documentation

Update Ubuntu version, codename, and image-name references in:

- `README.md` (title, badges, base-image line, clone/import examples, star-history URLs)
- `docs/ARCHITECTURE.md` (base image + target image names)
- `docs/PERFORMANCE.md` (base image row, example `FROM`)
- `docs/TESTING.md`, `docs/TROUBLESHOOTING.md`, `docs/GITHUB_ACTIONS.md`, `docs/ACT_QUICKSTART.md` (image-name examples)
- `docs/MULTISTAGE_PLAN.md` (the `FROM ubuntu:24.04 AS base` reference)
- `.github/copilot-instructions.md` (project description, image tags, Firefox-snap note)
- `.gitleaks.toml` title string (cosmetic)

> Codename change matters: "Noble Numbat" → "Resolute Raccoon" everywhere the
> codename is spelled out (e.g. `README.md:47`, `docs/ARCHITECTURE.md:25`).

---

## 5. Implementation Plan (phased)

**Phase 0 — Recon (no code changes). ✅ DONE 2026-06-25.**
Completed against a live `ubuntu:26.04` container — results recorded in §3
(Status column) and §3.1 (evidence). R1/R6/R9 cleared with no edits needed;
R2 (kubescape) and R7 (Azure CLI) are the only true workarounds; R3/R4/R5 are
mechanical edits with confirmed targets.

**Phase 1 — Base + foundation.**
Bump `FROM`, labels, repo codenames, and the `t64`/ICU package names. Get
Stage 1 (`base`) building. Resolve sudo (R1) here since everything downstream
depends on it.

**Phase 2 — Repos, PPAs, runtimes.**
Apply PPA/runtime decisions (Python matrix, Java set, .NET, Microsoft repo,
Azure CLI). Get Stages 2–4 building.

**Phase 3 — Dev tools + final.**
Homebrew/NVM/Gobrew bootstrap under GCC 15 / glibc 2.43; Stages 5–6. Full clean
build.

**Phase 4 — Scripts, CI, tests, docs.**
Rename images/distro, update `tests.yaml` (incl. new assertions), update all
docs. Run `container-structure-test` and `pre-commit run --all-files`.

**Phase 5 — Validation & sign-off.**
Import to WSL2 via `setup-wsl.ps1`, confirm systemd boots, sudo works, GUI/WSLg
and audio function, Podman socket + `act` work. Open PR to `main`.

---

## 6. Acceptance Criteria

- [ ] `FROM ubuntu:26.04`; image builds end-to-end via `bash build.sh` with no errors.
- [ ] CI (`.github/workflows/ci.yml`) builds and passes on `feature/PLAT-165`.
- [ ] `container-structure-test` passes; new assertions for OS version, GCC 15, and `sudo -n` are present and green.
- [ ] `sudo -n true` works for the `dev` user; the `wsl-network` per-command sudoers rule still functions (R1).
- [ ] No unintended `24.04` / `noble` / `Noble Numbat` references remain (`grep -rn`); intentional fallbacks are commented as such.
- [ ] `setup-wsl.ps1` imports a working distro; `systemctl status` is healthy; WSLg GUI and PulseAudio work.
- [ ] README test count and all version/codename strings are accurate.
- [ ] PLAT-165 acceptance criteria met; PR opened to `main`.

---

## 7. Open Decisions

- **D1 — Image/distro naming:** rename to `ubuntu-26.04` (recommended) vs. adopt
  a version-agnostic name to stop renaming each upgrade.
- **D2 — Python matrix on 26.04:** ✅ *Resolved by recon* — ship 3.12 + 3.13
  (deadsnakes `resolute`) and 3.14 (main). Open sub-question: keep 3.12 or drop
  to a 3.13/3.14 pair to reduce surface?
- **D3 — .NET 10:** add `dotnet-sdk-10.0` now, or keep 8/9 only this cycle?
- **D5 — blobfuse2:** dropped because upstream Azure ships no 24.04+/26.04 `.deb`
  (the 22.04 build needs `libfuse3.so.3`; 26.04 bumped the soname to `.so.4`).
  Forcing it risks FUSE ABI breakage. Options: (a) leave dropped and remove its
  test until Microsoft publishes a 26.04 build (recommended), (b) install the
  22.04 `.deb` with a `libfuse3.so.3` compat symlink (risky for a FUSE tool).
- **D6 — nuget CLI:** the standalone `nuget` apt package is gone from 26.04. The
  replacement is `dotnet nuget`. Options: (a) update the `tests.yaml` nuget test
  to `dotnet nuget` and drop the standalone command (recommended), (b) add a
  `/usr/local/bin/nuget` shim that execs `dotnet nuget`.
- **D4 — sudo strategy:** ✅ *Resolved by recon* — `sudo-rs` enforces the
  current rules correctly, so the default is acceptable. Optional hardening only:
  pin classic `/usr/bin/sudo.ws` if broader sudoers-grammar compatibility is
  wanted. Recommendation: accept `sudo-rs`, add a `sudo -n` regression test.

---

## 8. Rollback

The change is isolated to `feature/PLAT-165`. `main` continues to build the
working 24.04 image. If a blocker is found (e.g. a critical PPA never ships for
`resolute`), we hold the branch and document the blocker on PLAT-165 rather than
merging. No runtime data migration is involved — WSL users simply keep their
existing 24.04 distro until the 26.04 image is validated and imported.
