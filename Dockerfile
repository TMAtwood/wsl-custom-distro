ARG VERSION

# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ STAGE 1: BASE FOUNDATION                                                                      ║
# ║ Purpose: System foundation, users, repositories, WSL configuration                            ║
# ║ Contains: ARG/ENV vars, apt packages, user setup, git config script, PPAs, WSL config        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

FROM ubuntu:26.04 AS base

# Set shell options for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL maintainer="Tom Atwood<tom@tmatwood.com>"
LABEL org.opencontainers.image.version=26.04
LABEL org.opencontainers.image.ref.name=ubuntu


#  ██  ██      ███████ ███    ██ ██    ██     ██    ██  █████  ██████  ██  █████  ██████  ██      ███████ ███████
# ████████     ██      ████   ██ ██    ██     ██    ██ ██   ██ ██   ██ ██ ██   ██ ██   ██ ██      ██      ██
#  ██  ██      █████   ██ ██  ██ ██    ██     ██    ██ ███████ ██████  ██ ███████ ██████  ██      █████   ███████
# ████████     ██      ██  ██ ██  ██  ██       ██  ██  ██   ██ ██   ██ ██ ██   ██ ██   ██ ██      ██           ██
#  ██  ██      ███████ ██   ████   ████         ████   ██   ██ ██   ██ ██ ██   ██ ██████  ███████ ███████ ███████

ARG APT_KEY_DONT_WARN_IN_DANGEROUS_USAGE=1
ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C
ENV GROUP=dev
ENV NON_INTERACTIVE=1
ENV USER=dev
ENV version=$VERSION


#  ██  ██      ███████  ██████  ██    ██ ███    ██ ██████   █████  ████████ ██  ██████  ███    ██ ███████
# ████████     ██      ██    ██ ██    ██ ████   ██ ██   ██ ██   ██    ██    ██ ██    ██ ████   ██ ██
#  ██  ██      █████   ██    ██ ██    ██ ██ ██  ██ ██   ██ ███████    ██    ██ ██    ██ ██ ██  ██ ███████
# ████████     ██      ██    ██ ██    ██ ██  ██ ██ ██   ██ ██   ██    ██    ██ ██    ██ ██  ██ ██      ██
#  ██  ██      ██       ██████   ██████  ██   ████ ██████  ██   ██    ██    ██  ██████  ██   ████ ███████

WORKDIR /home/root
USER root

# Preliminary foundation packages installed first
# checkov:skip=CKV2_DOCKER_1: sudo is required for development container user management
RUN apt-get -y update \
    && apt-get -y upgrade \
    && apt-get -y install --no-install-recommends \
      adduser \
      apt-transport-https \
      apt-utils \
      axel \
      bash \
      bash-completion \
      bsdmainutils \
      build-essential \
      ca-certificates \
      cargo \
      curl \
      dbus-user-session \
      dkms \
      dpkg \
      fuse-overlayfs \
      git \
      gnupg \
      gnupg2 \
      iptables \
      jq \
      libffi-dev \
      libpam-systemd \
      libplist-utils \
      libssl-dev \
      libxi-dev \
      libxmu-dev \
      lsb-release \
      make \
      slirp4netns \
      software-properties-common \
      systemd \
      systemd-container \
      systemd-cron \
      systemd-resolved \
      systemd-sysv \
      sudo \
      tzdata \
      ubuntu-keyring \
      ubuntu-wsl \
      uidmap \
      unzip \
      wsl-setup \
      wget \
      zip \
    && dpkg-reconfigure ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# wslu (provides wslview, wslpath, wslsys, etc.) was dropped from the Ubuntu
