# GitHub Actions Runner Local Setup - Comprehensive Review

## Current Status

Your repository has a GitHub Actions runner setup configured for **Synology NAS** (outdated), but you want to run it locally on your **Windows/WSL2 laptop** for development.

---

## Issues & Recommendations

### 1. **Configuration is NAS-Specific** ⚠️

**Current Issues:**

- RUNNER_NAME: `synology-nas-runner` (should be laptop-specific)
- Volume paths: `/volume1/docker/github-runner/...` (NAS paths)
- Resource limits: 4 CPU / 8GB memory (may be too high for laptop)

**Recommendation:**
Update for laptop development with local paths.

---

### 2. **Docker vs Podman** 🐋

**Current Setup:**

```yaml
DOCKER_ENABLED: true
DOCKER_HOST: unix:///var/run/docker.sock
```

**Issue:**
Your WSL2 environment uses **Podman** (rootless), not Docker. The socket path is different:

- Docker socket: `/var/run/docker.sock`
- Podman socket (rootless): `/run/user/1001/podman/podman.sock`

**Recommendation:**
Use Podman's socket for better compatibility with your WSL2 setup.

---

### 3. **Runner Image Choice** 📦

**Current:**

```yaml
image: myoung34/github-runner:latest
```

**Issues:**

- Generic GitHub runner (not optimized for your environment)
- May lack your custom tools and configuration
- Creates inconsistency between local testing and runner execution

**Recommendation:**
Consider using your custom WSL2 image as the runner base:

```yaml
image: localhost/tmatwood/ubuntu-24.04:latest
```

This ensures consistency between development and CI.

---

### 4. **Ephemeral Mode** 🔄

**Current (commented out):**

```yaml
# EPHEMERAL: true
```

**Benefit for Development:**

- Clean state for each job (no lingering state)
- Prevents disk bloat during development
- Better isolation between test runs

**Recommendation:**
Enable for local development: `EPHEMERAL: true`

---

### 5. **Privileged Mode & Security** 🔒

**Current:**

```yaml
privileged: true
security_opt:
  - apparmor:unconfined
  - seccomp:unconfined
```

**Issues:**

- Very permissive for a development machine
- Unnecessary security restrictions disabled
- Could impact system stability

**Recommendation for Local Dev:**
Keep as-is for now (needed for Docker-in-Docker), but add comments about security implications.

---

### 6. **Resource Limits** 💾

**Current:**

```yaml
limits:
  cpus: "4.0"
  memory: 8G
reservations:
  cpus: "2.0"
  memory: 4G
```

**Issues:**

- Too high for typical laptop development
- May degrade host system performance
- Should be configurable per environment

**Recommendation for Laptop:**

```yaml
limits:
  cpus: "2.0"      # Adjust based on your CPU count
  memory: 4G       # Adjust based on available RAM
reservations:
  cpus: "1.0"
  memory: 2G
```

---

### 7. **Environment Variables** 🔧

**Issues:**

- REPO_URL hardcoded to your specific fork
- RUNNER_TOKEN/ACCESS_TOKEN requires manual setup
- Limited environment documentation

**Recommendation:**
Make configurable via .env file with examples:

```bash
# Configurable per environment
REPO_URL=${GITHUB_REPO_URL:-https://github.com/TMAtwood/wsl-ubuntu-24.04}
RUNNER_NAME=${RUNNER_NAME:-local-dev-runner}
GITHUB_PAT=${GITHUB_PAT}
```

---

### 8. **Integration with `act`** ✅

**Good News:**
Your CI workflow already supports `act` (GitHub Actions locally)!

**Current Detection (CI workflow line 77):**

```yaml
if [ -n "$ACT" ]; then
  DOCKER_BUILDKIT=0 docker build ...  # Local with act
else
  docker buildx build ...             # GitHub Actions
fi
```

**Alternative Approach:**
Instead of docker-compose runner, just use `act` for local testing:

```bash
# Run your workflow locally
act push --job build-and-test
```

This is simpler than running a persistent GitHub runner locally.

---

## Recommended Approaches

### **Option 1: Use `act` for Local Testing** ✅ RECOMMENDED

**Pros:**

- No persistent container needed
- Simpler setup
- Works with your existing workflow
- Already integrated in your CI

**Setup:**

```bash
# Already in your environment!
act --version

# Run specific workflow
act push --job build-and-test

# Run with self-hosted label
act push --self-hosted
```

---

### **Option 2: Persistent Local Runner** (if you need always-on)

**Pros:**

- Runner available for webhook triggers
- Can process multiple jobs sequentially
- Useful for testing runner-specific workflows

**Updated docker-compose.yml needed:**

