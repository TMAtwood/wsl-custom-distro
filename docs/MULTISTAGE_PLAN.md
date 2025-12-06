# Multi-Stage Dockerfile Refactoring Plan

This document outlines the plan to refactor the monolithic 1025-line Dockerfile into a multi-stage build with clear separation of concerns.

---

## Current Structure Analysis

**Current Dockerfile**: 1025 lines, monolithic structure
**Goal**: 6 logical stages with better caching and maintainability

---

## Proposed Stage Architecture

### Stage 1: Base Foundation (Lines 1-226)

**Purpose**: System foundation, users, repositories
**Stage Name**: `base`

**Contents**:

- ARG and ENV variables (lines 1-26)
- Foundation packages via apt (lines 38-89)
  - systemd, curl, wget, git, build-essential, jq, sudo, etc.
- User creation (lines 98-113)
  - root, linuxbrew, dev users
  - Groups: sudo, adm, docker, audio, video
- Git configuration script (lines 122-125)
  - `/usr/local/bin/setup-git-config.sh`
- PPAs and repositories (lines 127-150)
  - deadsnakes (Python), dotnet/backports, kubescape
  - HashiCorp, Microsoft packages
- WSL configuration (lines 158-171)
  - `/etc/wsl.conf` with systemd enabled
  - DNS overrides, Windows tool symlinks

**Why separate**: Core system that rarely changes. Excellent cache layer.

---

### Stage 2: Build Tools (Lines 38-89 subset + build-essential)

**Purpose**: Compilers and build systems from apt
**Stage Name**: `build-tools`
**FROM**: `base AS build-tools`

**Contents**:

- Already installed in base via build-essential package
- Additional build tools:
  - gcc, g++, make, cmake
  - autoconf, automake, libtool
  - pkg-config, intltool
  - gawk, sed, awk

**Why separate**: Build tools rarely change but are required for subsequent stages.

---

### Stage 3: Package Managers (Lines 203-256, 272-275)

**Purpose**: Install all package managers before using them
**Stage Name**: `package-managers`
**FROM**: `build-tools AS package-managers`

**Contents**:

#### Homebrew (lines 203-256)

- Clone Homebrew to `/home/linuxbrew/.linuxbrew`
- Configure brew shellenv
- Set permissions
- DO NOT install any packages yet

#### NVM - Node Version Manager (lines 272-275)

- Install nvm to `/home/dev/.nvm`
- DO NOT install Node.js yet

#### Gobrew - Go Version Manager

- Install gobrew to `/home/dev/.gobrew`
- DO NOT install Go versions yet

#### Tenv - Terraform/OpenTofu Version Manager

- Will be installed via Homebrew in Stage 5
- Listed here for awareness

**Git Configuration** (lines 180-196):

- Run `setup-git-config.sh` for all three users
- dev user: default credential helper (store)
- linuxbrew user: default credential helper (store)
- root user: Windows Git Credential Manager

**Why separate**: Package managers installation is expensive. Once cached, we can iterate on tools without reinstalling package managers.

---

### Stage 4: Language Runtimes (Lines 296-628)

**Purpose**: Install language runtimes using package managers
**Stage Name**: `runtimes`
**FROM**: `package-managers AS runtimes`

**Contents**:

#### Python (lines 296-347)

- Python build dependencies
- Python 3.12, 3.13, 3.14 (via deadsnakes PPA)
- update-alternatives configuration
- Version switcher scripts (`set-python-*.sh`)
- Python packages via pip:
  - checkov, pre-commit, yamllint, setuptools, wheel, pytest

#### Node.js (lines 272-284)

- Install Node.js LTS via nvm
- Global packages via npm:
  - @anthropic-ai/claude-code, npm-check, dep-check, newman, snyk

#### ClamAV (lines 355-379)

- ClamAV antivirus + daemon
- Configuration and systemd service
- Cron job for daily scans