# archive in 26.04. Install the upstream build from the wslutilities PPA pool:
# it is published for noble but is portable enough to run on resolute (runtime
# deps bc, desktop-file-utils, psmisc are all in 26.04 main). The .deb filename
# is resolved dynamically so the version is not pinned here.
# hadolint ignore=DL4006
RUN WSLU_BASE="https://ppa.launchpadcontent.net/wslutilities/wslu/ubuntu" \
    && WSLU_DEB=$(curl -fsSL "${WSLU_BASE}/dists/noble/main/binary-amd64/Packages.gz" | gunzip | awk '/^Filename: .*wslu_/{print $2; exit}') \
    && curl -fsSL -o /tmp/wslu.deb "${WSLU_BASE}/${WSLU_DEB}" \
    && apt-get -y update \
    && apt-get -y install --no-install-recommends /tmp/wslu.deb \
    && rm -rf /tmp/wslu.deb /var/lib/apt/lists/* \
    && command -v wslview


#  ██  ██       ██████ ██████  ███████  █████  ████████ ███████     ██    ██ ███████ ███████ ██████  ███████
# ████████     ██      ██   ██ ██      ██   ██    ██    ██          ██    ██ ██      ██      ██   ██ ██
#  ██  ██      ██      ██████  █████   ███████    ██    █████       ██    ██ ███████ █████   ██████  ███████
# ████████     ██      ██   ██ ██      ██   ██    ██    ██          ██    ██      ██ ██      ██   ██      ██
#  ██  ██       ██████ ██   ██ ███████ ██   ██    ██    ███████      ██████  ███████ ███████ ██   ██ ███████

# Create dev user with explicit UID/GID and sudo access
# checkov:skip=CKV2_DOCKER_1: sudo configuration is required for development container
RUN groupadd -g 1001 ${USER} \
    && groupadd -r docker \
    && groupadd -r linuxbrew \
    && useradd -m -u 1001 -g 1001 -s /bin/bash ${USER} \
    && usermod -aG sudo ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${USER}-nopasswd \
    && chmod 0440 /etc/sudoers.d/90-${USER}-nopasswd \
    && adduser ${USER} adm \
    && useradd --create-home -g linuxbrew -s /bin/bash linuxbrew \
    && echo "linuxbrew ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && usermod -aG docker ${USER} \
    && usermod -aG audio ${USER} \
    && usermod -aG video ${USER} \
    && mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R linuxbrew:linuxbrew /home/linuxbrew/.linuxbrew


#  ██  ██       █████  ██████  ██████      ██████  ███████ ██████   ██████  ███████
# ████████     ██   ██ ██   ██ ██   ██     ██   ██ ██      ██   ██ ██    ██ ██
#  ██  ██      ███████ ██   ██ ██   ██     ██████  █████   ██████  ██    ██ ███████
# ████████     ██   ██ ██   ██ ██   ██     ██   ██ ██      ██      ██    ██      ██
#  ██  ██      ██   ██ ██████  ██████      ██   ██ ███████ ██       ██████  ███████

# Create shared git configuration script to eliminate duplication
# This script configures git for any user with customizable credential helper
COPY config/scripts/setup-git-config.sh /usr/local/bin/setup-git-config.sh
RUN chmod +x /usr/local/bin/setup-git-config.sh

# Configure DNS before adding PPAs to ensure network connectivity
# Backup existing resolv.conf and configure reliable DNS servers
# hadolint ignore=DL3059
RUN cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true && \
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4\n" > /etc/resolv.conf

# Add PPAs with retry logic and network error handling
# hadolint ignore=DL3059,SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Adding PPAs..." && \
      add-apt-repository ppa:deadsnakes/ppa -y && \
      add-apt-repository ppa:cappelikan/ppa -y && \
      add-apt-repository ppa:dotnet/backports -y && \
      echo "Successfully added all PPAs" && \
      break || { echo "Failed attempt $attempt, retrying in 5 seconds..."; sleep 5; }; \
    done

# Restore original resolv.conf if backup exists
# hadolint ignore=DL3059
RUN mv /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null || true

# RUN wget -O - https://apt.corretto.aws/corretto.key | sudo gpg --dearmor -o /usr/share/keyrings/corretto-keyring.gpg \
#     && echo "deb [signed-by=/usr/share/keyrings/corretto-keyring.gpg] https://apt.corretto.aws stable main" | sudo tee /etc/apt/sources.list.d/corretto.list

RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg \
    && chmod 644 /etc/apt/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com resolute main" | tee /etc/apt/sources.list.d/hashicorp.list

# Add Antigravity repository
RUN curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg \
    && chmod 644 /etc/apt/keyrings/antigravity-repo-key.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev antigravity-debian main" | tee /etc/apt/sources.list.d/antigravity.list

RUN (apt-get remove -y 'dotnet*' 'aspnet*' 'netstandard*' || true) \
    && echo "Package: dotnet* aspnet* netstandard*" > /etc/apt/preferences \
    && echo "Pin: origin \"packages.microsoft.com\"" >> /etc/apt/preferences \
    && echo "Pin-Priority: -10" >> /etc/apt/preferences \
    && . /etc/os-release \
    && wget -q https://packages.microsoft.com/config/"$ID"/"$VERSION_ID"/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb


#  ██  ██      ██     ██ ███████ ██           ██████  ██████  ███    ██ ███████ ██  ██████
# ████████     ██     ██ ██      ██          ██      ██    ██ ████   ██ ██      ██ ██
#  ██  ██      ██  █  ██ ███████ ██          ██      ██    ██ ██ ██  ██ █████   ██ ██   ███
# ████████     ██ ███ ██      ██ ██          ██      ██    ██ ██  ██ ██ ██      ██ ██    ██
#  ██  ██       ███ ███  ███████ ███████      ██████  ██████  ██   ████ ██      ██  ██████

# See https://learn.microsoft.com/en-us/windows/wsl/wsl-config
# WSL config: enable systemd, set default user, configure automount and network
COPY config/etc/wsl.conf /etc/wsl.conf

# Configure static DNS since generateResolvConf=false in wsl.conf
# Using Cloudflare (1.1.1.1) and Google (8.8.8.8) public DNS servers
# Note: resolv.conf will be protected by generateResolvConf=false in wsl.conf
RUN printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4\n" > /etc/resolv.conf \
    && chmod 644 /etc/resolv.conf

# Create network fix script for WSL2/Tailscale compatibility
# This script fixes both DNS and default route issues common with Tailscale VPN
RUN printf '#!/bin/bash\n\
# WSL2 Network Fix - fixes DNS and default route (Tailscale compatibility)\n\
\n\
# Fix DNS if resolv.conf is empty or missing\n\
if [ ! -s /etc/resolv.conf ] || ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then\n\
    echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null\n\
    echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null\n\
fi\n\
\n\
# Fix default route if missing\n\
if ! ip route 2>/dev/null | grep -q "^default"; then\n\
    # Get network info and calculate proper gateway\n\
    # For a /20 subnet like 172.26.176.0/20, gateway is 172.26.176.1\n\
    NETWORK_INFO=$(ip -4 addr show eth0 2>/dev/null | grep -oP "inet \\K[0-9.]+/[0-9]+")\n\
    if [ -n "$NETWORK_INFO" ]; then\n\
        # Extract IP and prefix length\n\
        IP_ADDR=$(echo "$NETWORK_INFO" | cut -d"/" -f1)\n\
        PREFIX=$(echo "$NETWORK_INFO" | cut -d"/" -f2)\n\
        # Calculate network address based on prefix\n\
        IFS="." read -r a b c d <<< "$IP_ADDR"\n\
        if [ "$PREFIX" -le 16 ]; then\n\
            GATEWAY="$a.$b.0.1"\n\
        elif [ "$PREFIX" -le 20 ]; then\n\
            # For /20, mask the third octet to nearest 16 boundary\n\
            c=$((c & 240))\n\
            GATEWAY="$a.$b.$c.1"\n\
        elif [ "$PREFIX" -le 24 ]; then\n\
            GATEWAY="$a.$b.$c.1"\n\
        else\n\
            GATEWAY="$a.$b.$c.1"\n\
        fi\n\
        sudo ip route add default via "$GATEWAY" dev eth0 2>/dev/null || true\n\
    fi\n\
fi\n' > /etc/profile.d/wsl-network-fix.sh \
    && chmod +x /etc/profile.d/wsl-network-fix.sh

# Allow dev user to run ip and tee commands without password for network fix script
RUN echo "dev ALL=(ALL) NOPASSWD: /usr/sbin/ip, /usr/bin/tee /etc/resolv.conf, /usr/bin/tee -a /etc/resolv.conf" >> /etc/sudoers.d/wsl-network \
    && chmod 440 /etc/sudoers.d/wsl-network

# Create symlinks to Windows tools (will work when WSL is running)
# hadolint ignore=SC2015
RUN ln -s '/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe' /usr/bin/git-credential-manager || true \
    && ln -s '/mnt/c/Program Files/Microsoft VS Code/code.exe' /usr/bin/code || true


# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ STAGE 2: BUILD TOOLS                                                                          ║
# ║ Purpose: Verify compilers and build systems are available                                     ║
# ║ Contains: build-essential (gcc, g++, make, cmake) already installed in base                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

FROM base AS build-tools

# Build tools are already installed via build-essential in base stage
# This stage exists as a logical separation point and for potential future build-only operations
# Verify build tools are available
RUN gcc --version && g++ --version && make --version


# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ STAGE 3: PACKAGE MANAGERS                                                                     ║
# ║ Purpose: Install all package managers before using them for tools                             ║
# ║ Contains: Git config for all users, Homebrew, NVM, Gobrew installation (no packages yet)     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

FROM build-tools AS package-managers


#  ██  ██       ██████  ██ ████████      ██████  ██████  ███    ██ ███████ ██  ██████
# ████████     ██       ██    ██        ██      ██    ██ ████   ██ ██      ██ ██
#  ██  ██      ██   ███ ██    ██        ██      ██    ██ ██ ██  ██ █████   ██ ██   ███
# ████████     ██    ██ ██    ██        ██      ██    ██ ██  ██ ██ ██      ██ ██    ██
#  ██  ██       ██████  ██    ██         ██████  ██████  ██   ████ ██      ██  ██████

WORKDIR /home/${USER}
USER ${USER}

# Configure git for dev user (uses default credential helper: store)
RUN /usr/local/bin/setup-git-config.sh

WORKDIR /home/linuxbrew
USER linuxbrew

# Configure git for linuxbrew user (uses default credential helper: store)
RUN /usr/local/bin/setup-git-config.sh

WORKDIR /home/root
USER root

# Configure git for root user (uses Windows Git Credential Manager)
RUN /usr/local/bin/setup-git-config.sh "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"


#  ██  ██      ██████  ██████  ███████ ██     ██
# ████████     ██   ██ ██   ██ ██      ██     ██
#  ██  ██      ██████  ██████  █████   ██  █  ██
# ████████     ██   ██ ██   ██ ██      ██ ███ ██
#  ██  ██      ██████  ██   ██ ███████  ███ ███

WORKDIR /home/linuxbrew
USER linuxbrew

ENV PATH="${PATH}:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"

RUN git clone https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew \
    && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" \
    && brew --version \
    && brew doctor \
    && brew upgrade

# Fix ownership as root
USER root
RUN chown -R linuxbrew:linuxbrew /home/linuxbrew/.linuxbrew

# Create /usr/local directories with proper permissions for Homebrew
# Note: We do NOT create a brew symlink in /usr/local/bin to avoid HOMEBREW_PREFIX conflicts
RUN mkdir -p /usr/local/bin /usr/local/etc /usr/local/include /usr/local/lib /usr/local/sbin /usr/local/share /usr/local/share/man /usr/local/share/man/man1 /usr/local/var /usr/local/Cellar /usr/local/Caskroom /usr/local/Frameworks /usr/local/opt \
    && chown -R ${USER}:${GROUP} /usr/local \
    && chmod -R u+w /usr/local


#  ██  ██      ███    ██ ██    ██ ███    ███
# ████████     ████   ██ ██    ██ ████  ████
#  ██  ██      ██ ██  ██ ██    ██ ██ ████ ██
# ████████     ██  ██ ██  ██  ██  ██  ██  ██
#  ██  ██      ██   ████   ████   ██      ██

WORKDIR /home/${USER}
USER ${USER}

RUN mkdir -p /home/${USER}/.nvm \
    && chown ${USER}:${GROUP} -R /home/${USER}/.nvm

ENV PATH="${PATH}:/home/${USER}/.nvm/bin"

# Install NVM (Node Version Manager) - DO NOT install Node.js yet
# hadolint ignore=DL4006
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash \
    && export NVM_DIR="/home/${USER}/.nvm" \
    && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" \
    && [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" \
    && echo 'export NVM_DIR="/home/${USER}/.nvm"' >> /home/${USER}/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/${USER}/.bashrc \
    && echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> /home/${USER}/.bashrc \
    && echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/${USER}/.bashrc \
    && echo 'export ENABLE_LSP_TOOLS=1' >> /home/${USER}/.bashrc


#  ██  ██       ██████   ██████  ██████  ██████  ███████ ██     ██
# ████████     ██       ██    ██ ██   ██ ██   ██ ██      ██     ██
#  ██  ██      ██   ███ ██    ██ ██████  ██████  █████   ██  █  ██
# ████████     ██    ██ ██    ██ ██   ██ ██   ██ ██      ██ ███ ██
#  ██  ██       ██████   ██████  ██████  ██   ██ ███████  ███ ███

# Set up PATH for Gobrew
ENV PATH="/home/${USER}/.gobrew/current/bin:/home/${USER}/.gobrew/bin:/home/${USER}/go/bin:/home/${USER}/go/pkg:$PATH"

# Install Gobrew (Go Version Manager) - DO NOT install Go yet
# hadolint ignore=DL4006
RUN curl -sL https://git.io/gobrew | bash


# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ STAGE 4: LANGUAGE RUNTIMES                                                                    ║
# ║ Purpose: Install language runtimes using package managers                                     ║
# ║ Contains: Node.js (via NVM), Python, Go (via Gobrew), Java, .NET, ClamAV, Browsers           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

FROM package-managers AS runtimes


#  ██  ██      ███    ██  ██████  ██████  ███████             ██ ███████
# ████████     ████   ██ ██    ██ ██   ██ ██                  ██ ██
#  ██  ██      ██ ██  ██ ██    ██ ██   ██ █████               ██ ███████
# ████████     ██  ██ ██ ██    ██ ██   ██ ██             ██   ██      ██
#  ██  ██      ██   ████  ██████  ██████  ███████ ██      █████  ███████

WORKDIR /home/${USER}
USER ${USER}

# Install Node.js LTS using NVM and global npm packages
RUN export NVM_DIR="/home/${USER}/.nvm" \
    && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" \
    && [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" \
    && nvm install node \
    && nvm use node \
    && node -v \
    && npm -v \
    && npm install -g @anthropic-ai/claude-code @openai/codex npm@latest dep-check npm-check newman snyk


#  ██  ██      ██████  ██    ██ ████████ ██   ██  ██████  ███    ██
# ████████     ██   ██  ██  ██     ██    ██   ██ ██    ██ ████   ██
#  ██  ██      ██████    ████      ██    ███████ ██    ██ ██ ██  ██
# ████████     ██         ██       ██    ██   ██ ██    ██ ██  ██ ██
#  ██  ██      ██         ██       ██    ██   ██  ██████  ██   ████

WORKDIR /home/root
USER root

ENV PATH="/home/${USER}/.local/bin:${PATH}"

RUN apt-get -y update \
    && apt-get install -y --no-install-recommends \
      libbz2-dev \
      libffi-dev \
      libgdbm-dev \
      liblzma-dev \
      libncurses-dev \
      libnss3-dev \
      libreadline-dev \
      libsqlite3-dev \
      libssl-dev \
      tk-dev \
      uuid-dev \
      wget \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get -y update \
    && apt-get install -y --no-install-recommends \
      python3.12-full \
      python3.13-full \
      python3.14-full \
      python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get install -y --no-install-recommends \
    && python3.14 --version \
    && python3.13 --version \
    && python3.12 --version \
    && which python3.14 \
    && which python3.13 \
    && which python3.12 \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.12 3 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.13 2 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.14 1 \
    && update-alternatives --set python /usr/bin/python3.14 \
    && printf '#!/bin/bash\nupdate-alternatives --set python "/usr/bin/python3.12"\n' > /usr/bin/set-python-12.sh \
    && printf '#!/bin/bash\nupdate-alternatives --set python "/usr/bin/python3.13"\n' > /usr/bin/set-python-13.sh \
    && printf '#!/bin/bash\nupdate-alternatives --set python "/usr/bin/python3.14"\n' > /usr/bin/set-python-14.sh \
    && chmod +x /usr/bin/set-python-12.sh \
    && chmod +x /usr/bin/set-python-13.sh \
    && chmod +x /usr/bin/set-python-14.sh \
    && python --version


#  ██  ██       ██████ ██       █████  ███    ███  █████  ██    ██
# ████████     ██      ██      ██   ██ ████  ████ ██   ██ ██    ██
#  ██  ██      ██      ██      ███████ ██ ████ ██ ███████ ██    ██
# ████████     ██      ██      ██   ██ ██  ██  ██ ██   ██  ██  ██
#  ██  ██       ██████ ███████ ██   ██ ██      ██ ██   ██   ████

# ClamAV configuration after clamav and clamav-daemon are installed
# see https://https://aaronbrighton.medium.com/installation-configuration-of-clamav-antivirus-on-ubuntu-18-04-a6416bab3b41
# hadolint ignore=DL4006
RUN apt-get update \
    && apt-get install -y --no-install-recommends clamav clamav-daemon \
    && echo "0 1 * * 0 root /usr/bin/clamdscan --fdpass --log /var/log/clamav/clamav.log --move=/root/quartine /" | tee /etc/cron.d/clamav-scan \
    && printf "ExcludePath ^/proc\nExcludePath ^/sys\nExcludePath ^/snap\nExcludePath ^/dev\nExcludePath ^/run\nExcludePath ^/var/lib/lxcfs/cgroup\nExcludePath ^/root/quarantine\nExcludePath ^/var/lib/docker\n" >> /etc/clamav/clamd.conf \
    && echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.conf \
    && mkdir -p /var/clamav/tmp \
    && chown clamav:root /var/clamav/tmp \
    && chmod 770 /var/clamav/tmp \
    && rm -rf /var/lib/apt/lists/*

# Install ClamAV on-access scanner systemd service
COPY config/etc/systemd/system/clamonacc.service /etc/systemd/system/clamonacc.service


#  ██  ██       ██████   ██████
# ████████     ██       ██    ██
#  ██  ██      ██   ███ ██    ██
# ████████     ██    ██ ██    ██
#  ██  ██       ██████   ██████

WORKDIR /home/${USER}
USER ${USER}

# Install Go using Gobrew (Gobrew was installed in Stage 3)
RUN .gobrew/bin/gobrew use latest \
    && .gobrew/bin/gobrew install latest \
    && go install github.com/codesenberg/bombardier@latest


#  ██  ██      ███    ██ ██    ██  ██████  ███████ ████████     ██████  ██████  ███████ ██████
# ████████     ████   ██ ██    ██ ██       ██         ██        ██   ██ ██   ██ ██      ██   ██
#  ██  ██      ██ ██  ██ ██    ██ ██   ███ █████      ██        ██████  ██████  █████   ██████
# ████████     ██  ██ ██ ██    ██ ██    ██ ██         ██        ██      ██   ██ ██      ██
#  ██  ██      ██   ████  ██████   ██████  ███████    ██        ██      ██   ██ ███████ ██

WORKDIR /home/root
USER root

# Prep for NuGet (.NET)
RUN mkdir -p /home/${USER}/.nuget

COPY NuGet.Config /home/${USER}/.nuget/NuGet/NuGet.Config
COPY NuGet.Config /home/root/.nuget/NuGet/NuGet.Config


#  ██  ██       █████  ██████  ████████        ██████  ███████ ████████     ██████
# ████████     ██   ██ ██   ██    ██          ██       ██         ██             ██
#  ██  ██      ███████ ██████     ██    █████ ██   ███ █████      ██         █████
# ████████     ██   ██ ██         ██          ██    ██ ██         ██        ██
#  ██  ██      ██   ██ ██         ██           ██████  ███████    ██        ███████

WORKDIR /home/root
USER root

# Add Mozilla Team PPA for Firefox (Ubuntu 24.04's default firefox package requires snap)
RUN add-apt-repository -y ppa:mozillateam/ppa \
    && printf 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' > /etc/apt/preferences.d/mozilla-firefox

# Azure CLI: Microsoft has not published a 26.04 (resolute) apt suite yet, so we
# pin the repo to the noble suite, which installs cleanly with all dependencies
# on 26.04. The azure-cli package itself is installed from the main apt list
# below. This replaces the previous jammy-shim + install-script approach.
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft-azurecli.gpg \
    && chmod 644 /etc/apt/keyrings/microsoft-azurecli.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft-azurecli.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main" | tee /etc/apt/sources.list.d/azure-cli.list

# Add Google Chrome repository
# hadolint ignore=DL4006
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list

# Add Microsoft Edge repository
# hadolint ignore=DL4006
RUN wget -q -O - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-edge-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge-keyring.gpg] https://packages.microsoft.com/repos/edge stable main" | tee /etc/apt/sources.list.d/microsoft-edge.list

# Add k6 load testing tool repository
# k6 rotated its signing key; fetch it directly from dl.k6.io rather than a
# keyserver (the old keyserver fingerprint no longer matches the repo signature)
# hadolint ignore=DL4006
RUN curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg \
    && chmod 644 /usr/share/keyrings/k6-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | tee /etc/apt/sources.list.d/k6.list

# Install main packages including browsers
# checkov:skip=CKV2_DOCKER_1: sudo package is required for development container
RUN apt-get -y update \
    && apt-get -y upgrade \
    && apt-get -y install --no-install-recommends \
        alsa-utils \
        apparmor-utils \
        audacity \
        azure-cli \
        buildah \
        bzip2 \
        cifs-utils \
        clang \
        cmake \
        consul \
        daemonize \
        dbus \
        dbus-x11 \
        bind9-dnsutils \
        dotnet-sdk-8.0 \
        dotnet-sdk-9.0 \
        entr \
        extlinux \
        ffmpeg \
        file \
        firefox \
        g++ \
        gawk \
        gcc \
        gdb \
        gimp \
        git-flow \
        git-lfs \
        google-chrome-stable \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav \
        gstreamer1.0-tools \
        gstreamer1.0-alsa \
        gstreamer1.0-pulseaudio \
        htop \
        imagemagick \
        intltool \
        iproute2 \
        iptables \
        iputils-ping \
        k6 \
        keychain \
        less \
        libasound2-plugins \
        libc6 \
        libgcc-s1 \
        libgssapi-krb5-2 \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        libicu78 \
        liblttng-ust1t64 \
        libpulse0 \
        libpulse-dev \
        libsndfile1 \
        libssl3t64 \
        libstdc++6 \
        libunwind8 \
        libv4l-dev \
        lldb \
        make \
        maven \
        microsoft-edge-stable \
        nano \
        ncdu \
        net-tools \
        ninja-build \
        nvidia-cuda-toolkit \
        nvidia-cuda-toolkit-gcc \
        obs-studio \
        7zip \
        packer \
        pavucontrol \
        pkg-config \
        polkitd \
        pkexec \
        protobuf-compiler \
        pulseaudio \
        pulseaudio-utils \
        rsync \
        shellcheck\
        snapd \
        socat \
        sox \
        ssh \
        sudo \
        synaptic \
        tasksel \
        tmux \
        uuid-runtime \
        v4l-utils \
        vault \
        valgrind \
        vlc \
        x11-apps \
        yamllint \
        zlib1g \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*


#  ██  ██           ██  █████  ██    ██  █████
# ████████          ██ ██   ██ ██    ██ ██   ██
#  ██  ██           ██ ███████ ██    ██ ███████
# ████████     ██   ██ ██   ██  ██  ██  ██   ██
#  ██  ██       █████  ██   ██   ████   ██   ██

WORKDIR /home/root
USER root

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        openjdk-8-jdk \
        openjdk-11-jdk \
        openjdk-17-jdk \
        openjdk-21-jdk \
        openjdk-25-jdk \
    && update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-8-openjdk-amd64/bin/java 1 \
    && update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-11-openjdk-amd64/bin/java 2 \
    && update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-17-openjdk-amd64/bin/java 3 \
    && update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-21-openjdk-amd64/bin/java 4 \
    && update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-25-openjdk-amd64/bin/java 5 \
    && update-alternatives --set java "/usr/lib/jvm/java-25-openjdk-amd64/bin/java" \
    && printf '#!/bin/bash\nupdate-alternatives --set java "/usr/lib/jvm/java-8-openjdk-amd64/bin/java"\n' > /usr/bin/set-java-8.sh \
    && printf '#!/bin/bash\nupdate-alternatives --set java "/usr/lib/jvm/java-11-openjdk-amd64/bin/java"\n' > /usr/bin/set-java-11.sh \
    && printf '#!/bin/bash\nupdate-alternatives --set java "/usr/lib/jvm/java-17-openjdk-amd64/bin/java"\n' > /usr/bin/set-java-17.sh \
    && printf '#!/bin/bash\nupdate-alternatives --set java "/usr/lib/jvm/java-21-openjdk-amd64/bin/java"\n' > /usr/bin/set-java-21.sh \
    && printf '#!/bin/bash\nupdate-alternatives --set java "/usr/lib/jvm/java-25-openjdk-amd64/bin/java"\n' > /usr/bin/set-java-25.sh \
    && chmod +x /usr/bin/set-java-8.sh \
    && chmod +x /usr/bin/set-java-11.sh \
    && chmod +x /usr/bin/set-java-17.sh \
    && chmod +x /usr/bin/set-java-21.sh \
    && chmod +x /usr/bin/set-java-25.sh \
    && chown -R root:root /usr/bin/set-java-8.sh \
    && chown -R root:root /usr/bin/set-java-11.sh \
    && chown -R root:root /usr/bin/set-java-17.sh \
    && chown -R root:root /usr/bin/set-java-21.sh \
    && chown -R root:root /usr/bin/set-java-25.sh \
    && rm -rf /var/lib/apt/lists/*


#  ██  ██         ███    ██ ███████ ████████     ████████  ██████   ██████  ██      ███████
# ████████        ████   ██ ██         ██           ██    ██    ██ ██    ██ ██      ██
#  ██  ██         ██ ██  ██ █████      ██           ██    ██    ██ ██    ██ ██      ███████
# ████████        ██  ██ ██ ██         ██           ██    ██    ██ ██    ██ ██           ██
#  ██  ██      ██ ██   ████ ███████    ██           ██     ██████   ██████  ███████ ███████

WORKDIR /home/${USER}
USER ${USER}

ENV PATH="/home/${USER}/.dotnet/tools:$PATH"

# Install .NET global tools with retry logic for network resilience
# hadolint ignore=SC2015
RUN for i in 1 2 3; do \
      dotnet tool install -g coverlet.console && \
      dotnet tool install -g CycloneDX && \
      dotnet tool install -g dotnet-coverage && \
      dotnet tool install -g dotnet-dump && \
      dotnet tool install -g dotnet-format && \
      dotnet tool install -g dotnet-gcdump && \
      dotnet tool install -g dotnet-reportgenerator-globaltool && \
      dotnet tool install -g dotnet-script && \
      dotnet tool install -g dotnet-trace && \
      dotnet tool install -g fake-cli && \
      dotnet tool install -g GitVersion.Tool && \
      dotnet tool install -g paket && \
      break || { echo "Attempt $i failed, retrying in 5 seconds..."; sleep 5; } \
    done

# PowerShell (pwsh): not published in the 26.04 apt repo, and the 'powershell'
# dotnet global tool ships a broken package (missing DotnetToolSettings.xml), so
# install the official cross-platform binary archive — the method Microsoft
# documents for distros without a package. Version resolved from the latest
# GitHub release.
USER root
# hadolint ignore=DL4006
RUN PWSH_URL=$(curl -fsSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest | jq -r '.assets[] | select(.name|test("linux-x64.tar.gz$")) | .browser_download_url') \
    && curl -fsSL -o /tmp/powershell.tar.gz "${PWSH_URL}" \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
    && rm -f /tmp/powershell.tar.gz \
    && pwsh --version
USER ${USER}


# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ STAGE 5: DEVELOPMENT TOOLS                                                                    ║
# ║ Purpose: Install development tools via package managers                                       ║
# ║ Contains: Shell config, Act config, Homebrew packages, Podman config, root symlinks          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

FROM runtimes AS dev-tools


#  ██  ██       █████  ██      ██  █████  ███████ ███████ ███████
# ████████     ██   ██ ██      ██ ██   ██ ██      ██      ██
#  ██  ██      ███████ ██      ██ ███████ ███████ █████   ███████
# ████████     ██   ██ ██      ██ ██   ██      ██ ██           ██
#  ██  ██      ██   ██ ███████ ██ ██   ██ ███████ ███████ ███████

WORKDIR /home/root
USER root

RUN echo 'alias d="docker"' >> /home/${USER}/.bashrc \
    && echo 'alias dc="docker-compose"' >> /home/${USER}/.bashrc \
    && echo 'alias k="kubectl"' >> /home/${USER}/.bashrc \
    && echo 'alias p="podman"' >> /home/${USER}/.bashrc \
    && echo 'alias pc="podman compose"' >> /home/${USER}/.bashrc \
    && echo 'alias podman-compose="podman compose"' >> /home/${USER}/.bashrc \
    && echo 'alias tf="tofu"' >> /home/${USER}/.bashrc \
    && echo 'export BROWSER=wslview' >> /home/${USER}/.bashrc \
    && echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock' >> /home/${USER}/.bashrc \
    && echo 'export ENABLE_LSP_TOOLS=1' >> /home/${USER}/.bashrc \
    && echo '# Fix Windows directory permissions (missing execute bit prevents cd)' >> /home/${USER}/.bashrc \
    && echo 'fix-win-perms() { find "${1:-.}" -maxdepth "${2:-1}" -type d ! -perm -111 -exec chmod +x {} \; 2>/dev/null && echo "Fixed directory permissions in ${1:-.}"; }' >> /home/${USER}/.bashrc


#  ██  ██       █████   ██████ ████████
# ████████     ██   ██ ██         ██
#  ██  ██      ███████ ██         ██
# ████████     ██   ██ ██         ██
#  ██  ██      ██   ██  ██████    ██

# Configure act (GitHub Actions local runner) with custom images and rootless Podman backend
# Note: Podman socket will be started automatically via systemd user session
# Using '-' for container-daemon-socket disables bind mounting the socket into job containers
COPY config/home/dev/.actrc /home/${USER}/.actrc
RUN chown ${USER}:${GROUP} /home/${USER}/.actrc

# Create symlink for root user to access the same .actrc configuration
USER root
RUN ln -sf /home/${USER}/.actrc /root/.actrc
USER ${USER}


#  ██  ██      ██████  ██████  ███████ ██     ██     ██████
# ████████     ██   ██ ██   ██ ██      ██     ██          ██
#  ██  ██      ██████  ██████  █████   ██  █  ██      █████
# ████████     ██   ██ ██   ██ ██      ██ ███ ██     ██
#  ██  ██      ██████  ██   ██ ███████  ███ ███      ███████

WORKDIR /home/root
USER root

RUN chown -R ${USER}:${GROUP} /home/linuxbrew \
    && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" \
    && test -d /home/linuxbrew/.linuxbrew

WORKDIR /home/${USER}
USER ${USER}

ARG BUILD_DATE

# Ensure DNS is properly configured for network operations in this stage
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4\n" > /etc/resolv.conf \
    && chmod 644 /etc/resolv.conf
USER ${USER}

# Disable Homebrew's auto-update and API mode during build to reduce network dependencies
ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV HOMEBREW_NO_INSTALL_FROM_API=1

# Add Homebrew taps with DNS setup and retry logic for network resilience
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
USER ${USER}
# hadolint ignore=SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Adding Homebrew taps..." && \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
      brew tap spring-io/tap && \
      brew tap tofuutils/tap && \
      brew tap terraform-linters/tap && \
      brew trust spring-io/tap tofuutils/tap terraform-linters/tap && \
      echo "Successfully added all taps" && \
      break || { echo "Failed attempt $attempt, retrying in 10 seconds..."; sleep 10; }; \
    done

# Install development tools with DNS setup and retry logic
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
USER ${USER}
# hadolint ignore=SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Installing development tools..." && \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
      brew install act && \
      brew install btop && \
      brew install delta && \
      brew install gcc && \
      brew install gh && \
      brew install gitversion && \
      brew install starship && \
      brew install tldr && \
      echo "Successfully installed all development tools" && \
      break || { echo "Failed attempt $attempt, retrying in 10 seconds..."; sleep 10; }; \
    done

# Install container tools with DNS setup and retry logic
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
USER ${USER}
# hadolint ignore=SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Installing container tools..." && \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
      brew install container-structure-test && \
      brew install copa && \
      brew install cosign && \
      brew install crane && \
      brew install dive && \
      brew install hadolint && \
      brew install helm && \
      brew install k9s && \
      brew install kompose && \
      brew install krew && \
      brew install kubescape && \
      brew install kustomize && \
      brew install lazydocker && \
      brew install mkcert && \
      brew install podman && \
      echo "Successfully installed all container tools" && \
      break || { echo "Failed attempt $attempt, retrying in 10 seconds..."; sleep 10; }; \
    done

# Install security scanning tools with DNS setup and retry logic
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
USER ${USER}
# hadolint ignore=SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Installing security scanning tools..." && \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
      brew install dependency-check && \
      brew install gitleaks && \
      brew install grype && \
      brew install osv-scanner && \
      brew install syft && \
      brew install trivy && \
      echo "Successfully installed all security tools" && \
      break || { echo "Failed attempt $attempt, retrying in 10 seconds..."; sleep 10; }; \
    done

# Install infrastructure/terraform tools with DNS setup and retry logic
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
USER ${USER}
# hadolint ignore=SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Installing infrastructure/terraform tools..." && \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
      brew install infracost && \
      brew install tenv && \
      brew install terraform-docs && \
      brew install terraformer && \
      brew install terrascan && \
      brew install terraform-linters/tap/tflint && \
      brew install tfsec && \
      brew install tfupdate && \
      echo "Successfully installed all infrastructure tools" && \
      break || { echo "Failed attempt $attempt, retrying in 10 seconds..."; sleep 10; }; \
    done

# Install specialized tools with DNS setup and retry logic
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
USER ${USER}
# hadolint ignore=SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Installing specialized tools..." && \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
      brew install linka-cloud/tap/d2vm && \
      brew install spring-boot && \
      brew install uv && \
      brew install yamllint && \
      brew install yq && \
      echo "Successfully installed all specialized tools" && \
      break || { echo "Failed attempt $attempt, retrying in 10 seconds..."; sleep 10; }; \
    done

# Upgrade all brew packages and configure tenv with DNS setup and retry logic
USER root
RUN printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
USER ${USER}
# hadolint ignore=SC2015
RUN for attempt in 1 2 3; do \
      echo "Attempt $attempt: Upgrading brew packages and configuring tenv..." && \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
      brew upgrade && \
      tenv opentofu install latest && \
      tenv opentofu use latest && \
      echo "Successfully upgraded and configured" && \
      break || { echo "Failed attempt $attempt, retrying in 10 seconds..."; sleep 10; }; \
    done

# Create symlinks for Homebrew-installed tools to /usr/local/bin for root access
USER root
RUN ln -sf /home/linuxbrew/.linuxbrew/bin/act /usr/local/bin/act


#  ██  ██       █████  ███    ██ ████████ ██  ██████  ██████   █████  ██    ██ ██ ████████ ██    ██
# ████████     ██   ██ ████   ██    ██    ██ ██       ██   ██ ██   ██ ██    ██ ██    ██     ██  ██
#  ██  ██      ███████ ██ ██  ██    ██    ██ ██   ███ ██████  ███████ ██    ██ ██    ██      ████
# ████████     ██   ██ ██  ██ ██    ██    ██ ██    ██ ██   ██ ██   ██  ██  ██  ██    ██       ██
#  ██  ██      ██   ██ ██   ████    ██    ██  ██████  ██   ██ ██   ██   ████   ██    ██       ██

# Install Antigravity from apt repository
RUN apt-get update \
    && apt-get install -y --no-install-recommends antigravity \
    && rm -rf /var/lib/apt/lists/*

USER ${USER}


#  ██  ██      ███████ ██      ██    ██ ██     ██  █████  ██    ██
# ████████     ██      ██       ██  ██  ██     ██ ██   ██  ██  ██
#  ██  ██      █████   ██        ████   ██  █  ██ ███████   ████
# ████████     ██      ██         ██    ██ ███ ██ ██   ██    ██
#  ██  ██      ██      ███████    ██     ███ ███  ██   ██    ██

WORKDIR /home/${USER}
USER ${USER}

# Install Flyway
# hadolint ignore=DL4006
RUN FLYWAY_REPO="https://github.com/flyway/flyway" \
    && LATEST_VERSION=$(curl -s https://api.github.com/repos/flyway/flyway/releases/latest | jq -r '.tag_name') \
    && export LATEST_VERSION \
    && FLYWAY_VERSION=${LATEST_VERSION##*-} \
    && echo "Flyway version is $FLYWAY_VERSION." \
    && wget -q --progress=dot:giga "https://github.com/flyway/flyway/releases/download/flyway-${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz" -O flyway.tar.gz \
    && file flyway.tar.gz \
    && tar -xvzf flyway.tar.gz \
    && rm flyway.tar.gz

# Create symlink as root
USER root
# hadolint ignore=DL4006
RUN ln -s "/home/${USER}/flyway-$(curl -s https://api.github.com/repos/flyway/flyway/releases/latest | jq -r '.tag_name' | sed 's/flyway-//')/flyway" /usr/local/bin/flyway \
    && flyway -v

USER ${USER}

#  ██  ██      ██      ██  ██████  ██    ██ ██ ██████   █████  ███████ ███████
# ████████     ██      ██ ██    ██ ██    ██ ██ ██   ██ ██   ██ ██      ██
#  ██  ██      ██      ██ ██    ██ ██    ██ ██ ██████  ███████ ███████ █████
# ████████     ██      ██ ██ ▄▄ ██ ██    ██ ██ ██   ██ ██   ██      ██ ██
#  ██  ██      ███████ ██  ██████   ██████  ██ ██████  ██   ██ ███████ ███████
#                             ▀▀

# Install Liquibase
# hadolint ignore=DL4006
RUN LIQUIBASE_REPO="https://github.com/liquibase/liquibase" \
    && LATEST_VERSION=$(curl -s https://api.github.com/repos/liquibase/liquibase/releases/latest | jq -r '.tag_name') \
    && export LATEST_VERSION \
    && LIQUIBASE_VERSION=${LATEST_VERSION#v} \
    && echo "Liquibase version is $LIQUIBASE_VERSION." \
    && wget -q --progress=dot:giga "https://github.com/liquibase/liquibase/releases/download/v${LIQUIBASE_VERSION}/liquibase-${LIQUIBASE_VERSION}.tar.gz" -O liquibase.tar.gz \
    && file liquibase.tar.gz \
    && mkdir -p liquibase \
    && tar -xzf liquibase.tar.gz -C liquibase \
    && chmod +x liquibase/liquibase \
    && rm liquibase.tar.gz

# Create symlink as root
USER root
RUN ln -s "/home/${USER}/liquibase/liquibase" /usr/local/bin/liquibase \
    && liquibase --version

USER ${USER}


#  ██  ██       ██████  ██████  ██████  ███████  ██████  ██
# ████████     ██      ██    ██ ██   ██ ██      ██    ██ ██
#  ██  ██      ██      ██    ██ ██   ██ █████   ██    ██ ██
# ████████     ██      ██    ██ ██   ██ ██      ██ ▄▄ ██ ██
#  ██  ██       ██████  ██████  ██████  ███████  ██████  ███████
#                                                  ▀▀

USER root
WORKDIR /home/root

# hadolint ignore=DL4006
RUN CODEQL_REPO="https://github.com/github/codeql-action" \
    && DOWNLOAD_DIR="/home/${USER}" \
    && LATEST_VERSION=$(curl -sL https://api.github.com/repos/github/codeql-action/releases/latest | jq -r '.tag_name') \
    && export LATEST_VERSION \
    && CODEQL_VERSION=${LATEST_VERSION##*-} \
    && echo "CodeQL version is $CODEQL_VERSION." \
    && curl -sL "https://github.com/github/codeql-action/releases/download/codeql-bundle-${CODEQL_VERSION}/codeql-bundle-linux64.tar.gz" -o codeql-bundle-linux64.tar.gz \
    && tar -xvf codeql-bundle-linux64.tar.gz \
    && mv codeql /usr/local/bin/codeql \
    && ln -s /usr/local/bin/codeql/codeql /usr/bin/codeql \
    && rm codeql-bundle-linux64.tar.gz \
    && codeql --version


#  ██  ██      ██    ██ ███████ ███████ ██████   ██████   ██  ██████   ██████   ██    ███████ ███████ ██████  ██    ██ ██  ██████ ███████
# ████████     ██    ██ ██      ██      ██   ██ ██    ██ ███ ██  ████ ██  ████ ███    ██      ██      ██   ██ ██    ██ ██ ██      ██
#  ██  ██      ██    ██ ███████ █████   ██████  ██ ██ ██  ██ ██ ██ ██ ██ ██ ██  ██    ███████ █████   ██████  ██    ██ ██ ██      █████
# ████████     ██    ██      ██ ██      ██   ██ ██ ██ ██  ██ ████  ██ ████  ██  ██         ██ ██      ██   ██  ██  ██  ██ ██      ██
#  ██  ██       ██████  ███████ ███████ ██   ██  █ ████   ██  ██████   ██████   ██ ██ ███████ ███████ ██   ██   ████   ██  ██████ ███████

USER root
WORKDIR /home/root

RUN mkdir -p /etc/systemd/system/user@1001.service.d \
    && echo "[Service]" >> /etc/systemd/system/user@1001.service.d/override.conf \
    && echo "ExecStartPre=" >> /etc/systemd/system/user@1001.service.d/override.conf \
    && systemctl enable user@1001.service


#  ██  ██      ██████  ██    ██ ████████ ██   ██  ██████  ███    ██     ████████  ██████   ██████  ██      ███████
# ████████     ██   ██  ██  ██     ██    ██   ██ ██    ██ ████   ██        ██    ██    ██ ██    ██ ██      ██
#  ██  ██      ██████    ████      ██    ███████ ██    ██ ██ ██  ██        ██    ██    ██ ██    ██ ██      ███████
# ████████     ██         ██       ██    ██   ██ ██    ██ ██  ██ ██        ██    ██    ██ ██    ██ ██           ██
#  ██  ██      ██         ██       ██    ██   ██  ██████  ██   ████        ██     ██████   ██████  ███████ ███████

WORKDIR /home/${USER}
USER ${USER}

# Install Python packages
# Note: Not upgrading pip since it's managed by Debian package manager
# Using --ignore-installed to avoid conflicts with system-installed packages like jsonschema
RUN python -m pip install --no-cache-dir --break-system-packages --ignore-installed \
      checkov \
      detect-secrets \
      podman-compose \
      pre-commit \
      pyright \
      uv


# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ STAGE 6: FINAL CONFIGURATION                                                                  ║
# ║ Purpose: Final system configuration, services, and cleanup                                    ║
# ║ Contains: WSLg config, Podman config, system services, bash config, final cleanup             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

FROM dev-tools AS final


#  ██  ██      ███████ ██ ███    ██  █████  ██          ███████ ███████ ████████ ██    ██ ██████
# ████████     ██      ██ ████   ██ ██   ██ ██          ██      ██         ██    ██    ██ ██   ██
#  ██  ██      █████   ██ ██ ██  ██ ███████ ██          ███████ █████      ██    ██    ██ ██████
# ████████     ██      ██ ██  ██ ██ ██   ██ ██               ██ ██         ██    ██    ██ ██
#  ██  ██      ██      ██ ██   ████ ██   ██ ███████     ███████ ███████    ██     ██████  ██

USER root
WORKDIR /home/root

RUN apt-get -y update \
    && apt-get -y upgrade \
    && printf 'export PATH="%s"\n' "${PATH}" >> /home/${USER}/.bashrc \
    && rm -rf /var/lib/apt/lists/*

# Systemd (system instance) oneshot unit to make "/" recursively shared
# Install make-root-shared systemd service for rootless containers
COPY config/etc/systemd/system/make-root-shared.service /etc/systemd/system/make-root-shared.service

# Enable the system unit (creates the wants/ symlink)
RUN ln -s ../make-root-shared.service /etc/systemd/system/multi-user.target.wants/make-root-shared.service || true

# Install Starship configuration
COPY config/home/dev/.config/starship.toml /home/${USER}/.config/starship.toml
RUN chown ${USER}:${GROUP} /home/${USER}/.config/starship.toml

RUN echo "" >> /home/${USER}/.bashrc \
    && echo "# Initialize Starship prompt" >> /home/${USER}/.bashrc \
    && echo 'eval "$(starship init bash)"' >> /home/${USER}/.bashrc \
    && echo "" >> /home/${USER}/.bashrc \
    && echo "# Start keychain and add the key" >> /home/${USER}/.bashrc \
    && echo 'eval $(keychain --eval ~/.ssh/id_rsa)' >> /home/${USER}/.bashrc \
    && echo "" >> /home/${USER}/.bashrc \
    && echo '[[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path bash)"' >> /home/${USER}/.bashrc \
    && echo "" >> /home/${USER}/.bashrc \
    && echo "# Prompt for git user config if not set" >> /home/${USER}/.bashrc \
    && echo 'if [ -z "$(git config --global user.email)" ] || [ -z "$(git config --global user.name)" ]; then' >> /home/${USER}/.bashrc \
    && echo '  echo "Git user configuration is incomplete."' >> /home/${USER}/.bashrc \
    && echo '  if [ -z "$(git config --global user.name)" ]; then' >> /home/${USER}/.bashrc \
    && echo '    read -p "Enter your git user name: " git_user_name' >> /home/${USER}/.bashrc \
    && echo '    git config --global user.name "$git_user_name"' >> /home/${USER}/.bashrc \
    && echo '  fi' >> /home/${USER}/.bashrc \
    && echo '  if [ -z "$(git config --global user.email)" ]; then' >> /home/${USER}/.bashrc \
    && echo '    read -p "Enter your git user email: " git_user_email' >> /home/${USER}/.bashrc \
    && echo '    git config --global user.email "$git_user_email"' >> /home/${USER}/.bashrc \
    && echo '  fi' >> /home/${USER}/.bashrc \
    && echo '  echo "Git configuration updated."' >> /home/${USER}/.bashrc \
    && echo 'fi' >> /home/${USER}/.bashrc \
    && echo "" >> /home/${USER}/.bashrc \
    && echo "# Migrate SSH keys from Windows if not present in WSL" >> /home/${USER}/.bashrc \
    && echo 'if [ ! -f "/home/${USER}/.ssh/id_rsa" ] && [ -d "/mnt/c/Users" ]; then' >> /home/${USER}/.bashrc \
    && echo '  for windows_user_dir in /mnt/c/Users/*/; do' >> /home/${USER}/.bashrc \
    && echo '    windows_user=$(basename "$windows_user_dir")' >> /home/${USER}/.bashrc \
    && echo '    windows_ssh_dir="$windows_user_dir.ssh"' >> /home/${USER}/.bashrc \
    && echo '    if [ "$windows_user" != "Public" ] && [ "$windows_user" != "All Users" ] && [ -d "$windows_ssh_dir" ] && [ -n "$(ls -A "$windows_ssh_dir" 2>/dev/null)" ]; then' >> /home/${USER}/.bashrc \
    && echo '      mkdir -p /home/${USER}/.ssh' >> /home/${USER}/.bashrc \
    && echo '      cp "$windows_ssh_dir"/* /home/${USER}/.ssh/ 2>/dev/null' >> /home/${USER}/.bashrc \
    && echo '      find /home/${USER}/.ssh -type f -exec chmod 600 {} + 2>/dev/null' >> /home/${USER}/.bashrc \
    && echo '      find /home/${USER}/.ssh -type d -exec chmod 700 {} + 2>/dev/null' >> /home/${USER}/.bashrc \
    && echo '      chown -R ${USER}:${GROUP} /home/${USER}/.ssh 2>/dev/null' >> /home/${USER}/.bashrc \
    && echo '      echo "SSH keys migrated from Windows user: $windows_user"' >> /home/${USER}/.bashrc \
    && echo '      break' >> /home/${USER}/.bashrc \
    && echo '    fi' >> /home/${USER}/.bashrc \
    && echo '  done' >> /home/${USER}/.bashrc \
    && echo 'fi' >> /home/${USER}/.bashrc

# Podman engine config: use systemd cgroups + journald events (per-user default via /etc/skel)
RUN mkdir -p /etc/skel/.config/containers
COPY config/home/dev/.config/containers/containers.conf /etc/skel/.config/containers/containers.conf

# Give the current user the same containers.conf
RUN mkdir -p /home/${USER}/.config/containers \
  && cp /etc/skel/.config/containers/containers.conf /home/${USER}/.config/containers/containers.conf \
  && chown -R ${USER}:${GROUP} /home/${USER}/.config \
  && mkdir -p /etc/containers \
  && touch /etc/containers/nodocker

# Configure container registries to include docker.io, Azure CR, GitHub CR, and AWS ECR
COPY config/etc/containers/registries.conf /etc/containers/registries.conf

# Enable rootful Podman socket via systemd (system-wide service)
# This creates the socket at /run/podman/podman.sock which is accessible to all users
# and works properly with tools like 'act' that need to bind mount the socket
RUN mkdir -p /etc/systemd/system/sockets.target.wants && \
    ln -sf /lib/systemd/system/podman.socket /etc/systemd/system/sockets.target.wants/podman.socket

# Enable rootless Podman socket for the user (per-user systemd service)
# This creates the socket at /run/user/$(id -u)/podman/podman.sock for rootless operations
# The user socket is started by systemd --user when the user logs in (lingering is already enabled)
RUN mkdir -p /home/${USER}/.config/systemd/user/sockets.target.wants && \
    ln -sf /usr/lib/systemd/user/podman.socket /home/${USER}/.config/systemd/user/sockets.target.wants/podman.socket && \
    chown -R ${USER}:${GROUP} /home/${USER}/.config/systemd

# Create symlink from /run/podman/podman.sock to user socket for act compatibility
# Act expects to bind mount /run/podman/podman.sock but we use rootless Podman
# This symlink allows act to access the user socket via the standard path
RUN mkdir -p /run/podman && \
    chmod 755 /run/podman && \
    ln -sf /run/user/1001/podman/podman.sock /run/podman/podman.sock

RUN mkdir -p /home/${USER}/.ssh \
    && echo "Host ssh.dev.azure.com" >> /home/${USER}/.ssh/config \
    && echo "  IdentityFile ~/.ssh/id_rsa" >> /home/${USER}/.ssh/config \
    && echo "  IdentitiesOnly yes" >> /home/${USER}/.ssh/config \
    && echo "  HostkeyAlgorithms +ssh-rsa" >> /home/${USER}/.ssh/config \
    && echo "  PubkeyAcceptedKeyTypes=ssh-rsa" >> /home/${USER}/.ssh/config \
    && sh -c 'echo :WSLInterop:M::MZ::/init:PF > /usr/lib/binfmt.d/WSLInterop.conf' \
    && chown -R ${USER}:${GROUP} /home/${USER} \
    && printf '\nexport PODMAN_IGNORE_CGROUPSV1_WARNING=1\n' >> /home/${USER}/.bashrc \
    && printf '\nexport ENABLE_LSP_TOOLS=1\n' >> /home/${USER}/.bashrc \
    && printf '\nnvm use node\n' >> /home/${USER}/.bashrc

# Enable "linger" for the user without calling loginctl (works in images):
# creating /var/lib/systemd/linger/<user> is equivalent to `loginctl enable-linger <user>`
RUN mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/${USER} && \
    chmod 0644 /var/lib/systemd/linger/${USER}

# Add Chrome wrapper for WSL DPI scaling
COPY config/scripts/chrome-wsl /usr/local/bin/chrome-wsl
RUN chmod +x /usr/local/bin/chrome-wsl \
    && echo 'alias chrome=chrome-wsl' >> /home/${USER}/.bashrc


#  ██  ██       █████  ██    ██ ██████  ██  ██████      ██    ██ ██ ██████  ███████  ██████
# ████████     ██   ██ ██    ██ ██   ██ ██ ██    ██     ██    ██ ██ ██   ██ ██      ██    ██
#  ██  ██      ███████ ██    ██ ██   ██ ██ ██    ██     ██    ██ ██ ██   ██ █████   ██    ██
# ████████     ██   ██ ██    ██ ██   ██ ██ ██    ██      ██  ██  ██ ██   ██ ██      ██    ██
#  ██  ██      ██   ██  ██████  ██████  ██  ██████        ████   ██ ██████  ███████  ██████

# Configure PulseAudio for WSL2 audio support
# PulseAudio will use Windows host audio via WSLg
RUN mkdir -p /home/${USER}/.config/pulse
COPY config/home/dev/.config/pulse/client.conf /home/${USER}/.config/pulse/client.conf

# Configure ALSA to use PulseAudio by default
COPY config/home/dev/.asoundrc /home/${USER}/.asoundrc

# Set ownership of audio config files
RUN chown -R ${USER}:${GROUP} /home/${USER}/.config/pulse \
    && chown ${USER}:${GROUP} /home/${USER}/.asoundrc

# Audio is served by WSLg's PulseAudio server (/mnt/wslg/PulseServer); a local
# daemon must never spawn. The pulseaudio package enables its user units by
# preset, and the daemon's O_NOFOLLOW pidfile open collides with WSLg's
# pre-seeded /run/user/1001/pulse/pid symlink -> ELOOP ("Too many levels of
# symbolic links") -> crash-loop until start-limit. Mask the units for all users.
RUN systemctl --global mask pulseaudio.service pulseaudio.socket

# Add audio/video environment variables for WSLg
RUN echo 'export CLUTTER_BACKEND=wayland' >> /home/${USER}/.bashrc \
    && echo 'export DISPLAY=:0' >> /home/${USER}/.bashrc \
    && echo 'export LIBGL_ALWAYS_INDIRECT=1' >> /home/${USER}/.bashrc \
    && echo 'export PULSE_SERVER=unix:/mnt/wslg/PulseServer' >> /home/${USER}/.bashrc \
    && echo 'export QT_QPA_PLATFORM=wayland' >> /home/${USER}/.bashrc \
    && echo 'export WAYLAND_DISPLAY=wayland-0' >> /home/${USER}/.bashrc \
    && echo 'export XDG_RUNTIME_DIR=/run/user/1001' >> /home/${USER}/.bashrc \
    && echo 'export ENABLE_LSP_TOOLS=1' >> /home/${USER}/.bashrc


#  ██  ██      ██     ██ ███████ ██          ██    ██ ██████  ███    ██ ██   ██ ██ ████████
# ████████     ██     ██ ██      ██          ██    ██ ██   ██ ████   ██ ██  ██  ██    ██
#  ██  ██      ██  █  ██ ███████ ██          ██    ██ ██████  ██ ██  ██ █████   ██    ██
# ████████     ██ ███ ██      ██ ██           ██  ██  ██      ██  ██ ██ ██  ██  ██    ██
#  ██  ██       ███ ███  ███████ ███████       ████   ██      ██   ████ ██   ██ ██    ██

# Install wsl-vpnkit to provide network connectivity when connected to VPNs on Windows host
# See: https://github.com/sakai135/wsl-vpnkit
WORKDIR /usr/local/wsl-vpnkit
RUN wget -q https://github.com/containers/gvisor-tap-vsock/releases/download/v0.6.1/gvproxy-windows.exe \
    && wget -q https://github.com/containers/gvisor-tap-vsock/releases/download/v0.6.1/vm \
    && chmod +x ./gvproxy-windows.exe ./vm \
    && mv ./vm ./wsl-vm \
    && mv ./gvproxy-windows.exe ./wsl-gvproxy.exe

# Download wsl-vpnkit script
RUN wget -q https://raw.githubusercontent.com/sakai135/wsl-vpnkit/v0.4.1/wsl-vpnkit -O /usr/local/wsl-vpnkit/wsl-vpnkit \
    && chmod +x /usr/local/wsl-vpnkit/wsl-vpnkit \
    && ln -s /usr/local/wsl-vpnkit/wsl-vpnkit /usr/local/bin/wsl-vpnkit

# Create systemd service for wsl-vpnkit
COPY config/etc/systemd/system/wsl-vpnkit.service /etc/systemd/system/wsl-vpnkit.service
RUN systemctl enable wsl-vpnkit.service

# Clean, ensure no bashrc has dangerous mount lines
# hadolint ignore=SC2015
RUN sed -i '/make-rshared/d' /etc/skel/.bashrc || true \
  && sed -i '/mount[[:space:]]\+\/[[:space:]]*$/d' /etc/skel/.bashrc || true \
  && sed -i '/make-rshared/d' /home/${USER}/.bashrc || true \
  && sed -i '/mount[[:space:]]\+\/[[:space:]]*$/d' /home/${USER}/.bashrc || true

USER ${USER}
WORKDIR /home/${USER}

ARG BUILD_DATE
