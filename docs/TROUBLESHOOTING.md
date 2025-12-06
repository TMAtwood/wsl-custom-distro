# Troubleshooting Guide

This guide covers common issues and their solutions for the WSL Ubuntu 24.04 Development Environment.

---

## Table of Contents

- [Build Issues](#build-issues)
  - [Homebrew Installation Failures](#homebrew-installation-failures)
  - [Python Package Conflicts](#python-package-conflicts)
  - [OpenJDK Build Failures](#openjdk-build-failures)
  - [GitVersion Errors](#gitversion-errors)
  - [Docker/Podman Build Failures](#dockerpodman-build-failures)
- [Runtime Issues](#runtime-issues)
  - [Podman Permission Denied](#podman-permission-denied)
  - [Audio/Video Not Working](#audiovideo-not-working)
  - [Browser Display Issues](#browser-display-issues)
  - [Network/VPN Connectivity](#networkvpn-connectivity)
- [Testing Issues](#testing-issues)
  - [Container Structure Tests Failing](#container-structure-tests-failing)
  - [Act Local Testing Issues](#act-local-testing-issues)
- [General WSL Issues](#general-wsl-issues)
  - [Systemd Not Running](#systemd-not-running)
  - [Disk Space Issues](#disk-space-issues)

---

## Build Issues

### Homebrew Installation Failures

#### Symptom

```
Error: The following directories are not writable by your user:
/usr/local/bin
/usr/local/etc
```

#### Cause

The `dev` user doesn't have write permissions to `/usr/local/*` directories.

#### Solution

This should be fixed in [Dockerfile:250-254](../Dockerfile#L250-L254). If you encounter this:

```bash
# Run as root in the container
sudo chown -R dev:dev /usr/local
sudo chmod -R u+w /usr/local
```

#### Reference

See [CLAUDE.md - Homebrew /usr/local Permissions Fix](CLAUDE.md#homebrew-usrlocal-permissions-fix)

---

#### Symptom

```
Warning: Building from source as the bottle needs:
HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar (yours is /usr/local/Cellar)
```

#### Cause

Homebrew symlink in `/usr/local/bin` causes HOMEBREW_PREFIX to be detected incorrectly.

#### Solution

This is fixed in [Dockerfile:263-267](../Dockerfile#L263-L267) by removing the brew symlink. If you added it manually:

```bash
# Remove the problematic symlink
sudo rm /usr/local/bin/brew

# Use brew with full path or after shellenv
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew --version
```

#### Reference

See [CLAUDE.md - Homebrew HOMEBREW_PREFIX Conflict](CLAUDE.md#homebrew-homebrew_prefix-conflict-with-usrlocal-symlink)

---

### Python Package Conflicts

#### Symptom

```
ERROR: Cannot uninstall pip 24.0, RECORD file not found.
Hint: The package was installed by debian.
```

#### Cause

System-installed pip (from apt) doesn't have a RECORD file for tracking.

#### Solution

This is fixed in [Dockerfile:794-802](../Dockerfile#L794-L802) using `--ignore-installed`. If you're manually installing packages:

```bash
# Don't upgrade system pip
# python -m pip install --upgrade pip  # DON'T DO THIS

# Instead, install packages with --ignore-installed
python -m pip install --break-system-packages --ignore-installed <package>
```

#### Reference

See [CLAUDE.md - Python Pip Upgrade Conflict](CLAUDE.md#python-pip-upgrade-conflict-with-debian-package-manager)

---

#### Symptom

```
ERROR: Cannot uninstall jsonschema 4.10.3, RECORD file not found.
```

#### Cause

Checkov requires newer jsonschema than system-provided version.

#### Solution

Use `--ignore-installed` flag (already implemented in Dockerfile):

```bash
python -m pip install --break-system-packages --ignore-installed checkov
```

#### Reference

See [CLAUDE.md - Python Package Upgrade Conflicts](CLAUDE.md#python-package-upgrade-conflicts-with-system-packages-jsonschema)

---

### OpenJDK Build Failures

#### Symptom

```
configure: error: Incorrect wsl1 installation.
Neither cygpath nor wslpath was found
```

#### Cause

OpenJDK's configure script detects WSL metadata and looks for WSL1 utilities that don't exist in the container.

#### Solution

This is fixed by removing the `bfg` package (which triggered OpenJDK build). If you need `bfg`:

```bash
# Option 1: Download pre-built JAR
wget https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar
java -jar bfg-1.14.0.jar

# Option 2: Use apt-installed OpenJDK (already available)
# Java 8, 11, 17, 21, 25 are pre-installed
```

#### Reference

See [CLAUDE.md - Homebrew OpenJDK Build Failure](CLAUDE.md#homebrew-openjdk-build-failure-in-wsl-container)

---

### GitVersion Errors

#### Symptom

```
gitversion: command not found
```

Or build completes but VERSION is empty.

#### Cause

GitVersion is not installed or not in PATH.

#### Solution

**For build.ps1:**

```powershell
# Install GitVersion globally
dotnet tool install --global GitVersion.Tool

# Or use the script's fallback (automatically uses 0.0.0-dev)
.\build.ps1  # Will use default version
```

**For build-docker.sh:**

```bash
# Install GitVersion
brew install gitversion

# Or the script automatically falls back to 0.0.0-dev
bash build-docker.sh
```

Both build scripts now have robust fallback handling that uses `0.0.0-dev` if GitVersion is unavailable.

---

### Docker/Podman Build Failures

#### Symptom

```
Error: buildah does not support the --platform flag
```

#### Cause

Using Podman with buildah backend which doesn't support `--platform`.

#### Solution

Use Docker format with Podman:

```bash
podman build --format docker --platform linux/amd64 -t image:tag .
```

This is already configured in [build.ps1:151-156](../build.ps1#L151-L156).

---

#### Symptom

```
Error: No space left on device
```

#### Cause

Insufficient disk space for image layers.

#### Solution

```bash
# Check available space
df -h

# Clean up Docker/Podman
docker system prune -a --volumes  # Docker
podman system prune -a --volumes  # Podman

# Clean up WSL2 disk
# From Windows PowerShell (as Administrator):
wsl --shutdown
Optimize-VHD -Path "$env:LOCALAPPDATA\Docker\wsl\data\ext4.vhdx" -Mode Full
```

---

## Runtime Issues

### Podman Permission Denied

#### Symptom

```
Error: permission denied mounting /run/podman/podman.sock
```

#### Cause

Podman socket is not running or has incorrect permissions.

#### Solution

**Check Podman socket status:**

```bash
# Check system socket (rootful)
sudo systemctl status podman.socket

# Check user socket (rootless)
systemctl --user status podman.socket
```

**Start Podman socket:**

```bash
# For rootful Podman (default in this image)
sudo systemctl start podman.socket
sudo systemctl enable podman.socket

# For rootless Podman
systemctl --user start podman.socket
systemctl --user enable podman.socket
```

**Verify socket exists:**

```bash
# Rootful socket
ls -la /run/podman/podman.sock

# Rootless socket
ls -la /run/user/$(id -u)/podman/podman.sock
```

#### Reference

See [CLAUDE.md - Rootless to Rootful Podman](CLAUDE.md#switching-from-rootless-to-rootful-podman-for-act-compatibility)

---

### Audio/Video Not Working

#### Symptom

No audio output or video display in GUI applications.

#### Cause

WSLg (Windows Subsystem for Linux GUI) not properly configured or PulseAudio not connected.

#### Solution

**Check WSLg is available:**

```bash
# Check if WSLg directories exist
ls -la /mnt/wslg/

# Check PulseAudio socket
ls -la /mnt/wslg/PulseServer

# Check environment variables
echo $DISPLAY
echo $WAYLAND_DISPLAY
echo $PULSE_SERVER
```

**Test audio:**

```bash
# Check PulseAudio connection
pactl list sinks

# Test audio playback (generates 1 second beep)
pactl play-sample bell

# Check audio devices
aplay -l
```

**Restart WSL (from Windows):**

```powershell
# From Windows PowerShell
wsl --shutdown
# Then restart WSL
wsl
```

**Verify configuration:**

- PulseAudio config: [Dockerfile:983-984](../Dockerfile#L983-L984)
- ALSA config: [Dockerfile:988](../Dockerfile#L988)
- Environment variables: [Dockerfile:995-1001](../Dockerfile#L995-L1001)

#### Reference

See [CLAUDE.md - Audio and Video Capabilities](CLAUDE.md#audio-and-video-capabilities-for-dev-user)

---

### Browser Display Issues

#### Symptom

Browser windows don't open or display incorrectly.

#### Cause

WSLg not enabled or display variables not set.

#### Solution

**Check Windows version:**

```powershell
# From Windows PowerShell
winver
# Requires Windows 11 or Windows 10 Build 19044+
```

**Check display environment:**

```bash
echo $DISPLAY        # Should be :0
echo $WAYLAND_DISPLAY  # Should be wayland-0
echo $XDG_RUNTIME_DIR  # Should be /run/user/1001
```

**Test with simple GUI:**

```bash
# Test X11
xeyes

# If xeyes works, try browser
google-chrome --no-sandbox
```

**Use chrome-wsl wrapper:**

```bash
# Custom wrapper with correct settings
chrome-wsl
```

#### Reference

Chrome wrapper: [Dockerfile:968-971](../Dockerfile#L968-L971)

---

### Network/VPN Connectivity

#### Symptom

Network connections fail when Windows VPN is active.

#### Cause

WSL2 uses a virtual network adapter that may not work correctly with some VPNs.

#### Solution

**Use wsl-vpnkit (pre-installed):**

```bash
# Check if service is running
sudo systemctl status wsl-vpnkit

# Start the service
sudo systemctl start wsl-vpnkit

# Enable on boot
sudo systemctl enable wsl-vpnkit
```

**Manual DNS fix:**

```bash
# Check DNS settings
cat /etc/resolv.conf

# If needed, use custom DNS
sudo cp /etc/resolv.conf.override /etc/resolv.conf
```

**Test connectivity:**

```bash
# Test DNS resolution
nslookup google.com

# Test connectivity
ping -c 3 8.8.8.8

# Test HTTPS
curl -I https://www.google.com
```

#### Reference

See [Dockerfile:1010-1038](../Dockerfile#L1010-L1038) for wsl-vpnkit configuration.

---

## Testing Issues

### Container Structure Tests Failing

#### Symptom

```
FAIL - <test name> expected output not found
```

#### Cause

Tool not installed or version output format changed.

#### Solution

**Debug a specific test:**

```bash
# Enter the container
podman run -it --rm localhost/tmatwood/ubuntu-24.04:latest bash

# Run the command manually
<command from test> --version

# Check if command exists
which <command>
```

**Common fixes:**

- GUI apps: Use `which` instead of `--version` (see [tests.yaml:430-453](../tests.yaml#L430-L453))
- Empty expectedOutput: Tool may not support `--version` properly

#### Reference

See [CLAUDE.md - Test Fixes for Browser and Audio/Video Features](CLAUDE.md#test-fixes-for-browser-and-audiovideo-features)

---

### Act Local Testing Issues

#### Symptom

```
Error: .NET SDK not found
GitVersion: command not found
```

#### Cause

Act uses lightweight runner image that doesn't include .NET or GitVersion.

#### Solution

**Option 1: Use full act image:**

```bash
# Use fuller image with more tools
act -P ubuntu-latest=catthehacker/ubuntu:full-latest
```

**Option 2: Skip version step:**
The CI workflow now has fallback logic (see [.github/workflows/ci.yml](../.github/workflows/ci.yml)).

**Option 3: Use local test script:**

```bash
# Simpler local testing without act
./local-test.sh
```

#### Reference

See [CLAUDE.md - Act Compatibility](CLAUDE.md#switching-from-rootless-to-rootful-podman-for-act-compatibility)

---

## General WSL Issues

### Systemd Not Running

#### Symptom

```
System has not been booted with systemd
```

#### Cause

Systemd not enabled in `/etc/wsl.conf`.

#### Solution

**Check configuration:**

```bash
cat /etc/wsl.conf
```

Should contain:

```ini
[boot]
systemd=true
```

**Restart WSL (from Windows):**

```powershell
wsl --shutdown
wsl
```

**Verify systemd is running:**

```bash
systemctl --version
ps -p 1
```

#### Reference

See [Dockerfile:160-161](../Dockerfile#L160-L161) for wsl.conf configuration.

---

### Disk Space Issues

#### Symptom

```
No space left on device
```

#### Cause

WSL2 virtual disk is full or image is too large.

#### Solution

**Check space in WSL:**

```bash
df -h
du -sh /*
```

**Compact WSL disk (from Windows PowerShell as Administrator):**

```powershell
# Shutdown WSL
wsl --shutdown

# Find your WSL disk location
# Usually at: %LOCALAPPDATA%\Packages\<DistroName>\LocalState\ext4.vhdx

# Compact the disk
wsl --manage <DistroName> --set-sparse true

# Or manually optimize
Optimize-VHD -Path "path\to\ext4.vhdx" -Mode Full
```

**Clean up in WSL:**

```bash
# Clean package cache
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove

# Clean Docker/Podman
podman system prune -a --volumes

# Clean Homebrew cache
brew cleanup -s
rm -rf "$(brew --cache)"

# Clean temp files
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
```

---

## Getting More Help

### Check Documentation

- [README.md](../README.md) - Overview and quick start
- [CLAUDE.md](CLAUDE.md) - Detailed decision log with historical context
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture and design decisions
- [PERFORMANCE.md](PERFORMANCE.md) - Build times and optimization tips

### Enable Debug Output

**For build.ps1:**

```powershell
$VerbosePreference = "Continue"
$DebugPreference = "Continue"
.\build.ps1
```

**For build-docker.sh:**

```bash
# Add set -x for detailed trace
bash -x build-docker.sh
```

**For Dockerfile:**

```dockerfile
# Add before problematic RUN command
RUN set -x && <your command>
```

### Report Issues

If you encounter issues not covered here, please check:

1. Existing issues: https://github.com/TMAtwood/wsl-ubuntu-24.04/issues
2. Create new issue with:
    - Error message (full output)
    - Steps to reproduce
    - Environment info (Windows version, WSL version, Docker/Podman version)
    - Relevant log files

---

**Last Updated:** 2025-11-27
