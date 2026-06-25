# Container Structure Tests

This document describes the testing strategy for the WSL Ubuntu 26.04 development image.

## Overview

We use [Container Structure Test](https://github.com/GoogleContainerTools/container-structure-test) to verify that all tools and applications are properly installed and functional in the container image.

## Test File

- **tests.yaml** - Main test configuration file containing all command tests

## Test Categories

The tests are organized into the following categories:

### 1. System Checks

- apt-get package system validation

### 2. Version Control

- git
- git-lfs

### 3. Package Managers & Build Tools

- Homebrew/Linuxbrew (brew)
- apt
- cargo (Rust)
- make

### 4. Python & Tools

- Python 3.11, 3.12, 3.13
- pip
- checkov (IaC security scanner)
- detect-secrets
- pre-commit
- uv (fast Python package installer)

### 5. Node.js & NPM Tools

- Node.js
- npm
- nvm
- newman (Postman CLI)
- snyk (security scanner)

### 6. Go & Tools

- Go
- bombardier (HTTP benchmarking tool)

### 7. .NET & Tools

- .NET SDK 8.0, 9.0 & 10.0
- dotnet-coverage
- dotnet-format
- GitVersion
- PowerShell Core
- **Note**: .NET 10.0 installed via official dotnet-install.sh script

### 8. Java

- OpenJDK 21
- Maven

### 9. Database Tools

- Flyway (database migration)
- Liquibase (database migration)

### 10. Container & Kubernetes Tools

- Podman
- Buildah
- Helm
- k9s
- Kompose
- Kustomize
- Dive (image analyzer)
- Lazydocker
- Crane
- Cosign (container signing)
- Copa (container patching)

### 11. Security & Scanning Tools

- Trivy (vulnerability scanner)
- Grype (vulnerability scanner)
- Syft (SBOM generator)
- Kubescape (Kubernetes security)
- OSV-Scanner
- Dependency-Check
- ClamAV (antivirus)

### 12. Infrastructure as Code Tools

- Terraform (via tenv)
- OpenTofu
- terraform-docs
- tflint
- tfsec
- terrascan
- tfupdate
- Infracost
- Packer
- Vault
- Consul

### 13. Cloud CLI Tools

- Azure CLI (az)
- GitHub CLI (gh)

### 14. Code Quality & Testing Tools

- hadolint (Dockerfile linter)
- ShellCheck (shell script linter)
- yamllint
- container-structure-test
- act (GitHub Actions local runner)

### 15. Utilities

- jq (JSON processor)
- yq (YAML processor)
- wget
- curl
- tmux
- htop
- btop
- ncdu (disk usage analyzer)
- tldr (simplified man pages)
- mkcert (local CA)

### 16. Text Editors

- nano
- vim

### 17. Compression Tools

- zip/unzip
- 7z
- tar

### 18. System Services

- systemd/systemctl

### 19. Code Analysis

- CodeQL

## Running Tests

### Prerequisites

1. Build the container image first:

    ```bash
    # Using PowerShell on Windows
    .\build.ps1

    # Or using bash in WSL
    bash build-podman.sh
    ```

2. Ensure `container-structure-test` is installed (it's included in the image via Homebrew)

### Run All Tests

```bash
# Using default image name
bash run_tests.sh

# Or specify a custom image name
IMAGE_NAME=localhost/tmatwood/ubuntu-26.04:0.1.0 bash run_tests.sh
```

### Run Tests on Specific Image

```bash
container-structure-test test \
  --image localhost/tmatwood/ubuntu-26.04:latest \
  --config tests.yaml
```

### Run Specific Tests

To run only certain tests, you can filter by test name:

```bash
container-structure-test test \
  --image localhost/tmatwood/ubuntu-26.04:latest \
  --config tests.yaml \
  --test-report output.json
```

## Test Output

Tests will output:

- ✅ **PASS** - Test succeeded
- ❌ **FAIL** - Test failed with error details

Example output:

```
====================================
====== Test file: tests.yaml ======
====================================
Running tests for image: localhost/tmatwood/ubuntu-26.04:latest

=== RUN: Command Test: git installation
--- PASS
duration: 0.15s

=== RUN: Command Test: python installation
--- PASS
duration: 0.12s

...

=================
All tests passed!
=================
```

## Adding New Tests

When adding new tools to the Dockerfile, add corresponding tests to `tests.yaml`:

```yaml
commandTests:
  - name: "new-tool installation"
    command: "new-tool"
    args: ["--version"]
    expectedOutput: ["expected string in output"]
```

## Continuous Integration

These tests should be run:

1. **Before committing** - Ensure changes don't break installations
2. **In CI/CD pipeline** - Automated validation on every build
3. **Before publishing** - Final verification before pushing images

## Troubleshooting

### Test Fails with "command not found"

- Check if the tool is actually installed in the Dockerfile
- Verify the command is in the PATH for the `dev` user
- Check if the tool requires a specific user context (root vs dev)

### Test Fails with Unexpected Output

- Run the command manually in the container to see actual output
- Update `expectedOutput` or use regex patterns
- Check if tool output format changed in newer versions

### Permission Issues

- Some tests may require root privileges
- Adjust `containerRunOptions.user` if needed
- Or create separate test sections for root-only commands

## Best Practices

1. **Keep tests atomic** - Each test should verify one thing
2. **Use version checks** - Prefer `--version` over `which`
3. **Expect specific output** - Don't just check exit codes
4. **Document test purpose** - Use descriptive test names
5. **Test actual functionality** - Not just presence of binaries
6. **Update tests with Dockerfile** - Keep them in sync

## Resources

- [Container Structure Test Documentation](https://github.com/GoogleContainerTools/container-structure-test)
- [Container Structure Test Examples](https://github.com/GoogleContainerTools/container-structure-test/tree/master/examples)
