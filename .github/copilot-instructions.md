# WSL Ubuntu 26.04 Development Environment - Copilot Instructions

## Project Overview

This project builds a comprehensive Ubuntu 26.04 LTS container image for WSL2 with 100+ pre-configured development tools. It's a multi-language development environment (Python, Node.js, Go, Java, .NET, Rust) optimized for WSL2 with full systemd, GUI (WSLg), and rootful Podman support.

## Architecture: Multi-Stage Dockerfile

The 1082-line `Dockerfile` uses a **6-stage build** for optimal caching and separation of concerns:

1. **base** - System foundation: apt packages, 3-user architecture (root/linuxbrew/dev), PPAs, WSL config
2. **build-tools** - Compiler verification (gcc, g++, make) from build-essential
3. **package-managers** - Homebrew, NVM, git config (DO NOT install packages yet - manager setup only)
4. **runtimes** - Language runtimes via package managers (Python 3.12/3.13/3.14, Node.js, Java 8/11/17/21, .NET 8/9, ClamAV, browsers)
5. **dev-tools** - Development tools via Homebrew (helm, k9s, terraform, act, trivy, grype, etc.)
6. **final** - Podman configuration, systemd services, final user setup

**Critical Pattern**: Package managers are installed in stage 3 but packages are installed in stages 4-5. This optimizes Docker layer caching.

## Three-User Architecture

- **root** (UID 0) - System admin, package installation, service config
- **linuxbrew** (custom GID) - Owns `/home/linuxbrew/.linuxbrew`, manages Homebrew packages
- **dev** (UID 1001, default WSL user) - Primary development user, member of: sudo, adm, docker, audio, video

**Each stage switches users** with `USER` directives. Track the active user when editing the Dockerfile.

## Build & Test Workflow

### Local Build

```bash
# WSL (bash) - Uses GitVersion for semantic versioning
./build.sh

# Windows PowerShell (not commonly used)
./build.ps1
```

**Build System**:

- Semantic versioning via GitVersion (GitFlow workflow - see `GitVersion.yml`)
- Tags: `localhost/tmatwood/ubuntu-26.04:VERSION` and `localhost/tmatwood/ubuntu-26.04:latest`
- Uses Podman (not Docker) with `--format docker` for compatibility

### Local Test

```bash
# Run 240+ container structure tests
./run_tests.sh

# Uses container-structure-test with tests.yaml
# Tests verify: command existence, --version output, package installation
```

**Test Configuration** (`tests.yaml`):

- GUI apps (firefox, vlc, obs, pavucontrol) use `which` instead of `--version` (they require X11/Wayland)
- Ubuntu 26.04 Firefox is a snap transitional package - test with `which` only
- VLC output is "VLC version" not "VLC media player"

### CI/CD Pipeline

**GitHub Actions** (`.github/workflows/ci.yml`):

