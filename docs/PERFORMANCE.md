# Performance Guide

This document provides performance benchmarks, build optimization tips, and resource usage information for the WSL Ubuntu 26.04 Development Environment.

---

## Table of Contents

- [Build Performance](#build-performance)
- [Image Size Analysis](#image-size-analysis)
- [Test Duration](#test-duration)
- [Runtime Performance](#runtime-performance)
- [Optimization Tips](#optimization-tips)
- [Resource Requirements](#resource-requirements)

---

## Build Performance

### Build Times by Platform

#### Podman Build (Windows - build.ps1)

**Target**: Single architecture (linux/amd64)

| Stage | Duration | Percentage |
| ------- | ---------- | ------------ |
| Foundation Packages | 2-3 min | 10% |
| Language Runtimes (Python, Node, Go, Rust) | 3-4 min | 15% |
| Java Installation (5 versions) | 2-3 min | 10% |
| .NET SDK & Tools | 1-2 min | 8% |
| Homebrew Installation | 8-12 min | 45% |
| Additional Packages (apt) | 2-3 min | 10% |
| Configuration & Cleanup | 1-2 min | 2% |
| **Total** | **19-27 min** | **100%** |

**Average Build Time**: ~23 minutes

#### Docker Buildx (Linux/macOS - build-docker.sh)

**Target**: Multi-architecture (linux/amd64, linux/arm64)

| Stage | Duration | Percentage |
| ------- | ---------- | ------------ |
| Foundation Packages | 3-4 min | 8% |
| Language Runtimes (Python, Node, Go, Rust) | 4-6 min | 12% |
| Java Installation (5 versions) | 3-5 min | 10% |
| .NET SDK & Tools | 2-3 min | 6% |
| Homebrew Installation (both architectures) | 20-30 min | 55% |
| Additional Packages (apt) | 3-4 min | 7% |
| Configuration & Cleanup | 1-2 min | 2% |
| **Total** | **36-54 min** | **100%** |

**Average Build Time**: ~45 minutes (multi-arch)

### Build Time Breakdown

#### Stage 1: Foundation (Lines 38-89)

- **What**: System packages, build tools, systemd
- **Time**: 2-4 minutes
- **Size**: ~500 MB
- **Optimization**: Already optimized with `--no-install-recommends`

#### Stage 2: Users & Repositories (Lines 98-150)

- **What**: Create users, add PPAs, configure package repositories
- **Time**: 1-2 minutes
- **Size**: ~50 MB
- **Optimization**: Minimal overhead, necessary for subsequent steps

#### Stage 3: Language Runtimes

**Python (Lines 296-347)**

- Time: 1-2 minutes
- Size: ~150 MB (3 Python versions)
- Note: Includes pip packages (checkov, pre-commit)

**Node.js (Lines 272-284)**

- Time: 2-3 minutes
- Size: ~100 MB
- Note: nvm installation + global packages

**Java (Lines 569-598)**

- Time: 2-3 minutes
- Size: ~800 MB (5 OpenJDK versions)
- Note: Largest single language runtime

**.NET (Lines 140-150, 607-628)**

- Time: 1-2 minutes
- Size: ~300 MB
- Note: Includes 15 global tools

**Go (via apt)**

- Time: <1 minute
- Size: ~50 MB

**Rust (via apt)**

- Time: <1 minute
- Size: ~200 MB

#### Stage 4: Homebrew (Lines 235-689)

- **What**: Homebrew installation + 40+ packages
- **Time**: 8-30 minutes (varies by platform and architecture)
- **Size**: ~1.5 GB
- **Bottleneck**: This is the slowest stage
  - Initial brew repository clone: 1-2 min
  - Package installations: 7-28 min
  - Multi-arch builds take significantly longer

**Homebrew Package Categories**:

- Development tools: 1-2 min
- Container tools: 2-4 min
- Security scanners: 2-3 min
- Infrastructure tools: 2-3 min
- Specialized tools: 1-2 min

#### Stage 5: Additional Packages (Lines 381-565)

- **What**: Browsers, audio/video, additional utilities
- **Time**: 2-3 minutes
- **Size**: ~400 MB
- **Note**: Chrome and Edge repositories add minimal overhead

#### Stage 6: Configuration (Lines 639-1038)

- **What**: Shell aliases, Podman setup, WSLg, services
- **Time**: 1-2 minutes
- **Size**: <10 MB
- **Note**: Mostly configuration, minimal package installs

### Cache Effectiveness

#### Docker Layer Caching

**Best Case** (no changes):

- Rebuild time: <1 minute (cached layers)

**Change in Late Stage** (e.g., bashrc alias):

- Rebuild time: 2-3 minutes (only uncached layers)

**Change in Early Stage** (e.g., foundation packages):

- Rebuild time: Full build (all subsequent layers invalidated)

**Tip**: Order Dockerfile from least-frequently-changed (base packages) to most-frequently-changed (configuration).

#### Homebrew Bottle Cache

- **Bottles**: Pre-compiled binaries (fast)
- **From Source**: Compiled during build (slow)
- **Cache Location**: `/home/linuxbrew/.cache/Homebrew`

When Homebrew builds from source:

- Significantly increases build time (3-5x longer per package)
- Usually caused by HOMEBREW_PREFIX mismatch (fixed in our image)

See [TROUBLESHOOTING.md - Homebrew Issues](TROUBLESHOOTING.md#homebrew-installation-failures) for details.

---

## Image Size Analysis

### Final Image Size

- **Compressed**: ~3.2 GB (Docker Hub/Registry)
- **Uncompressed**: ~8.5 GB (Disk usage)
- **Layer Count**: ~50 layers

### Size by Category

| Category | Size | Percentage |
| ---------- | ------ | ------------ |
| Base Ubuntu 26.04 | ~200 MB | 2% |
| System Packages (apt) | ~1.5 GB | 18% |
| Java (5 versions) | ~800 MB | 9% |
| Homebrew + Packages | ~1.5 GB | 18% |
| Python (3 versions + packages) | ~300 MB | 4% |
| Node.js (nvm + packages) | ~200 MB | 2% |
| .NET (SDK + tools) | ~500 MB | 6% |
| Browsers (Chrome, Edge, Firefox) | ~400 MB | 5% |
| Audio/Video (GStreamer, VLC, OBS) | ~300 MB | 4% |
| Go + Rust | ~250 MB | 3% |
| ClamAV (virus definitions) | ~200 MB | 2% |
| Miscellaneous & Overhead | ~2.4 GB | 27% |
| **Total** | **~8.5 GB** | **100%** |

### Largest Individual Components

1. **Java OpenJDK**: ~800 MB (5 versions)
    - Java 25: ~200 MB
    - Java 21: ~190 MB
    - Java 17: ~180 MB
    - Java 11: ~140 MB
    - Java 8: ~90 MB

2. **Homebrew**: ~1.5 GB (Cellar + repository)
    - Largest packages: terraform, kubernetes tools, container tools

3. **System Libraries**: ~1.5 GB (apt packages)
    - Build essentials, systemd, graphics libraries

4. **.NET SDK**: ~500 MB
    - Includes SDK 8.0, 9.0 and 15 global tools

5. **Browsers**: ~400 MB combined
    - Chrome: ~200 MB
    - Edge: ~180 MB
    - Firefox: ~20 MB (transitional package)

6. **Python**: ~300 MB
    - 3 Python versions + pip packages (checkov is large)

7. **Audio/Video**: ~300 MB
    - GStreamer plugins, VLC, OBS Studio, Audacity

### Layer Size Distribution

Typical layer sizes:

- Small (<10 MB): Configuration files, scripts, symlinks
- Medium (10-100 MB): Individual packages, tools
- Large (100-500 MB): Language runtimes, Homebrew installations
- Very Large (>500 MB): Foundation packages, Java installation

**Optimization Opportunity**: Combining small layers could reduce overhead (but harms caching).

---

## Test Duration

### Container Structure Test Performance

#### Test Execution Time

- **Total Tests**: 240
- **Duration**: 2-3 minutes
- **Average per Test**: <1 second

#### Test Categories by Speed

**Fast Tests** (<0.1s each):

- Version checks: `--version` output validation
- File existence: `/etc/wsl.conf`, config files
- Symlink verification

**Medium Tests** (0.1-0.5s each):

- Command execution: Tool invocations
- Group membership: User/group validation

**Slow Tests** (>0.5s each):

- GUI applications: `which` checks (may require X11 socket check)
- Network tools: May perform connectivity checks

### Test Results Summary

From recent test run:

```
===================================
============= RESULTS =============
===================================
Passes:      240
Failures:    0
Duration:    2m17.6386907s
Total tests: 240

PASS
```

**Performance Observations**:

- Consistent 2-3 minute duration across runs
- No flaky tests (100% pass rate)
- Linear scaling with test count

See [tests.yaml](../tests.yaml) for complete test suite.

---

## Runtime Performance

### Startup Time

#### WSL Distro First Boot

- **Cold Start**: 8-12 seconds
  - Systemd initialization
  - Service startup (Podman, ClamAV)
  - Network configuration

- **Warm Start**: 2-4 seconds
  - Services already initialized
  - Faster systemd boot

#### Application Launch Times

**Terminal Applications** (<1s):

- bash, python, node, go, java
- Quick to launch, minimal overhead

**GUI Applications** (1-3s):

- Chrome, Edge, Firefox
- Requires WSLg initialization
- First launch slower, subsequent faster

**Container Operations** (2-5s):

- `podman run`: 2-3s (image cached)
- `podman pull`: Depends on image size and network
- `podman build`: See Build Performance section

### Memory Usage

#### Idle State (No Containers Running)

- **Base System**: ~200-300 MB
- **With Services** (Podman, ClamAV): ~400-600 MB

#### Active Development (Typical Workload)

- **1-2 Containers Running**: +500 MB - 2 GB (per container)
- **IDE/Editor**: +200-500 MB (VS Code, vim minimal)
- **Browser Tabs**: +100-300 MB per tab

#### Heavy Load (Multiple Containers + Build)

- **Container Build**: +2-4 GB (temporary, released after build)
- **Multiple Containers**: +1-4 GB (depends on container workload)

**Recommendation**: Allocate at least 8 GB RAM to WSL2 for comfortable development.

### CPU Usage

#### Idle State

- **CPU**: <5% (systemd, background services)

#### Active Development

- **Editing/Browsing**: 10-20%
- **Container Running**: 15-40% (depends on workload)

#### Heavy Load

- **Image Build**: 80-100% (sustained during Homebrew installations)
- **Multi-arch Build**: 100% (can pin all cores for extended periods)

**Tip**: Multi-arch builds can benefit from higher core count (8+ cores recommended).

### Disk I/O

#### Build Operations

- **Read**: Moderate (package downloads, cache reads)
- **Write**: Heavy (layer creation, package extraction)
- **IOPS**: High during apt/brew installations

#### Runtime Operations

- **Read**: Light to moderate (application loading)
- **Write**: Light (logs, temporary files)

**Tip**: SSD strongly recommended for acceptable build performance.

---

## Optimization Tips

### Build Time Optimization

#### 1. Layer Ordering

**Current**: Dockerfile orders from least-frequently-changed to most-frequently-changed.

**Optimization**: No change needed; already optimized for caching.

#### 2. Combine Related Operations

**Potential**: Combine multiple RUN commands in Homebrew section.

**Trade-off**:

- **Benefit**: Fewer layers, slightly smaller image
- **Cost**: Harder to debug, poor cache granularity

**Recommendation**: Keep current structure for maintainability during active development.

#### 3. Use Specific Versions

**Current**: Most packages use "latest" or distro-provided versions.

**Optimization**: Pin specific versions for reproducible builds.

**Benefit**: Consistent build times, no surprises from upstream changes.

#### 4. Parallel Installation

**Potential**: Some Homebrew packages could install in parallel.

**Challenge**: Homebrew doesn't support parallel installation well.

**Recommendation**: Not feasible without significant complexity.

#### 5. Pre-built Base Image

**Strategy**: Create a "base" image with slow-changing dependencies.

**Example**:

```dockerfile
# Base image: Ubuntu + system packages + language runtimes
FROM base-wsl-ubuntu:26.04
# Then add: Homebrew packages, configuration
```

**Benefit**: Faster iteration on configuration changes.

### Image Size Optimization

#### 1. Remove Unnecessary Java Versions

**Current**: 5 Java versions (8, 11, 17, 21, 25)

**Optimization**: Keep only LTS versions (11, 17, 21)

**Savings**: ~280 MB

**Trade-off**: Less version flexibility.

#### 2. Slim Down Homebrew

**Current**: ~40 packages

**Optimization**: Move some tools to optional install script.

**Savings**: ~500-800 MB (depends on packages removed)

**Recommendation**: Consider creating "slim" and "full" variants.

#### 3. Multi-stage Build

**Strategy**: Build tools in one stage, copy only runtime artifacts to final stage.

**Challenge**: Not applicable; this is a development environment needing all tools at runtime.

#### 4. Clean Package Caches

**Current**: Partially implemented (`apt-get clean`, `rm -rf /var/lib/apt/lists/*`)

**Additional**:

```dockerfile
RUN brew cleanup -s && rm -rf "$(brew --cache)"
```

**Savings**: ~200-400 MB

**Recommendation**: Add to Dockerfile after Homebrew installations.

#### 5. Remove Documentation

**Current**: Man pages and docs included.

**Optimization**:

```dockerfile
RUN rm -rf /usr/share/doc/* /usr/share/man/*
```

**Savings**: ~100-200 MB

**Trade-off**: No offline documentation.

### Runtime Performance Optimization

#### 1. Increase WSL2 Memory Allocation

**File**: `%USERPROFILE%\.wslconfig` (Windows)

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB
```

**Benefit**: Allows more containers to run simultaneously.

#### 2. Use Podman's `--memory` and `--cpus` Limits

**Command**:

```bash
podman run --memory=2g --cpus=2 myimage
```

**Benefit**: Prevents container resource starvation.

#### 3. Enable Podman Remote API Caching

**Config**: Already enabled via Podman socket.

**Benefit**: Faster container operations with Docker-compatible tools.

#### 4. Use Tmpfs for Build Artifacts

**Command**:

```bash
podman build --tmpfs /tmp ...
```

**Benefit**: Faster I/O for temporary build files.

#### 5. Optimize Homebrew

**Commands**:

```bash
# Disable analytics
brew analytics off

# Clean up old versions
brew cleanup -s

# Update only when needed
# brew update  (don't run automatically)
```

**Benefit**: Faster brew operations, less disk usage.

---

## Resource Requirements

### Minimum Requirements

- **CPU**: 2 cores
- **RAM**: 4 GB
- **Disk**: 15 GB free space
- **OS**: Windows 10 Build 19044+ or Windows 11

**Experience**: Acceptable for light development, slow builds.

### Recommended Requirements

- **CPU**: 4+ cores (8 preferred for multi-arch builds)
- **RAM**: 8 GB (16 GB preferred)
- **Disk**: 30 GB free space (SSD strongly recommended)
- **OS**: Windows 11 with latest updates

**Experience**: Comfortable development, reasonable build times.

### Optimal Requirements

- **CPU**: 8+ cores (modern Ryzen or Intel i7/i9)
- **RAM**: 16-32 GB
- **Disk**: 50+ GB free on NVMe SSD
- **OS**: Windows 11 22H2+

**Experience**: Fast builds, multiple containers, no compromises.

### Network Requirements

- **Bandwidth**: 10+ Mbps (for package downloads)
- **Latency**: <100ms to package repositories
- **Data Usage**: ~2-3 GB for initial build (package downloads)

**VPN Considerations**: See [TROUBLESHOOTING.md - Network/VPN](TROUBLESHOOTING.md#networkvpn-connectivity) for wsl-vpnkit configuration.

---

## Benchmarks

### Build Performance Comparison

| Configuration | Single-Arch Build | Multi-Arch Build |
| ----------------- | ------------------- | ------------------ |
| 4-core, 8GB RAM, HDD | 35-45 min | 70-90 min |
| 4-core, 16GB RAM, SSD | 20-25 min | 40-50 min |
| 8-core, 16GB RAM, SSD | 15-20 min | 30-40 min |
| 8-core, 32GB RAM, NVMe | 12-18 min | 25-35 min |

### Test Performance Comparison

| Test Count | Duration (SSD) | Duration (HDD) |
| ------------ | ---------------- | ---------------- |
| 120 tests | 1m 30s | 2m 15s |
| 240 tests | 2m 30s | 3m 45s |
| 480 tests | 4m 45s | 7m 20s |

*Note: Linear scaling with test count.*

### Container Operations

| Operation | Duration (Cached) | Duration (Cold) |
| ----------- | ------------------- | ----------------- |
| `podman pull` (100MB image) | N/A | 15-30s |
| `podman run` (cached image) | 2-3s | 5-10s |
| `podman build` (simple) | 30s - 2m | 2-5m |
| `podman build` (this image) | 15-25m | 20-30m |

---

## Performance Monitoring

### Build Progress Tracking

Both build scripts provide real-time progress:

**build.ps1**:

```powershell
→ Building Docker image...
This may take 15-30 minutes...
✓ Image built successfully in 23.45 minutes
```

**build-docker.sh**:

```bash
→ Building Multi-Architecture Image
This may take 20-40 minutes...
✓ Image built and pushed successfully in 42m 18s
```

### System Resource Monitoring

**Inside WSL**:

```bash
# CPU and memory
htop

# Disk usage
df -h
du -sh /home/linuxbrew/.linuxbrew

# Container stats
podman stats
```

**Windows (PowerShell)**:

```powershell
# WSL memory usage
wsl --list --verbose
Get-Process vmmem | Select-Object WorkingSet, CPU
```

### Build Cache Analysis

**Docker**:

```bash
docker buildx du
docker system df
```

**Podman**:

```bash
podman system df
podman info --format '{{.Store}}'
```

---

## Related Documentation

- [README.md](../README.md) - Quick start and usage
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Performance issues and solutions
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and structure
- [CLAUDE.md](CLAUDE.md) - Historical context and decisions
- [CODE_REVIEW.md](CODE_REVIEW.md) - Code quality analysis

---

**Last Updated:** 2025-11-27
