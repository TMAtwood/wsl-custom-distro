# Architecture Documentation

This document describes the system architecture, design decisions, and organization of the WSL Ubuntu 26.04 Development Environment.

---

## Table of Contents

- [System Overview](#system-overview)
- [User Architecture](#user-architecture)
- [Directory Structure](#directory-structure)
- [Package Managers](#package-managers)
- [Tool Categories](#tool-categories)
- [Configuration Strategy](#configuration-strategy)
- [WSL Integration](#wsl-integration)
- [Network & Security](#network--security)
- [Build System](#build-system)

---

## System Overview

### Base Image

- **Base**: Ubuntu 26.04 LTS (Resolute Raccoon)
- **Purpose**: Multi-language development environment optimized for WSL2
- **Design Goal**: Comprehensive tooling for modern software development workflows

### Key Characteristics

- **Systemd-enabled**: Full init system support for services and daemons
- **Multi-language**: Python, Node.js, Go, Java, .NET, Rust
- **Container-native**: Rootful Podman for act compatibility
- **GUI-capable**: WSLg integration for graphical applications
- **Version-flexible**: Multiple language runtime versions with switcher scripts

---

## User Architecture

The image uses a **three-user architecture** to separate concerns and maintain proper permissions:

### 1. **root** (UID 0, GID 0)

- **Purpose**: System administration and configuration
- **Home**: `/home/root`
- **Responsibilities**:
  - Package installation (apt)
  - System service configuration
  - Filesystem permissions management
  - Installing tools that require root access

### 2. **linuxbrew** (GID: linuxbrew)

- **Purpose**: Homebrew package manager ownership
- **Home**: `/home/linuxbrew`
- **Responsibilities**:
  - Owns `/home/linuxbrew/.linuxbrew` directory tree
  - Installs and manages Homebrew packages
  - Maintains Homebrew repository integrity
- **Sudo**: Passwordless sudo access for package operations

### 3. **dev** (UID 1001, GID 1001)

- **Purpose**: Primary development user (default WSL user)
- **Home**: `/home/dev`
- **Responsibilities**:
  - Day-to-day development work
  - User-level tool configuration
  - Running applications and services
- **Groups**: `dev`, `sudo`, `adm`, `docker`, `audio`, `video`
- **Sudo**: Passwordless sudo access
- **Shell**: `/bin/bash` with bash-completion and git-prompt

---

## Directory Structure

### Primary Locations

```
/
├── home/
│   ├── root/                        # Root user home
│   ├── dev/                         # Development user home (default)
│   │   ├── .bashrc                  # Bash configuration with aliases
│   │   ├── .config/                 # User configuration
│   │   │   ├── pulse/               # PulseAudio client config
│   │   │   └── containers/          # Podman configuration
│   │   ├── .local/bin/              # User-installed Python scripts
│   │   ├── .dotnet/tools/           # .NET global tools
│   │   ├── .nvm/                    # Node Version Manager
│   │   └── .ssh/                    # SSH configuration
│   │
│   └── linuxbrew/                   # Homebrew user home
│       └── .linuxbrew/              # Homebrew installation root
│           ├── bin/                 # Homebrew binaries
│           ├── sbin/                # Homebrew system binaries
│           ├── Cellar/              # Installed packages
│           ├── Caskroom/            # Cask installations
│           └── Homebrew/            # Homebrew repository
│
├── usr/
│   ├── bin/                         # System binaries (apt packages)
│   │   ├── python → python3.14      # Python symlink via alternatives
│   │   ├── java → openjdk-25        # Java symlink via alternatives
│   │   ├── set-python-*.sh          # Python version switchers
│   │   └── set-java-*.sh            # Java version switchers
│   │
│   ├── local/                       # Locally compiled software
│   │   ├── bin/                     # Local binaries (brew symlinks)
│   │   ├── etc/                     # Local configuration
│   │   ├── lib/                     # Local libraries
│   │   └── share/                   # Local shared data
│   │
│   └── lib/
│       └── jvm/                     # Java Virtual Machines
│           ├── java-8-openjdk-amd64/
│           ├── java-11-openjdk-amd64/
│           ├── java-17-openjdk-amd64/
│           ├── java-21-openjdk-amd64/
│           └── java-25-openjdk-amd64/
│
├── etc/
│   ├── wsl.conf                     # WSL configuration
│   ├── resolv.conf.override         # Custom DNS override
│   ├── containers/                  # Container configuration
│   │   └── storage.conf             # Container storage config
│   ├── clamav/                      # ClamAV antivirus config
│   │   └── clamd.conf
│   └── systemd/system/              # Systemd service definitions
│       ├── podman.socket            # Podman API socket
│       ├── clamonacc.service        # ClamAV on-access scanner
│       └── make-root-shared.service # Mount propagation service
│
├── run/
│   ├── podman/
│   │   └── podman.sock              # Rootful Podman socket
│   └── user/1001/
│       └── podman/
│           └── podman.sock          # Rootless Podman socket (user)
│
└── mnt/
    ├── c/                           # Windows C: drive
    │   ├── Program Files/
    │   │   ├── Git/                 # Git for Windows (GCM)
    │   │   └── Microsoft VS Code/   # VS Code binary
    │   └── Users/                   # Windows user directories
    │
    └── wslg/                        # WSLg integration (GUI/audio)
        ├── PulseServer              # PulseAudio socket
        ├── .X11-unix/               # X11 sockets
        └── runtime-dir/             # WSLg runtime directory
```

---

## Package Managers

The image uses **four primary package managers** plus language-specific tools:

### 1. **apt** (System Packages)

- **Scope**: Operating system packages, foundational tools
- **User**: `root`
- **Configuration**:
  - PPAs: deadsnakes (Python), dotnet/backports (.NET), kubescape
  - Third-party repos: HashiCorp, Microsoft, Google, Edge
- **Examples**: gcc, make, systemd, git, curl, jq

### 2. **Homebrew** (Development Tools)

- **Scope**: Development utilities, modern CLI tools
- **User**: `linuxbrew` (owned), `dev` (accessed via PATH)
- **Installation**: `/home/linuxbrew/.linuxbrew`
- **PATH**: Added via `brew shellenv` in shell initialization
- **Examples**: gh, helm, k9s, terraform, act, dive, trivy

### 3. **npm** (Node.js Packages)

- **Scope**: JavaScript/Node.js global tools
- **User**: `dev` (via nvm)
- **Installation**: `~/.nvm/versions/node/*/lib/node_modules`
- **Examples**: @anthropic-ai/claude-code, newman, snyk

### 4. **.NET Tools** (Global Tools)

- **Scope**: .NET development utilities
- **User**: `dev`
- **Installation**: `~/.dotnet/tools`
- **Examples**: dotnet-format, GitVersion, powershell, coverlet

### Language-Specific Package Managers

- **pip** (Python): System-wide packages with `--break-system-packages --ignore-installed`
- **go install** (Go): Go binaries installed to `$GOPATH/bin`
- **cargo** (Rust): Rust packages installed to `~/.cargo/bin`

---

## Tool Categories

### Foundation Tools (via apt)

**Purpose**: Core system utilities and build tools

- **Build Essentials**: gcc, g++, make, cmake, autoconf, automake, libtool
- **Version Control**: git, git-lfs, git-flow
- **Compression**: zip, unzip, tar, gzip, bzip2, xz-utils, p7zip-full
- **Network**: curl, wget, axel, ssh, rsync
- **Text Processing**: jq, yq (snap), sed, awk, grep
- **System Monitoring**: htop, iotop, ncdu, dstat

See [Dockerfile:38-565](../Dockerfile#L38-L565) for complete apt package list.

### Language Runtimes

#### Python (via apt + deadsnakes PPA)

- **Versions**: 3.12, 3.13, 3.14
- **Default**: Python 3.14
- **Switchers**: `set-python-12.sh`, `set-python-13.sh`, `set-python-14.sh`
- **Method**: `update-alternatives` system
- **Global Packages**: checkov, pre-commit, yamllint, setuptools, wheel, pytest

See [Dockerfile:296-347](../Dockerfile#L296-L347) for Python configuration.

#### Node.js (via nvm)

- **Manager**: Node Version Manager (nvm)
- **Version**: Latest LTS
- **Global Packages**: @anthropic-ai/claude-code, npm-check, dep-check, newman, snyk
- **Installation**: `~/.nvm/`

See [Dockerfile:272-284](../Dockerfile#L272-L284) for Node.js setup.

#### Java (via apt)

- **Versions**: OpenJDK 8, 11, 17, 21, 25
- **Default**: OpenJDK 25
- **Switchers**: `set-java-8.sh`, `set-java-11.sh`, `set-java-17.sh`, `set-java-21.sh`, `set-java-25.sh`
- **Method**: `update-alternatives` system

See [Dockerfile:569-598](../Dockerfile#L569-L598) for Java configuration.

#### .NET (via Microsoft packages)

- **Versions**: SDK 8.0, 9.0
- **Global Tools**: 15 development utilities including GitVersion, PowerShell, dotnet-format
- **Installation**: `~/.dotnet/tools`

See [Dockerfile:140-150, 607-628](../Dockerfile#L607-L628) for .NET configuration.

#### Go (via apt)

- **Package**: golang-go
- **Additional**: gobrew (Go version manager via Homebrew)

#### Rust (via apt)

- **Packages**: cargo, rustc, rustfmt

### Container & Kubernetes Tools (via Homebrew)

**Container Engines:**

- **Podman**: Rootful configuration for act compatibility
- **act**: GitHub Actions local runner

**Container Utilities:**

- container-structure-test, dive, lazydocker, crane, copa

**Kubernetes:**

- kubectl, helm, k9s, kompose, kustomize, krew, kubescape

**Security & Compliance:**

- cosign, mkcert, trivy, grype, syft, dependency-check, osv-scanner

See [Dockerfile:624-689](../Dockerfile#L624-L689) for Homebrew package list.

### Infrastructure as Code (via Homebrew)

**Terraform Ecosystem:**

- tenv (Terraform/Terragrunt/OpenTofu version manager)
- terraform-docs, terraformer, terrascan, tflint, tfsec, tfupdate

**Cost Analysis:**

- infracost

See [Dockerfile:677-683](../Dockerfile#L677-L683) for IaC tools.

### Browsers & GUI Applications (via apt + repositories)

**Browsers:**

- Firefox (via apt)
- Google Chrome (via Google repository)
- Microsoft Edge (via Microsoft repository)

**GUI Utilities:**

- Chrome wrapper: `chrome-wsl` script for proper WSLg integration

See [Dockerfile:451-461, 487-527](../Dockerfile#L451-L527) for browser setup.

### Audio/Video Tools

**Audio:**

- PulseAudio + ALSA
- pavucontrol (GUI mixer)
- sox (audio toolkit)
- audacity (audio editor)

**Video:**

- obs-studio (recording/streaming)
- vlc (media player)
- ffmpeg (transcoding)
- v4l-utils (Video4Linux)

**Multimedia Frameworks:**

- GStreamer (complete plugin set)

See [Dockerfile:466-564, 936-974](../Dockerfile#L936-L974) for multimedia configuration.

### Security Tools

**Antivirus:**

- ClamAV (daemon + on-access scanning)
- Automated daily scans via cron

**Static Analysis:**

- hadolint (Dockerfile linting)

**Vulnerability Scanning:**

- trivy, grype, syft, dependency-check, osv-scanner (via Homebrew)
- snyk (via npm)

See [Dockerfile:355-379](../Dockerfile#L355-L379) for ClamAV setup.

---

## Configuration Strategy

### Git Configuration

- **Per-user**: Each user (root, linuxbrew, dev) has individual git config
- **Settings**: CRLF handling, case sensitivity, LFS filters, credential helpers
- **Windows Integration**: Root user uses Windows Git Credential Manager
- **Safe Directories**: All users trust `/home/linuxbrew/.linuxbrew`

See [Dockerfile:184-227](../Dockerfile#L184-L227) for git configuration.

### Podman Configuration

- **Mode**: Rootful (for act/GitHub Actions compatibility)
- **Socket**: `/run/podman/podman.sock` (system-wide)
- **Storage**: Overlay driver with mount propagation
- **Environment**: `DOCKER_HOST` set to Podman socket
- **Compatibility**: Docker-compatible API

See [Dockerfile:803-909](../Dockerfile#L803-L909) for Podman configuration.

### WSLg Integration (GUI & Audio)

- **Display**: `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`
- **Audio Server**: PulseAudio client → WSLg PulseAudio server
- **Audio Config**: `~/.config/pulse/client.conf`, `~/.asoundrc`
- **Runtime**: `XDG_RUNTIME_DIR=/run/user/1001`

See [Dockerfile:936-974](../Dockerfile#L936-L974) for WSLg configuration.

### Shell Environment

- **Shell**: Bash with completion and git-prompt
- **Aliases**: Docker/Podman shortcuts (d, dc, k, p, pc, tf)
- **SSH**: Agent auto-start in `.bashrc`
- **Browser**: `BROWSER=wslview` for WSL-Windows browser integration
- **Homebrew**: Added via `brew shellenv` evaluation

See [Dockerfile:639-648, 715-752](../Dockerfile#L639-L752) for shell configuration.

### Version Switching

- **Python**: `update-alternatives` + wrapper scripts (`set-python-*.sh`)
- **Java**: `update-alternatives` + wrapper scripts (`set-java-*.sh`)
- **Node.js**: `nvm use <version>`
- **Terraform/OpenTofu**: `tenv` (Terraform environment manager)
- **Go**: `gobrew` (Go version manager)

---

## WSL Integration

### WSL Configuration (`/etc/wsl.conf`)

```ini
[boot]
systemd=true                    # Enable systemd init

[user]
default=dev                     # Default login user

[automount]
enabled=true                    # Auto-mount Windows drives
options=metadata,umask=22,fmask=11
mountFsTab=false

[network]
generateResolvConf=true         # Auto-generate DNS config

[interop]
appendWindowsPath=true          # Access Windows binaries
```

See [Dockerfile:158-161](../Dockerfile#L158-L161) for WSL configuration.

### Windows Integration

- **Git Credential Manager**: Symlinked from Windows Git installation
- **VS Code**: Symlinked to `/usr/bin/code` for CLI access
- **Browser**: `wslview` command for opening links in Windows browser
- **Drives**: Windows drives mounted at `/mnt/c`, `/mnt/d`, etc.

See [Dockerfile:170-171](../Dockerfile#L170-L171) for Windows tool symlinks.

### VPN Support

- **Tool**: wsl-vpnkit (systemd service)
- **Purpose**: Maintain network connectivity when Windows VPN is active
- **DNS Override**: `/etc/resolv.conf.override` with Cloudflare/Google DNS

See [Dockerfile:1010-1038](../Dockerfile#L1010-L1038) and [TROUBLESHOOTING.md - Network/VPN](TROUBLESHOOTING.md#networkvpn-connectivity).

---

## Network & Security

### DNS Configuration

- **Primary**: Auto-generated by WSL (`/etc/resolv.conf`)
- **Override**: Manual configuration at `/etc/resolv.conf.override`
  - Cloudflare: 1.1.1.1
  - Google: 8.8.8.8, 8.8.4.4

### Firewall & Network

- **iptables**: Installed for container networking
- **slirp4netns**: User-mode networking for rootless containers
- **VPN**: wsl-vpnkit service for VPN compatibility

### Antivirus

- **ClamAV Daemon**: Real-time on-access scanning
- **Scheduled Scans**: Weekly full system scan via cron
- **Quarantine**: Infected files moved to `/root/quarantine`
- **Exclusions**: System directories (`/proc`, `/sys`, `/dev`, Docker volumes)

See [Dockerfile:355-379](../Dockerfile#L355-L379) for antivirus configuration.

### Access Control

- **Sudo**: Passwordless for `dev` and `linuxbrew` users
- **Groups**:
  - `docker`: Container daemon access
  - `audio`: Audio device access
  - `video`: Video/webcam access
  - `adm`: System log access

---

## Build System

### Build Scripts

#### build.ps1 (PowerShell - Podman)

- **Platform**: Windows with Podman Desktop
- **Target**: `localhost/tmatwood/ubuntu-26.04:latest`
- **Architecture**: linux/amd64
- **Features**:
  - GitVersion integration with fallback
  - Colored output and progress tracking
  - Prerequisite validation
  - Build timing metrics

See [build.ps1](../build.ps1) for implementation.

#### build-docker.sh (Bash - Docker)

- **Platform**: Linux/macOS with Docker
- **Target**: `docker.io/tmatwood/ubuntu-26.04:latest`
- **Architecture**: Multi-arch (linux/amd64, linux/arm64)
- **Features**:
  - Docker buildx multi-platform builds
  - Prerequisite checks (docker, jq, buildx)
  - Error handling with traps
  - Build timing and push verification

See [build-docker.sh](../build-docker.sh) for implementation.

### Version Management

- **Tool**: GitVersion (installed as .NET global tool)
- **Format**: Semantic versioning (SemVer)
- **Fallback**: `0.0.0-dev` if GitVersion unavailable
- **Build Arg**: `VERSION` and `BUILD_DATE` passed to Docker

### Testing

- **Framework**: Google Container Structure Test
- **Test File**: [tests.yaml](../tests.yaml)
- **Test Count**: 240 comprehensive tests
- **Categories**:
  - Command availability
  - Version verification
  - Configuration file existence
  - User/group membership
  - Systemd service setup

See [tests.yaml](../tests.yaml) and [TROUBLESHOOTING.md - Testing Issues](TROUBLESHOOTING.md#testing-issues).

### CI/CD

- **Platform**: GitHub Actions
- **Workflow**: [.github/workflows/ci.yml](../.github/workflows/ci.yml)
- **Steps**:
  1. Checkout code
  2. Determine version (GitVersion with fallback)
  3. Build multi-arch image (buildx)
  4. Run container structure tests
  5. Push to registry (on main branch)
- **Local Testing**: `act` tool for running workflows locally

---

## Design Decisions

### Why Rootful Podman?

- **Act Compatibility**: GitHub Actions runner needs to mount daemon socket
- **Developer Convenience**: Simpler configuration, fewer edge cases
- **WSL Security Context**: Already isolated from host Windows system
- **Trade-off**: Less user namespace isolation (acceptable for dev environment)

See [CLAUDE.md - Switching from Rootless to Rootful Podman](CLAUDE.md#switching-from-rootless-to-rootful-podman-for-act-compatibility).

### Why Three Users?

- **Separation of Concerns**: System (root), package management (linuxbrew), development (dev)
- **Permission Isolation**: Homebrew owned by dedicated user prevents conflicts
- **Flexibility**: Dev user can switch contexts with sudo if needed

### Why Multiple Language Versions?

- **Compatibility Testing**: Test code across multiple runtime versions
- **Legacy Support**: Maintain older projects requiring specific versions
- **Version Switchers**: Easy switching without complex environment management

### Why `.dockerignore`?

- **Build Speed**: Exclude unnecessary files from build context
- **Security**: Prevent secrets and credentials from entering image
- **Size Optimization**: Reduce context transfer time to Docker daemon

See [.dockerignore](../.dockerignore) for excluded patterns.

---

## Future Architecture Considerations

### Potential Improvements

1. **Layer Optimization**: Combine some RUN commands to reduce layers (trade-off: debuggability)
2. **Multi-stage Builds**: Separate build-time and runtime dependencies
3. **Base Image Variants**: Create slim, full, and minimal variants
4. **Rootless by Default**: Add rootful as optional configuration
5. **Modular Tool Installation**: Make tool categories optional via build args

### Monitoring & Observability

- Consider adding: Prometheus node exporter, collectd, or telegraf
- Log aggregation: journald forwarding to Windows Event Log

### Security Enhancements

- AppArmor profiles for containers
- SELinux policy (if needed for specific compliance)
- Regular CVE scanning in CI pipeline

---

## Related Documentation

- [README.md](../README.md) - Quick start and usage guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [PERFORMANCE.md](PERFORMANCE.md) - Build times and optimization tips
- [CLAUDE.md](CLAUDE.md) - Decision log and historical context
- [CODE_REVIEW.md](CODE_REVIEW.md) - Code quality assessment

---

**Last Updated:** 2025-11-27