```yaml
version: "3.8"

services:
  github-runner:
    image: localhost/tmatwood/ubuntu-24.04:latest  # Your custom image
    container_name: github-runner-local-dev
    environment:
      REPO_URL: ${GITHUB_REPO_URL:-https://github.com/TMAtwood/wsl-custom-distro}
      ACCESS_TOKEN: ${GITHUB_PAT}
      RUNNER_NAME: ${RUNNER_NAME:-local-dev-runner}
      RUNNER_WORKDIR: /tmp/runner/work
      LABELS: local,development,self-hosted
      DOCKER_ENABLED: true
      DOCKER_HOST: unix:///run/user/1001/podman/podman.sock  # Podman socket
      EPHEMERAL: true  # Clean state per job

    volumes:
      - /run/user/1001/podman/podman.sock:/run/user/1001/podman/podman.sock  # Podman
      - ${HOME}/.local/share/github-runner/work:/tmp/runner/work
      - ${HOME}/.local/share/github-runner/cache:/tmp/runner/cache

    restart: unless-stopped

    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 4G
        reservations:
          cpus: "1.0"
          memory: 2G

    privileged: true
    security_opt:
      - apparmor:unconfined
      - seccomp:unconfined
```

---

## Setup Instructions

### **Method 1: Using `act` (Recommended)**

```bash
# Already available in your environment
act --version

# List available workflows
act --list

# Run workflow locally
act push

# Run specific job
act push --job build-and-test

# Set GitHub token for authentication
export GITHUB_TOKEN=your_github_token
act push
```

### **Method 2: Persistent Runner (Optional)**

```bash
# Create directories for runner state
mkdir -p ~/.local/share/github-runner/{work,cache}

# Update .env.github-runner with your PAT
GITHUB_PAT=ghp_xxxx...

# Start the runner
docker-compose -f docker-compose-github-runner.yml up -d

# View logs
docker-compose -f docker-compose-github-runner.yml logs -f

# Stop the runner
docker-compose -f docker-compose-github-runner.yml down
```

---

## Updated .env.github-runner

```bash
# GitHub Personal Access Token (PAT)
# Create at: https://github.com/settings/tokens
# Required scopes: repo (full control), admin:org_hook
GITHUB_PAT=your_github_pat_here

# Runner configuration
GITHUB_REPO_URL=https://github.com/TMAtwood/wsl-custom-distro
RUNNER_NAME=local-dev-runner

# Optional: For WSL2/Podman setup
PODMAN_SOCKET=/run/user/1001/podman/podman.sock

# Resource limits (adjust for your machine)
RUNNER_CPU_LIMIT=2.0
RUNNER_MEMORY_LIMIT=4G
```

---

## Security Considerations

### ⚠️ Current Warnings

1. **Privileged Mode**: Container has full host access
2. **Unconfined AppArmor/Seccomp**: Security restrictions disabled
3. **Docker-in-Docker**: Requires privileged access

### ✅ Mitigations for Local Dev

- Use separate user/project for runner
- Keep .env file secure (add to .gitignore)
- Regular token rotation
- Monitor runner logs: `docker-compose logs -f`

### 🔐 PAT Scope Best Practices

When creating your GitHub PAT, grant **minimal** required scopes:

- `repo` - Access to repositories ✅
- `workflow` - Manage workflows (optional)
- `admin:org_hook` - Manage webhooks (if needed)

**DO NOT grant:**

- `admin:repo_hook` unless absolutely needed
- `admin:org`
- `gist` or other unnecessary scopes

---

## Testing Your Setup

### **With `act`:**

```bash
# Test your workflow locally
act push --verbose

# Show what would run
act --list

# Run specific job with debug output
ACT_DEBUG=true act push --job build-and-test
```

### **With Persistent Runner:**

```bash
# Check runner status
docker ps

# View logs
docker logs github-runner-local-dev

# Test connectivity
docker exec github-runner-local-dev gh --version
```

---

## Troubleshooting

### **Issue: Podman socket not found**

```bash
# Verify Podman is running
systemctl --user status podman

# Check socket exists
ls -la /run/user/1001/podman/podman.sock

# Or use rootful Podman socket
ls -la /run/podman/podman.sock
```

### **Issue: Insufficient disk space**

```bash
# Clear runner cache
rm -rf ~/.local/share/github-runner/cache/*

# Or enable EPHEMERAL mode in docker-compose
```

### **Issue: PAT token expired**

```bash
# Regenerate PAT at https://github.com/settings/tokens
# Update .env.github-runner
# Restart runner: docker-compose restart
```

---

## Recommendations Summary

| Item | Current | Recommended | Priority |
|------|---------|-------------|----------|
| Runner Type | myoung34/github-runner | Your custom image | Medium |
| Socket Path | Docker | Podman WSL2 | High |
| CPU Limit | 4.0 | 2.0 | Medium |
| Memory Limit | 8G | 4G | Medium |
| Ephemeral | Off | On | Low |
| Primary Method | Persistent runner | `act` for local testing | High |

---

## Next Steps

1. **Decide on approach**: `act` vs persistent runner
2. **Update configuration**: docker-compose if using persistent runner
3. **Set up credentials**: Create/update .env.github-runner
4. **Test locally**: Run `act push` or start runner container
5. **Monitor**: Check logs during first few test runs