#### Browsers & Repositories (lines 451-565)

- Google Chrome (repository + install)
- Microsoft Edge (repository + install)
- Firefox (apt install)
- Audio/video packages:
  - PulseAudio, ALSA, GStreamer
  - VLC, OBS Studio, Audacity, GIMP
  - v4l-utils, ffmpeg

#### Java (lines 569-598)

- OpenJDK 8, 11, 17, 21, 25
- update-alternatives configuration
- Version switcher scripts (`set-java-*.sh`)

#### .NET (lines 607-628)

- .NET SDK 8.0, 9.0
- Global tools:
  - coverlet, CycloneDX, dotnet-dump, dotnet-gcdump
  - dotnet-format, dotnet-trace, GitVersion, PowerShell
  - paket, fake-cli, SpecFlow, trx2junit

**Why separate**: Language runtimes change more frequently than package managers. Good caching boundary.

---

### Stage 5: Development Tools (Lines 630-689, 757-875)

**Purpose**: Install development tools via package managers
**Stage Name**: `dev-tools`
**FROM**: `runtimes AS dev-tools`

**Contents**:

#### Shell Configuration (lines 639-648)

- Bash aliases (d, dc, k, p, pc, tf)
- SSH agent auto-start
- BROWSER=wslview
- DOCKER_HOST environment variable

#### Act Configuration (lines 657-669)

- `.actrc` for GitHub Actions local runner
- Symlinks for root access

#### Homebrew Packages (lines 624-689)

Organized by category:

**Taps** (lines 624-625):

- linka-cloud/tap

**Development Tools** (lines 628-634):

- act, bash-git-prompt, btop, cloc, gcc (brew), gh, gitversion, tldr

**Container Tools** (lines 637-651):

- container-structure-test, copa, cosign, crane, dive
- hadolint, helm, k9s, kompose, krew, kubescape
- kustomize, lazydocker, mkcert, podman

**Security Scanning** (lines 654-659):

- dependency-check, grype, osv-scanner, syft, trivy

**Infrastructure/Terraform** (lines 662-668):

- infracost, tenv, terraform-docs, terraformer
- terrascan, tflint, tfsec, tfupdate

**Specialized Tools** (lines 671-683):

- d2vm, spring-boot, uv, yamllint, yq

**Configuration** (lines 686-689):

- brew upgrade
- tenv configuration

#### Symlinks for Root Access (lines 692-754)

- Homebrew tools accessible from root via `/usr/local/bin`

#### Python Packages (lines 757-802)

- pip packages with `--break-system-packages --ignore-installed`
- checkov, pre-commit, yamllint, setuptools, wheel, pytest

#### Podman Configuration (lines 803-909)

- Containers configuration
- Registries (docker.io, ghcr.io, gcr.io, quay.io, azurecr.io, AWS ECR)
- Storage configuration
- Rootful podman socket (systemd)

**Why separate**: Development tools can be added/removed frequently. Changes here don't invalidate previous stages.

---

### Stage 6: Final Configuration (Lines 912-1025)

**Purpose**: Final system configuration and cleanup
**Stage Name**: `final` (default target)
**FROM**: `dev-tools AS final`

**Contents**:

#### WSLg Audio/Video Configuration (lines 936-974)

- PulseAudio client configuration
- ALSA configuration
- Environment variables (DISPLAY, WAYLAND_DISPLAY, PULSE_SERVER)
- Chrome wrapper script

#### Bash Configuration (lines 976-1002)

- bash-git-prompt integration
- NVM initialization
- Custom prompt configuration

#### System Services (lines 1004-1038)

- wsl-vpnkit for VPN support
- Systemd service files
- Enable lingering for dev user

#### Final Cleanup (lines 1042-1048)

- Remove unnecessary bashrc entries
- Set final user and workdir

**ARG BUILD_DATE** (line 1050):

- Build timestamp

**Why separate**: Final configuration and cleanup. Changes here are cheap to rebuild.

