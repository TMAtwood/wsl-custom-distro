# GitHub Actions Workflow

This repository includes a GitHub Actions workflow that automatically builds and tests the container image.

## Workflow: Build and Test Container Image

**File**: `.github/workflows/build-and-test.yml`

### Triggers

The workflow runs on:

- **Push** to `main`, `develop`, or `feature/**` branches
- **Pull requests** targeting `main` or `develop`
- **Manual trigger** via `workflow_dispatch`

### What it Does

1. **Checkout Code** - Fetches the repository with full history for GitVersion
2. **Setup Build Environment** - Configures QEMU and Docker Buildx
3. **Version Determination** - Uses GitVersion to calculate semantic version
4. **Install Tools** - Installs Homebrew and container-structure-test
5. **Build Image** - Builds the container image with version tags
6. **Run Tests** - Executes all 88 container structure tests
7. **Save Artifact** - (main branch only) Saves the built image as a downloadable artifact
8. **Publish to GHCR** - (main branch only) Publishes to GitHub Container Registry

### Outputs

- Container image tagged with semantic version and `latest`
- Test results showing pass/fail for all 88 tests
- Compressed image artifact for download (main branch pushes only, 7-day retention)
- Published container image on GitHub Container Registry at `ghcr.io/tmatwood/wsl-ubuntu-26.04`

### Local Testing with `act`

You can test the GitHub Actions workflow locally using [`act`](https://github.com/nektos/act).

#### Prerequisites

1. Install `act` (already included in this WSL environment via Homebrew):

    ```bash
    brew install act
    ```

2. Ensure Podman socket is running:

    ```bash
    sudo systemctl start podman.socket
    sudo chmod 666 /run/podman/podman.sock
    ```

3. Install podman-docker for Docker CLI emulation:

    ```bash
    sudo apt-get install podman-docker
    ```

#### Running Tests

**View workflow structure:**

```bash
act -g
```

**List available jobs:**

```bash
act --list
```

**Run the workflow (dry-run simulation):**

```bash
act -n
```

**Run the workflow for real:**

```bash
act push
```

**Run with verbose output:**

```bash
act push -v
```

**Run specific job:**

```bash
act -j build-and-test
```

#### Configuration

The repository includes a `.actrc` configuration file with sensible defaults:

- Uses `catthehacker/ubuntu:act-latest` as the runner image
- Binds workspace for faster execution
- Configured for amd64 architecture
- Disables daemon socket binding for Podman compatibility

#### Known Limitations

- `act`'s dry-run mode (`-n`) may fail when checking socket connectivity, but the workflow structure is valid
- Full execution requires downloading the runner image (~500MB for medium image)
- Some GitHub-specific features (like GITHUB_TOKEN) may need to be mocked
- Build time on local hardware may vary from GitHub's hosted runners

#### Troubleshooting

**Error: "Cannot connect to the Docker daemon"**

- Start Podman socket: `sudo systemctl start podman.socket`
- Fix permissions: `sudo chmod 666 /run/podman/podman.sock`

**Error: "docker: command not found"**

- Install podman-docker: `sudo apt-get install podman-docker`

**Error: "permission denied while trying to connect"**

- Check socket permissions: `ls -la /run/podman/podman.sock`
- Add user to docker group: `sudo usermod -aG docker $USER` (then log out/in)

## Workflow Customization

### Changing Build Arguments

Edit `.github/workflows/build-and-test.yml` to modify build arguments:

```yaml
- name: Build container image
  run: |
      docker build \
        --build-arg BUILD_DATE="${BUILD_DATE}" \
        --build-arg VERSION="${VERSION}" \
        --build-arg CUSTOM_ARG="value" \
        -t "${{ env.IMAGE_NAME }}:${VERSION}" \
        .
```

### Adding Additional Tests

Add new test steps after the container structure tests:

```yaml
- name: Custom security scan
  run: |
      trivy image "${{ env.IMAGE_NAME }}:${VERSION}"
```

### Changing Runner

To use a different GitHub Actions runner:

```yaml
jobs:
    build-and-test:
        runs-on: ubuntu-22.04  # or ubuntu-20.04, etc.
```

### Publishing Images

To publish to a container registry, add after tests:

The workflow automatically publishes to GitHub Container Registry (GHCR) on pushes to the `main` branch:

```yaml
- name: Login to GitHub Container Registry
  if: github.ref == 'refs/heads/main'
  uses: docker/login-action@v3
  with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}

- name: Push to GitHub Container Registry
  run: |
      docker push "ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${VERSION}"
      docker push "ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:latest"
```

#### Using Published Images

After a successful build on the `main` branch, you can pull the image:

```bash
# Pull specific version
docker pull ghcr.io/tmatwood/wsl-ubuntu-26.04:0.1.0

# Pull latest
docker pull ghcr.io/tmatwood/wsl-ubuntu-26.04:latest

# Using with Podman
podman pull ghcr.io/tmatwood/wsl-ubuntu-26.04:latest
```

#### Making Images Public

By default, images published to GHCR are private. To make them public:

1. Go to your GitHub profile → Packages
2. Find `wsl-ubuntu-26.04` package
3. Click "Package settings"
4. Scroll to "Danger Zone" → Change visibility → Make public

#### Publishing to Docker Hub

To also publish to Docker Hub, add these steps and configure secrets:

```yaml
- name: Login to Docker Hub
  uses: docker/login-action@v3
  with:
      username: ${{ secrets.DOCKERHUB_USERNAME }}
      password: ${{ secrets.DOCKERHUB_TOKEN }}

- name: Push to Docker Hub
  run: |
      docker tag "${{ env.IMAGE_REGISTRY }}/${{ env.IMAGE_NAME }}:${VERSION}" "docker.io/tmatwood/${{ env.IMAGE_NAME }}:${VERSION}"
      docker push "docker.io/tmatwood/${{ env.IMAGE_NAME }}:${VERSION}"
```

## CI/CD Best Practices

1. **Version Control**: GitVersion automatically calculates semantic versions
2. **Artifact Retention**: Images are kept for 7 days (configurable)
3. **Test Coverage**: All 88 tests validate tool installations
4. **Branch Protection**: Require workflow to pass before merging
5. **Caching**: Docker layer caching speeds up builds

## Integration with GitHub

### Branch Protection Rules

Configure branch protection for `main`:

1. Go to Settings → Branches → Branch protection rules
2. Add rule for `main` branch
3. Enable "Require status checks to pass before merging"
4. Select "build-and-test" as required check

### Viewing Results

- **Actions Tab**: View all workflow runs
- **Pull Requests**: See status checks on PRs
- **Commit Status**: Check marks on commits
- **Artifacts**: Download built images from successful runs

### Secrets Management

If you add registry publishing, configure secrets:

1. Go to Settings → Secrets and variables → Actions
2. Add repository secrets:
    - `DOCKERHUB_USERNAME`
    - `DOCKERHUB_TOKEN`
    - Any other credentials needed

## Performance

Typical execution times on GitHub-hosted runners:

- **Checkout & Setup**: ~30 seconds
- **GitVersion**: ~10 seconds
- **Homebrew Install**: ~2 minutes
- **Image Build**: ~15-25 minutes (uncached)
- **Tests**: ~2-3 minutes
- **Total**: ~20-30 minutes

With Docker layer caching, subsequent builds can be as fast as 5-10 minutes.
