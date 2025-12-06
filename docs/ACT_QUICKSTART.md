# GitHub Actions Local Testing with `act` - Quick Start Guide

**`act` lets you test your GitHub Actions workflows locally before pushing to GitHub.**

This is the **recommended approach** for development over running a persistent GitHub Actions runner.

---

## What is `act`?

`act` is a tool that runs GitHub Actions workflows locally using Docker/Podman. It:

- Tests workflows on your machine before pushing
- Simulates GitHub Actions environment
- Supports all GitHub Actions features
- Works with Podman (your WSL2 setup)
- Already installed in your environment via Homebrew

---

## Quick Start (5 minutes)

### 1. Verify `act` is installed

```bash
act --version
```

You should see output like: `act version X.X.X`

### 2. Run your workflow locally

```bash
# Test the 'push' event trigger
act push

# Test the 'pull_request' event trigger
act pull_request

# Run a specific job
act push --job build-and-test
```

### 3. View available workflows

```bash
act --list
```

Output shows all workflows and jobs:

```
Stage  Job ID           Job Name         Workflow Name            Workflow File                     Events
0      build-and-test   Build and Test   Build and Test Container .github/workflows/ci.yml         push, pull_request, workflow_dispatch
```

---

## Common Commands

### Run specific workflow

```bash
# Run the default job
act push

# Run a specific job
act push --job build-and-test

# Run with verbose output to see details
act push --verbose

# Run with debug output
ACT_DEBUG=true act push --job build-and-test
```

### Test different events

```bash
# Test on push event
act push

# Test on pull_request event
act pull_request

# Test workflow_dispatch event
act workflow_dispatch
```

### Run with specific configuration

```bash
# Use your custom WSL2 image instead of default
act push --container-architecture linux/amd64

# Run without building image (use existing)
act push --job build-and-test --container-image localhost/tmatwood/ubuntu-24.04:latest

# Set secrets for authentication
act push --secret GITHUB_TOKEN=your_token_here
```

---

## Authentication (GitHub Tokens)

### Optional: Use GitHub token for authenticated requests

For workflows that need GitHub API access (e.g., uploading releases):

```bash
# Set token for this session
export GITHUB_TOKEN=ghp_xxxx...
act push

# Or use act's secret feature
act push --secret GITHUB_TOKEN=ghp_xxxx...
```

To get a token:

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" > "Generate new token (classic)"
3. Select scope: `repo`
4. Generate and copy
5. Use in command above

---

## Troubleshooting

### Issue: Image build fails or takes too long

**Cause**: `act` downloads/builds Docker images for each job

**Solution**:

```bash
# Use your pre-built custom image
act push --container-image localhost/tmatwood/ubuntu-24.04:latest

# Or use a lighter Ubuntu image
act push --container-image ubuntu:24.04
```

### Issue: Container socket errors

**Cause**: Podman socket might not be running

**Solution**:

```bash
# Check if Podman is running
systemctl --user status podman

# Start Podman if needed
systemctl --user start podman

# For rootful Podman (if you have it)
sudo systemctl status podman
```

### Issue: Out of disk space

**Cause**: act stores images and work directories locally

**Solution**:

```bash
# Clear act cache
rm -rf ~/.cache/act

# Clear work directories
rm -rf /tmp/runner/work

# Clean up unused Docker/Podman images
podman image prune -a
```

### Issue: "Permission denied" on volumes

**Cause**: File permissions mismatch between host and container

**Solution**:

```bash
# Run with elevated permissions (if needed)
sudo act push

# Or adjust file permissions
chmod -R 755 .github/
```

### Issue: Workflow references `self-hosted` runner label

**Cause**: Default `act` uses `ubuntu-latest`, not `self-hosted`

**Solution**: Update your workflow to use labels that `act` supports

Example workflow:

```yaml
jobs:
  build:
    # ❌ This won't run with act
    runs-on: self-hosted

    # ✅ This will run with act
    runs-on: ubuntu-latest
```

Or add conditional logic:

```yaml
jobs:
  build:
    # Runs on GitHub with self-hosted, but with act uses ubuntu-latest
    runs-on: ${{ github.event_name == 'push' && 'self-hosted' || 'ubuntu-latest' }}
```

---

## Tips & Best Practices

### 1. Test incrementally

```bash
# First: Run the job to see if it starts
act push --job build-and-test

# Second: Run with verbose output to debug issues
act push --job build-and-test --verbose

# Third: Run with all output
ACT_DEBUG=true act push --job build-and-test
```

### 2. Use act config file (optional)

Create `.actrc` in your home directory:

```ini
# Use your custom image for all jobs
-C localhost/tmatwood/ubuntu-24.04:latest

# Verbose output by default
-v

# Container daemon socket for Podman
-c /run/user/1001/podman/podman.sock
```

Then just run:

```bash
act push
```

### 3. Test before pushing

```bash
# Before git push
act push --job build-and-test

# Before git pull request
act pull_request --job build-and-test

# Then commit and push if local tests pass
git push
```

### 4. Simulate different branches

```bash
# Test against main branch (useful for workflow changes)
act push -r main

# Test against current branch
act push -r $(git rev-parse --abbrev-ref HEAD)
```

---

## When to Use `act` vs. Persistent Runner

### Use `act` for

- ✅ Testing workflow changes locally
- ✅ Quick iteration during development
- ✅ Before pushing to GitHub
- ✅ CI/CD pipeline testing
- ✅ No persistent infrastructure needed

### Use persistent runner (docker-compose) for

- ⚠️ Testing long-running jobs
- ⚠️ Webhook-triggered workflows
- ⚠️ Production-like testing
- ⚠️ Multiple concurrent jobs

**For most development: use `act`!**

---

## Integration with Your Workflow

Your CI workflow (`.github/workflows/ci.yml`) already supports `act`:

```yaml
- name: Build container image
  env:
    BUILD_DATE: ${{ steps.gitversion.outputs.commitDate }}
  run: |
    if [ -n "$ACT" ]; then
      # Running with act locally - disable buildx
      DOCKER_BUILDKIT=0 docker build ...
    else
      # Running on GitHub - use buildx
      docker buildx build ...
    fi
```

This means your workflow automatically detects when it's running with `act` and adjusts accordingly!

---

## Example Workflow

### Test your changes locally

```bash
# 1. Make changes to your code
vi src/some-file.sh

# 2. Test locally with act
act push --job build-and-test --verbose

# 3. If tests pass, commit and push
git add .
git commit -m "Fix: update workflow"
git push origin main

# 4. GitHub Actions runs the same workflow
# (Should pass since we tested with act!)
```

---

## Advanced Usage

### Run specific steps

```bash
# See available steps
act --list

# Run up to a specific step
act push --job build-and-test --step "Build container image"
```

### Set environment variables

```bash
# Set variables for the workflow
act push \
  --env VERSION=1.2.3 \
  --env BUILD_TYPE=release
```

### Use matrix strategy

```bash
# Test matrix strategy (multiple configurations)
act push --job build-and-test
```

---

## Resources

- **Official act documentation**: https://github.com/nektos/act
- **GitHub Actions documentation**: https://docs.github.com/en/actions
- **Your workflow file**: [.github/workflows/ci.yml](.github/workflows/ci.yml)
- **Full runner setup guide**: [docs/GITHUB_RUNNER_REVIEW.md](GITHUB_RUNNER_REVIEW.md)

---

## Next Steps

1. **Try it now**: `act push --list`
2. **Run a job**: `act push --job build-and-test`
3. **Make changes** to your workflow
4. **Test again** with `act push`
5. **Commit and push** when tests pass

You now have a complete local CI/CD testing setup! 🚀