- **Triggers**: Push to main/develop/feature/*, PRs to main/develop, manual workflow_dispatch
- **Build**: Uses Docker Buildx for caching and multi-platform support
- **Version**: GitVersion determines SemVer from git history
- **Test**: Runs all 240+ container-structure-tests
- **Publish** (main branch only):
  - Saves image as tarball artifact (7-day retention)
  - Pushes to GitHub Container Registry (ghcr.io) with version tag + latest
- **Act support**: Detects local execution and uses legacy docker build (disables buildx)

**Testing locally with Act**:

```bash
# Run the CI workflow locally using Act
act -j build-and-test
```

## Pre-commit Hooks

**Critical for Dockerfile edits**: Run `.pre-commit-config.yaml` hooks before commits

**Key Hooks**:

- `hadolint` (Dockerfile linting) - `./scripts/pre-commit-hadolint.sh`
- `dockle` (Container security) - `./scripts/pre-commit-dockle.sh`
- `trivy-config` (IaC scanning) - `./scripts/pre-commit-trivy-config.sh`
- `trivy-image` (Vulnerability scanning) - `./scripts/pre-commit-trivy-image.sh`
- `container-structure-test` - Runs full test suite before commit

**Hadolint Patterns to Avoid**:

- ❌ **NO heredocs** (`tee file <<'EOF'`) - hadolint parser fails with "unexpected '['" errors
- ✅ **Use printf** with `\n` for multi-line file writes (see lines 160, 846, 906 in Dockerfile)
- Use `# hadolint ignore=RULE` comments for intentional violations

**Common Ignores**:

- `DL3002` (last USER root) - Required for system operations
- `DL3005` (apt-get upgrade) - Development env needs latest
- `DL3008/3013/3016/3062` (unpinned versions) - Dev env wants latest tools
- `SC2086` (unquoted variables) - Often intentional for word splitting

## Key Development Patterns

### Version Switcher Scripts

Multiple versions of Python and Java are installed with switcher scripts:

```bash
/usr/bin/set-python-12.sh  # Switch to Python 3.12
/usr/bin/set-python-13.sh  # Switch to Python 3.13
/usr/bin/set-python-14.sh  # Switch to Python 3.14 (default)
/usr/bin/set-java-8.sh     # Switch to Java 8
/usr/bin/set-java-21.sh    # Switch to Java 21 (default)
```

These use `update-alternatives --set` under the hood.

### Podman Configuration (Rootful Mode)

- **Why rootful**: Act (GitHub Actions local runner) requires rootful containers for Docker compatibility
- Podman socket: `unix:///run/user/$(id -u)/podman/podman.sock` (set in `.bashrc`)
- `.actrc` configures Act with `-` for `container-daemon-socket` (disables socket bind mount)

### Common Aliases (in `/home/dev/.bashrc`)

```bash
alias p="podman"
alias pc="podman compose"
alias k="kubectl"
alias tf="tofu"
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock
```

## Critical Files & Locations

- `Dockerfile` (1082 lines) - Main build definition
- `tests.yaml` (1078 lines) - Container structure test suite
- `build.sh` - Podman build script with GitVersion
- `run_tests.sh` - Test runner wrapper
- `.github/workflows/ci.yml` - GitHub Actions CI/CD pipeline
- `config/scripts/setup-git-config.sh` - Git config script for all users
- `config/etc/wsl.conf` - WSL2 systemd configuration
- `config/home/dev/.actrc` - Act (GitHub Actions) configuration
- `.pre-commit-config.yaml` - Pre-commit hooks (hadolint, trivy, dockle, etc.)
- `GitVersion.yml` - GitFlow versioning configuration
- `docker-compose-github-runner.yml` - Self-hosted runner setup for Synology NAS
- `docs/ARCHITECTURE.md` - Detailed system architecture
- `docs/TESTING.md` - Test categories and tool list
- `docs/CLAUDE.md` - Conversation log with AI-assisted development decisions

## Editing Guidelines (from CLAUDE.md Commandments)

1. **Plan in `tasks/todo.md`** before work - Get user verification
2. **Simplicity first** - Minimal code impact, avoid large changes
3. **Root cause fixes only** - No temporary fixes, senior developer mindset
4. **Mark progress** - Check off completed items in `tasks/todo.md`
5. **Document changes** - Add review section summarizing work

## Line Endings & Formatting

- **All files use LF** (Unix line endings) - enforced by pre-commit hook `mixed-line-ending`
- Shell scripts must be executable - `check-executables-have-shebangs` enforces this
- `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` - Dockerfile uses pipefail for error handling

## WSL-Specific Considerations

- DNS override: `/etc/resolv.conf.override` with Cloudflare (1.1.1.1) and Google (8.8.8.8/8.8.4.4)
- Windows tool symlinks: `git-credential-manager.exe` and `code.exe` linked from `/mnt/c/Program Files`
- WSLg audio/video: PulseAudio client config at `/home/dev/.config/pulse/client.conf`
- Systemd services: `wsl-vpnkit.service`, `make-root-shared.service`, `clamonacc.service`

## When Adding New Tools

1. **Identify the correct stage**: runtimes (language runtimes) vs dev-tools (CLI tools)
2. **Use appropriate package manager**: apt (system), brew (CLI tools), pip (Python), npm (Node.js)
3. **Add test to `tests.yaml`**: Use `which` for GUI apps, `--version` for CLI tools
4. **Update README.md**: Add to relevant category section
5. **Run pre-commit**: `pre-commit run --all-files` before committing
6. **Test the build**: `./build.sh && ./run_tests.sh`

## Security Scanning

Multiple layers of security scanning (via pre-commit and manual):

- **Hadolint** - Dockerfile best practices
- **Dockle** - Container image security (CIS Benchmark)
- **Trivy** - Vulnerability scanner (config + image)
- **Checkov** - Infrastructure as Code security
- **Gitleaks, TruffleHog, detect-secrets** - Secret detection
- **ClamAV** - Antivirus (runs daily via cron in container)

## CoPilot Commandments for Development

### The 9 Commandments GitHub CoPilot Will Follow

#### 1. Think, Read, Plan

First think through the problem, read the codebase for relevant files, and write a plan to `tasks/todo.md`.

#### 2. Structured Planning

The plan should have a list of to-do items that you can check off as you complete them.

#### 3. Verification Before Work

Before you begin working, check in with me, and I will verify the plan.

#### 4. Progressive Completion

Then work on the to-do items, marking them as complete as you go.

#### 5. Clear Communication

At each step, provide a high-level explanation of what changes you made.

#### 6. Simplicity First

Make every task and code change as simple as possible. Avoid large complex changes. Each change should affect as little code as possible.

#### 7. Review and Documentation

At the end, add a review section to `tasks/todo.md` with a summary of the changes you made and any other relevant information.

#### 8. SENIOR DEVELOPER MINDSET

**DO NOT BE LAZY; NEVER BE LAZY. IF THERE IS A BUG, FIND THE ROOT CAUSE AND FIX IT - NO TEMPORARY FIXES. YOU ARE A SENIOR DEVELOPER; NEVER BE LAZY.**

#### 9. MINIMAL IMPACT CHANGES

**MAKE ALL FIXES AND CODE CHANGES AS SIMPLE AS HUMANLY POSSIBLE. THEY SHOULD ONLY IMPACT THE NECESSARY CODE RELEVANT TO THE TASK AND NOTHING ELSE; THEY SHOULD AFFECT AS LITTLE CODE AS POSSIBLE. YOUR GOAL IS TO NOT INTRODUCE ANY BUGS; IT IS ALL ABOUT SIMPLICITY.**

---

### Summary

These commandments ensure that all development work is:

- **Well-planned** and verified before execution
- **Simple and focused** with minimal code changes
- **Thoroughly documented** with clear explanations
- **Root-cause oriented** with no shortcuts or temporary fixes
- **Bug-free** through careful, intentional changes