---

## Build Command Changes

### Current Build

```bash
podman build -t image:tag .
```

### After Multi-Stage

```bash
# Full build (default)
podman build -t image:latest .

# Build only base (for testing)
podman build --target base -t image:base .

# Build up to package managers
podman build --target package-managers -t image:pm .

# Build variant: base + build-tools + package-managers + runtimes only
podman build --target runtimes -t image:runtimes .
```

---

## Benefits

### 1. **Better Caching**

- Base foundation changes: Rebuild all
- Package manager update: Rebuild from Stage 3 onwards
- New Homebrew package: Rebuild from Stage 5 onwards
- Config change: Rebuild only Stage 6

### 2. **Variant Images**

```dockerfile
# Minimal runtime (base + runtimes)
FROM runtimes AS minimal
WORKDIR /home/dev
USER dev

# Full development (all stages)
FROM final AS full
```

### 3. **Faster Iteration**

- Test new tools without rebuilding everything
- Debug specific stages independently
- Parallel stage builds (with buildx)

### 4. **Clearer Structure**

- Each stage has single responsibility
- Easier to understand and maintain
- Better documentation via stage names

---

## Implementation Steps

1. **Backup current Dockerfile**

    ```bash
    cp Dockerfile Dockerfile.monolithic.backup
    ```

2. **Create Stage 1: Base Foundation**
    - Lines 1-226 with `FROM ubuntu:24.04 AS base`

3. **Create Stage 2: Build Tools**
    - `FROM base AS build-tools`
    - Verify build-essential and compilers

4. **Create Stage 3: Package Managers**
    - `FROM build-tools AS package-managers`
    - Homebrew, nvm, gobrew installation only
    - Git configuration for all users

5. **Create Stage 4: Language Runtimes**
    - `FROM package-managers AS runtimes`
    - Python, Node.js, Java, .NET, etc.

6. **Create Stage 5: Development Tools**
    - `FROM runtimes AS dev-tools`
    - Homebrew packages, Podman, etc.

7. **Create Stage 6: Final Configuration**
    - `FROM dev-tools AS final`
    - System services, cleanup, final user/workdir

8. **Test each stage independently**

    ```bash
    podman build --target base -t test:base .
    podman build --target build-tools -t test:build-tools .
    # ... etc
    ```

9. **Full build test**

    ```bash
    podman build -t test:full .
    ```

10. **Run container structure tests**

    ```bash
    container-structure-test test --image test:full --config tests.yaml
    ```

---

## Risk Assessment

### High Risk Areas

1. **User context switching**: Ensure USER/WORKDIR commands are in correct stages
2. **Environment variables**: Some may need to be set in multiple stages
3. **Path dependencies**: Tools depending on previous stage outputs

### Mitigation

- Test each stage independently
- Verify with container-structure-test
- Keep backup of monolithic Dockerfile
- Implement incrementally with git commits per stage

---

## Timeline Estimate

- **Planning & Review**: 30 minutes (current)
- **Implementation**: 4-6 hours
  - Stage 1-2: 1 hour
  - Stage 3: 1 hour (package managers are complex)
  - Stage 4: 1.5 hours (many language runtimes)
  - Stage 5: 1.5 hours (many tools)
  - Stage 6: 30 minutes (final config)
- **Testing**: 1-2 hours
  - Build each stage
  - Full integration test
  - Container structure tests
- **Total**: 5.5-8.5 hours

---

## Questions for Review

1. **Should we create variant images** (e.g., minimal, full)?
2. **Stage granularity**: Is 6 stages appropriate or should we have more/fewer?
3. **Build targets**: Should we set a specific default target or use `final`?
4. **Package manager stage**: Should gobrew and tenv be in their own substage?

---

**Status**: Ready for review and approval
**Next Step**: User approval, then implementation
**Estimated Effort**: 5.5-8.5 hours total
