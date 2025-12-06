# Pre-Commit Enhancements Guide

This document describes the enhanced pre-commit configuration and installation requirements.

## Overview

The enhanced `.pre-commit-config-enhanced.yaml` adds comprehensive security, quality, and compliance checks to your CI/CD pipeline.

## New Hooks Added

### 1. Security Enhancements

#### Markdownlint

**Purpose**: Lint markdown files for consistency and quality
**Hook**: `igorshubovych/markdownlint-cli`
**Installation**: Auto-installed by pre-commit
**Benefits**:

- Consistent markdown formatting
- Better documentation quality
- Catches common markdown errors

#### Detect-Secrets (Enhanced)

**Purpose**: More comprehensive secret detection than `detect-private-key`
**Hook**: `Yelp/detect-secrets`
**Installation**: Auto-installed by pre-commit
**Setup Required**:

```bash
# Generate baseline file
detect-secrets scan > .secrets.baseline
```

**Benefits**:

- Detects API keys, tokens, passwords
- Configurable with baseline file
- Prevents accidental secret commits

#### Gitleaks

**Purpose**: Additional secret scanner with different detection patterns
**Hook**: `gitleaks/gitleaks`
**Installation**: Auto-installed by pre-commit
**Benefits**:

- Complements detect-secrets
- Industry-standard secret detection
- Low false-positive rate

#### Dockle

**Purpose**: Docker security and best practices linter
**Hook**: Local (requires manual installation)
**Installation**:

```bash
# Linux/WSL
curl -L -o dockle.deb https://github.com/goodwithtech/dockle/releases/download/v0.4.14/dockle_0.4.14_Linux-64bit.deb
sudo dpkg -i dockle.deb
rm dockle.deb

# macOS
brew install goodwithtech/r/dockle

# Windows (via Chocolatey)
choco install dockle
```

**Benefits**:

- CIS Benchmark compliance checks
- Dockerfile security best practices
- Image configuration validation

#### Trivy

**Purpose**: Vulnerability scanner for containers and configurations
**Hook**: Local (requires manual installation)
**Installation**:

```bash
# Linux/WSL
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# macOS
brew install aquasecurity/trivy/trivy

# Windows (via Chocolatey)
choco install trivy
```

**Benefits**:

- CVE detection in base images
- Configuration scanning
- SBOM generation

### 2. Code Quality

#### ShellCheck

**Purpose**: Lint shell scripts for common errors
**Hook**: `shellcheck-py/shellcheck-py`
**Installation**: Auto-installed by pre-commit
**Benefits**:

- Catches shell script bugs
- Best practices enforcement
- Cross-shell compatibility checks

#### ActionLint

**Purpose**: Lint GitHub Actions workflows
**Hook**: `rhysd/actionlint`
**Installation**: Auto-installed by pre-commit
**Benefits**:

- Validates GitHub Actions syntax
- Catches workflow errors early
- Best practices enforcement

#### Prettier

**Purpose**: Code formatter for YAML, JSON, Markdown
**Hook**: `pre-commit/mirrors-prettier`
**Installation**: Auto-installed by pre-commit
**Benefits**:

- Consistent formatting
- Auto-fixes formatting issues
- Reduces merge conflicts

#### Ruff (Python)

**Purpose**: Fast Python linter and formatter
**Hook**: `astral-sh/ruff-pre-commit`
**Installation**: Auto-installed by pre-commit
**Benefits**:

- Extremely fast (10-100x faster than alternatives)
- Replaces flake8, black, isort, and more
- Auto-fixes many issues

### 3. PowerShell

#### PSScriptAnalyzer

**Purpose**: PowerShell script linter
**Hook**: Local (requires PowerShell)
**Installation**:

```powershell
# Already installed if you have PowerShell 7+
# If not installed:
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

**Benefits**:

- PowerShell best practices
- Security issue detection
- Performance recommendations

### 4. Container Testing

#### Container Structure Test

**Purpose**: Validate container structure and contents
**Hook**: Local (requires manual installation)
**Installation**: Already documented in your project
**Benefits**:

- Validates container contents
- Command output testing
- Metadata validation

## Installation Steps

### 1. Install Required Tools

```bash
# Install tools that require manual installation
# (Most hooks are auto-installed by pre-commit)

