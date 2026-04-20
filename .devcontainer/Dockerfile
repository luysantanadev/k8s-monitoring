FROM mcr.microsoft.com/devcontainers/base:noble

ENV DEBIAN_FRONTEND=noninteractive

# Retry configuration so transient network failures don't abort the build
RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries

# ── Base packages + Python 3 ─────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    xz-utils \
    python3 \
    python3-pip \
    python3-venv \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

# ── .NET 10 SDK (official Ubuntu 24.04 feed — no Microsoft repo needed) ───────
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    dotnet-sdk-10.0 \
    && rm -rf /var/lib/apt/lists/* \
    && dotnet --version

# ── nvm + Node.js LTS (installed globally) ────────────────────────────────────
ENV NVM_DIR=/usr/local/share/nvm
RUN mkdir -p "${NVM_DIR}" \
    && curl --retry 5 --retry-delay 3 -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install --lts \
    && nvm alias default lts/* \
    && nvm cache clear \
    && NODE_PATH="$(find ${NVM_DIR}/versions/node -maxdepth 1 -mindepth 1 | head -1)/bin" \
    && ln -sf "${NODE_PATH}/node"  /usr/local/bin/node \
    && ln -sf "${NODE_PATH}/npm"   /usr/local/bin/npm \
    && ln -sf "${NODE_PATH}/npx"   /usr/local/bin/npx \
    && node --version && npm --version

# ── kubectl ───────────────────────────────────────────────────────────────────
RUN curl --retry 5 --retry-delay 3 -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' \
    > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update && apt-get install -y --no-install-recommends kubectl \
    && rm -rf /var/lib/apt/lists/*

# ── Helm 4 (official install script — resilient to transient DNS failures) ────
RUN curl --retry 5 --retry-delay 3 -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 \
    | bash

# ── Docker CLI (docker-outside-of-docker — needed for k3d communication) ─────
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl --retry 5 --retry-delay 3 -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Allow the vscode user to use Docker via the host socket
RUN groupadd -f docker && usermod -aG docker vscode

# ── nvm shell integration for interactive use ─────────────────────────────────
RUN echo 'export NVM_DIR="/usr/local/share/nvm"' >> /home/vscode/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> /home/vscode/.bashrc
