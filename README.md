# 🚀 Ultimate WSL2 Ubuntu 24.04 Development Environment

[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![WSL2](https://img.shields.io/badge/WSL-2-0078D4?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)
[![Podman](https://img.shields.io/badge/Podman-Built-892CA0?logo=podman&logoColor=white)](https://podman.io/)
[![License](https://img.shields.io/github/license/TMAtwood/wsl-ubuntu-24.04)](LICENSE)

> **The most comprehensive, production-ready WSL2 development environment** - A meticulously crafted Ubuntu 24.04 container image packed with 100+ pre-configured development tools, security scanners, and cloud utilities.

---

## 📋 Table of Contents

- [Why This Project?](#-why-this-project)
- [Features](#-features)
- [What's Included](#-whats-included)
- [Quick Start](#-quick-start)
- [Build Options](#-build-options)
- [Testing](#-testing)
- [Usage Examples](#-usage-examples)
- [Customization](#-customization)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## 🎯 Why This Project?

Setting up a development environment is time-consuming and error-prone. This project eliminates that pain by providing:

- **⚡ Zero Configuration** - Everything works out of the box
- **🔒 Security First** - Pre-installed scanners and best practices
- **🌍 Multi-Language** - Python, Node.js, Go, Java, .NET, and more
- **☁️ Cloud Ready** - Azure, AWS, and Kubernetes tools included
- **✅ Tested** - 242 automated tests ensure reliability
- **📦 Reproducible** - Containerized for consistent environments
- **🔄 Always Current** - Auto-fetches latest tool versions

Whether you're a DevOps engineer, cloud architect, security researcher, or full-stack developer, this environment has you covered.

---

## ✨ Features

### 🏗️ **Architecture Highlights**

- **Base Image**: Ubuntu 24.04 LTS (Noble Numbat)
- **Container Runtime**: Podman (rootful) with Docker format support
- **Shell**: Bash with pipefail for robust error handling
- **Package Management**: apt, Homebrew/Linuxbrew, pip, npm, cargo, dotnet
- **User Configuration**: Non-root `dev` user (UID 1001) with passwordless sudo
- **Systemd Support**: Full systemd integration for WSL2

### 🛠️ **Development Philosophy**

- **Latest Versions**: Tools auto-fetch latest releases from GitHub/official sources
- **Clean Builds**: Proper apt cleanup patterns minimize image size
- **Error Resilience**: Non-fatal patterns for optional components
- **Best Practices**: Following hadolint, shellcheck, and yamllint standards
- **Line Endings**: LF standardized across all files

---

## 📦 What's Included

<details>
<summary><b>🐍 Python Ecosystem (Click to expand)</b></summary>

- **Python**: 3.11, 3.12, 3.13 (all versions)
- **Package Manager**: pip, uv (ultra-fast package installer)
- **Security Tools**:
  - `checkov` - Infrastructure as Code scanner
  - `detect-secrets` - Secret detection
  - `pre-commit` - Git hook framework
- **Testing & Quality**: pytest, coverage tools

</details>

<details>
<summary><b>🟢 Node.js Ecosystem</b></summary>

- **Runtime**: Node.js (latest LTS via NVM)
- **Package Manager**: npm
- **Tools**:
  - `@openai/codex` - OpenAI Codex CLI for AI-assisted coding
  - `newman` - Postman CLI runner
  - `snyk` - Security vulnerability scanner

</details>

<details>
<summary><b>🔵 Go Ecosystem</b></summary>

- **Go**: Latest stable release
- **Tools**:
  - `bombardier` - HTTP benchmarking tool

</details>

<details>
<summary><b>☕ Java Ecosystem</b></summary>

- **JDK**: OpenJDK 8, 11, 17, 21
- **Build Tools**: Maven
- **Default**: Java 21

</details>

<details>
<summary><b>💜 .NET Ecosystem</b></summary>

- **SDK**: .NET 8.0, 9.0, 10.0
- **Tools**:
  - `dotnet-coverage` - Code coverage
  - `dotnet-format` - Code formatter
  - `gitversion` - Semantic versioning
  - `powershell` (pwsh) - PowerShell Core
- **Note**: .NET 10.0 installed via official dotnet-install.sh script

</details>

<details>
<summary><b>🗄️ Database Tools</b></summary>

- **Migration Tools**:
  - `flyway` - Database migration (latest)
  - `liquibase` - Database change management (latest)

</details>

<details>
<summary><b>🐳 Container & Kubernetes Tools</b></summary>

- **Container Runtimes**:
  - `podman` - Daemonless container engine
  - `buildah` - OCI image builder
- **Kubernetes**:
  - `helm` - Kubernetes package manager
  - `k9s` - Terminal UI for Kubernetes
  - `kompose` - Docker Compose to Kubernetes
  - `kustomize` - Kubernetes configuration management
- **Container Utilities**:
  - `dive` - Container image layer explorer
  - `lazydocker` - Terminal UI for Docker/Podman
  - `crane` - Container registry tool
  - `cosign` - Container signing and verification
  - `copa` - Automated container patching

</details>

<details>
<summary><b>🔐 Security & Scanning Tools</b></summary>

- **Vulnerability Scanners**:
  - `trivy` - All-in-one security scanner
  - `grype` - Vulnerability scanner
  - `syft` - SBOM generator
  - `kubescape` - Kubernetes security scanner
  - `osv-scanner` - OSV vulnerability scanner
  - `dependency-check` - OWASP dependency checker
  - `snyk` - Developer-first security scanner
- **Malware Detection**:
  - `clamav` - Antivirus scanner
- **Secret Detection**:
  - `detect-secrets` - Pre-commit secret scanner

</details>

<details>
<summary><b>🏗️ Infrastructure as Code (IaC) Tools</b></summary>

- **Terraform Ecosystem**:
  - `terraform` (via tenv - version manager)
  - `opentofu` - Open-source Terraform alternative
  - `terraform-docs` - Generate Terraform documentation
  - `tflint` - Terraform linter
  - `tfsec` - Terraform security scanner
  - `terrascan` - IaC security scanner
  - `tfupdate` - Terraform version updater
  - `infracost` - Cloud cost estimation
- **HashiCorp Tools**:
  - `packer` - Image builder
  - `vault` - Secrets management
  - `consul` - Service mesh

</details>

<details>
<summary><b>☁️ Cloud CLI Tools</b></summary>

- **Azure**: `az` (Azure CLI)
- **GitHub**: `gh` (GitHub CLI)
- **Multi-Cloud**: All major cloud SDKs via language runtimes

</details>

<details>
<summary><b>✅ Code Quality & Testing Tools</b></summary>

- **Linters**:
  - `hadolint` - Dockerfile linter
  - `shellcheck` - Shell script linter
  - `yamllint` - YAML linter
- **Testing**:
  - `container-structure-test` - Container validation
  - `act` - Run GitHub Actions locally (works with rootful Podman)
- **Version Control**:
  - `git` - Distributed version control
  - `git-lfs` - Git Large File Storage

</details>

<details>
<summary><b>🔧 Utilities & Productivity Tools</b></summary>

- **JSON/YAML Processing**: `jq`, `yq`
- **Package Managers**: `brew` (Homebrew/Linuxbrew)
- **Build Tools**: `make`, `cmake`, `cargo`
- **Compression**: `zip`, `unzip`, `tar`
- **Network**: `curl`, `wget`, `axel`
- **WSL Integration**: `wslu`, `wsl-setup`
- **AI/ML Tools**: `antigravity` - AI-powered development assistant

</details>

<details>
<summary><b>🔬 Advanced Security & Code Analysis</b></summary>

- **CodeQL**: GitHub's semantic code analysis engine (latest)
- **Static Analysis**: Multiple SAST tools across languages
- **Dependency Scanning**: Comprehensive dependency vulnerability detection

</details>

---

## 🚀 Quick Start

### Prerequisites

- **Windows 10/11** with WSL2 enabled
- **Podman Desktop** or **Podman CLI** installed
- **Git** for cloning this repository

### Installation

1. **Clone the repository**:

    ```bash
    git clone https://github.com/TMAtwood/wsl-ubuntu-24.04.git
    cd wsl-ubuntu-24.04
    ```

2. **Build the container image**:

    **Option A - PowerShell (Windows)**:

    ```powershell
    .\build.ps1
    ```

    **Option B - Bash (WSL/Linux) - Recommended**:

    ```bash
    bash build.sh
    ```

3. **Import to WSL2** (PowerShell as Administrator):

    ```powershell
    .\setup-wsl.ps1
    ```

    **Note**: The `setup-wsl.ps1` script automatically copies `.wslgconfig` to your Windows user profile (`$env:USERPROFILE\.wslgconfig`). This configuration file includes:
    - **High-DPI Scaling**: `WESTON_RDP_DEBUG_DESKTOP_SCALING_FACTOR=150` for balanced GUI scaling in WSLg
    - **Memory/CPU Limits**: 24GB RAM, 12 virtual processors
    - **Swap Configuration**: 6GB swap space at `C:\temp\wsl-swap.vhdx`
    - **WSL2 Settings**: Localhost forwarding, auto memory reclaim, and experimental features

4. **Start using your environment**:

    ```bash
    wsl -d tmatwood-ubuntu-24.04
    ```

That's it! You now have a fully-configured development environment. 🎉

---

## 🔨 Build Options

### Environment Variables

Customize the build by setting environment variables:

```bash
# Set custom version tag
export VERSION=1.0.0

# Build with custom image name
podman build --format docker -t myname/ubuntu-dev:latest .
```

### Build Scripts

| Script | Purpose | Platform |
| -------- | --------- | ---------- |
| `build.ps1` | Podman build with error handling (PowerShell) | Windows |
| `build.sh` | Podman build with error handling (Bash) | Linux/WSL |

Both build scripts include:

- GitVersion integration with fallback to default version
- Comprehensive error handling and colored output
- Build timing and progress reporting
- Automatic image tagging (version and latest)
- Support for `--format docker` flag for compatibility with Docker-specific Dockerfile directives

---

## ✅ Testing

This project includes **242 automated tests** using [Container Structure Test](https://github.com/GoogleContainerTools/container-structure-test).

### Local Testing with GitHub Actions Workflow

You can use `act` to test GitHub Actions workflows locally (works with rootful Podman):

```bash
# Run act to test GitHub Actions workflows locally
act
```

This runs the same build and test steps as the GitHub Actions CI/CD pipeline, including:

- ✅ Building the container image with Podman
- ✅ Running container-structure-test validation
- ✅ Using GitVersion for semantic versioning
- ✅ Mimicking the exact GitHub Actions workflow steps

### Run Tests Only

```bash
# Test the default image
bash run_tests.sh

# Test a specific image
IMAGE_NAME=localhost/tmatwood/ubuntu-24.04:0.1.0 bash run_tests.sh
```

### Test Categories

- ✅ System package verification
- ✅ Version control tools (git, git-lfs, gh)
- ✅ Programming language runtimes (Python, Node, Go, Java, .NET)
- ✅ Database migration tools (Flyway, Liquibase)
- ✅ Container tools (Podman, Buildah, Helm, K9s)
- ✅ Security scanners (Trivy, Grype, Syft, ClamAV)
- ✅ IaC tools (Terraform, Packer, Vault)
- ✅ Cloud CLIs (Azure, GitHub)
- ✅ Code quality tools (hadolint, shellcheck, yamllint)

See [TESTING.md](docs/TESTING.md) for detailed testing documentation.

---

## 💡 Usage Examples

### Python Development

```bash
# Multiple Python versions available
python3.13 --version
python3.12 --version
python3.11 --version

# Use uv for fast package installation
uv pip install requests

# Run security checks
checkov -d .
detect-secrets scan
```

### Container Development

```bash
# Build with Podman
podman build -t myapp:latest .

# Scan for vulnerabilities
trivy image myapp:latest
grype myapp:latest

# Explore image layers
dive myapp:latest
```

### Kubernetes Management

```bash
# Manage clusters with K9s
k9s

# Deploy with Helm
helm install myapp ./chart

# Convert Docker Compose
kompose convert -f docker-compose.yml
```

### Infrastructure as Code

```bash
# Terraform development
terraform init
terraform plan
tflint --init
tfsec .

# Check costs
infracost breakdown --path .

# Generate docs
terraform-docs markdown . > README.md
```

### Security Scanning

```bash
# Multi-tool vulnerability scanning
trivy fs .
grype dir:.
osv-scanner scan .

# Generate SBOM
syft . -o spdx-json

# Scan for secrets
detect-secrets scan --all-files

# Kubernetes security
kubescape scan framework nsa .
```

---

## 🎨 Customization

### Adding New Tools

1. Edit `Dockerfile` to add installation steps
2. Update `tests.yaml` to add validation tests
3. Run pre-commit checks:

    ```bash
    pre-commit run --all-files
    ```

### Modifying Users

The default `dev` user (UID 1001) has passwordless sudo. To change:

```dockerfile
# In Dockerfile
ENV USER=yourname
ENV GROUP=yourgroup
```

### Homebrew Access

Both `root` and `dev` users can access Homebrew:

- Dev user: Native brew environment
- Root user: Symlinked to `/usr/local/bin/brew`

---

## 🐛 Troubleshooting

### VPN Network Connectivity

This image includes **wsl-vpnkit** for maintaining network connectivity when connected to VPNs on your Windows host.

**What is wsl-vpnkit?**

- Automatically provides network connectivity to WSL2 when blocked by VPN
- Uses gvisor-tap-vsock for transparent network bridging
- Runs as a systemd service (starts automatically)
- No Windows host configuration required

**Usage:**

```bash
# Check status
systemctl status wsl-vpnkit

# View logs
journalctl -u wsl-vpnkit -f

# Restart if needed
sudo systemctl restart wsl-vpnkit
```

**Troubleshooting VPN connectivity:**

If you experience network issues while connected to a VPN:

1. The service should start automatically with WSL
2. Check service status: `systemctl status wsl-vpnkit`
3. Test connectivity: `ping 8.8.8.8`
4. For debugging: `sudo DEBUG=1 /usr/local/bin/wsl-vpnkit`

For more information, see [sakai135/wsl-vpnkit](https://github.com/sakai135/wsl-vpnkit).

---

### Common Issues

<details>
<summary><b>Running GitHub Actions locally with act</b></summary>

This environment uses **rootful Podman** for better compatibility with tools like `act`. The Podman socket is configured at `/run/podman/podman.sock` and starts automatically via systemd.

```bash
# Run act to test workflows locally
act

# Or use the convenience script
./local-test.sh
```

**Note**: We switched from rootless to rootful Podman for developer convenience in this WSL environment. For production deployments, rootless Podman is still recommended.

For more details about this decision, see [CLAUDE.md](docs/CLAUDE.md#switching-from-rootless-to-rootful-podman-for-act-compatibility).
</details>

<details>
<summary><b>Build fails with "permission denied"</b></summary>

Ensure you're running Podman/Docker with appropriate permissions:

```bash
# Add user to podman/docker group (Linux)
sudo usermod -aG podman $USER
newgrp podman
```

</details>

<details>
<summary><b>WSL import fails</b></summary>

1. Ensure WSL2 is enabled: `wsl --set-default-version 2`
2. Check available disk space
3. Try unregistering old distro: `wsl --unregister tmatwood-ubuntu-24.04`

</details>

<details>
<summary><b>Tools not in PATH</b></summary>

Restart your shell or source the profile:

```bash
source ~/.bashrc
```

</details>

<details>
<summary><b>Systemd services not starting</b></summary>

WSL2 systemd support requires Windows 11 or Windows 10 with recent updates:

```bash
# Check systemd status
systemctl status
```

</details>

### Getting Help

- 📖 Check [TESTING.md](docs/TESTING.md) for test documentation
- 🐛 [Open an issue](https://github.com/TMAtwood/wsl-ubuntu-24.04/issues)
- 💬 Review existing issues for solutions

---

## 🔧 Development

### Pre-commit Hooks

This project uses pre-commit hooks for code quality:

```bash
# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

Configured hooks:

- `hadolint` - Dockerfile linting (errors only)
- `yamllint` - YAML validation
- Standard file checks (trailing whitespace, EOF, merge conflicts, etc.)

### Line Endings

All files default to **LF** line endings (configured via `.gitattributes`):

- Windows scripts (`.ps1`, `.bat`, `.cmd`): CRLF
- Everything else: LF

---

## 📊 Project Stats

- **100+ Tools**: Curated selection of industry-standard tools
- **242 Tests**: Comprehensive validation suite
- **5 Language Runtimes**: Python, Node.js, Go, Java, .NET
- **20+ Security Tools**: From scanning to secrets detection
- **15+ IaC Tools**: Complete Terraform ecosystem
- **10+ Container Tools**: Build, scan, deploy, and manage

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-tool`
3. **Add the tool** to `Dockerfile`
4. **Add tests** to `tests.yaml`
5. **Run pre-commit**: `pre-commit run --all-files`
6. **Test your changes**: `bash run_tests.sh`
7. **Commit your changes**: `git commit -m 'Add amazing-tool'`
8. **Push to your fork**: `git push origin feature/amazing-tool`
9. **Open a Pull Request**

### Contribution Guidelines

- ✅ All tools must have corresponding tests
- ✅ Follow existing patterns for consistency
- ✅ Update documentation (README, TESTING.md)
- ✅ Ensure hadolint, shellcheck, yamllint pass
- ✅ Test the full build before submitting

---

## 📝 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

---

## 🙏 Acknowledgments

- **Ubuntu** - For the solid foundation
- **Microsoft** - For WSL2 and amazing Windows/Linux integration
- **HashiCorp** - For Terraform, Packer, Vault, and Consul
- **GitHub** - For CodeQL and CLI tools
- **Aqua Security** - For Trivy
- **Anchore** - For Grype and Syft
- **All open-source contributors** - This project stands on the shoulders of giants

---

## 🌟 Star History

If this project saves you time, please consider giving it a ⭐!

[![Star History Chart](https://api.star-history.com/svg?repos=TMAtwood/wsl-ubuntu-24.04&type=Date)](https://star-history.com/#TMAtwood/wsl-ubuntu-24.04&Date)

---

<div align="center">

**Built with ❤️ for the developer community**

[Report Bug](https://github.com/TMAtwood/wsl-ubuntu-24.04/issues) · [Request Feature](https://github.com/TMAtwood/wsl-ubuntu-24.04/issues) · [Documentation](https://github.com/TMAtwood/wsl-ubuntu-24.04/wiki)

</div>