# Dockle
curl -L -o dockle.deb https://github.com/goodwithtech/dockle/releases/download/v0.4.14/dockle_0.4.14_Linux-64bit.deb
sudo dpkg -i dockle.deb
rm dockle.deb

# Trivy
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# PowerShell (if not already installed)
# See: https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu
```

### 2. Initialize Detect-Secrets

```bash
# Generate secrets baseline
detect-secrets scan > .secrets.baseline

# Review and approve the baseline
detect-secrets audit .secrets.baseline
```

### 3. Replace Configuration

```bash
# Backup current config
cp .pre-commit-config.yaml .pre-commit-config.yaml.backup

# Use enhanced config
cp .pre-commit-config-enhanced.yaml .pre-commit-config.yaml

# Install hooks
pre-commit install

# Run on all files (first time)
pre-commit run --all-files
```

### 4. Create .markdownlintignore

```bash
cat > .markdownlintignore << 'EOF'
# Ignore non-markdown files
.actrc
wsl-vpnkit.service
*.ps1
*.sh
EOF
```

## Comparison: Current vs Enhanced

| Feature | Current | Enhanced |
| --------- | --------- | ---------- |
| Secret Detection | ✅ Basic (detect-private-key) | ✅ Advanced (detect-secrets + gitleaks) |
| Markdown Linting | ❌ None | ✅ markdownlint |
| Docker Security | ✅ hadolint | ✅ hadolint + dockle + trivy |
| Shell Linting | ⚠️ Partial (via hadolint) | ✅ Dedicated shellcheck |
| GitHub Actions | ❌ None | ✅ actionlint |
| Code Formatting | ❌ None | ✅ prettier |
| Python Linting | ❌ None | ✅ ruff |
| PowerShell Linting | ❌ None | ✅ PSScriptAnalyzer |
| Container Testing | ⚠️ Separate script | ✅ Integrated in pre-commit |

## Performance Impact

The enhanced configuration adds approximately:

- **Time per commit**: +10-30 seconds (depending on changes)
- **Initial setup**: +5-10 minutes (installing tools)
- **False positives**: Minimal (most hooks are well-tuned)

## Gradual Adoption Strategy

If the full enhanced config is too heavy, adopt gradually:

### Phase 1: Security First (Highest Priority)

```yaml
# Add these hooks first
- detect-secrets
- gitleaks
- dockle
- trivy
```

### Phase 2: Quality Improvements

```yaml
# Add after Phase 1 is stable
- markdownlint
- shellcheck
- actionlint
```

### Phase 3: Formatting & Polish

```yaml
# Add last
- prettier
- ruff
- PSScriptAnalyzer
```

## Skipping Hooks for Specific Commits

If you need to bypass a hook temporarily:

```bash
# Skip specific hook
SKIP=dockle git commit -m "WIP: testing changes"

# Skip all hooks (not recommended)
git commit --no-verify -m "Emergency fix"
```

## Troubleshooting

### Dockle/Trivy: "Image not found"

These hooks run on the built container image. Build it first:

```bash
./build.ps1
```

### Detect-Secrets: Too many false positives

Update `.secrets.baseline`:

```bash
detect-secrets scan --baseline .secrets.baseline
detect-secrets audit .secrets.baseline
```

### Markdownlint: Conflicts with IDE linter

Configure both to use same `.markdownlint.yaml` config.

## CI/CD Integration

Add to GitHub Actions workflow:

```yaml
- name: Run pre-commit hooks
  run: |
    pip install pre-commit
    pre-commit run --all-files
```

## Additional Resources

- [Pre-commit hooks catalog](https://pre-commit.com/hooks.html)
- [Dockle documentation](https://github.com/goodwithtech/dockle)
- [Trivy documentation](https://aquasecurity.github.io/trivy/)
- [Detect-Secrets documentation](https://github.com/Yelp/detect-secrets)
- [Gitleaks documentation](https://github.com/gitleaks/gitleaks)
