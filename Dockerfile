FROM ubuntu:24.04

ARG RUNNER_VERSION="2.335.1"
ARG TARGETARCH
ARG TARGETVARIANT
ARG RUNNER_X64_SHA256="4ef2f25285f0ae4477f1fe1e346db76d2f3ebf03824e2ddd1973a2819bf6c8cf"
ARG RUNNER_ARM64_SHA256="6d1e85bfd1a506a8b17c1f1b9b57dba458ffed90898799aaa9f599520b0d9207"
ARG RUNNER_ARM_SHA256="d9810476ceebb6739913ed16afd5c61664e53312a444ee5226e9010a4219a864"
ARG NODE_VERSION="22.13.0"
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="Dockerized GitHub Actions Runner" \
      org.opencontainers.image.description="Ubuntu-based self-hosted GitHub Actions runner for Docker workloads." \
      org.opencontainers.image.source="https://github.com/bestony/actions-runner" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${RUNNER_VERSION}"

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libasound2t64 \
        libatk-bridge2.0-0t64 \
        libatk1.0-0t64 \
        libatspi2.0-0t64 \
        libcairo2 \
        libcups2t64 \
        libdbus-1-3 \
        libdrm2 \
        libffi-dev \
        libgbm1 \
        libglib2.0-0t64 \
        libicu-dev \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libssl-dev \
        libx11-6 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        libxcb1 \
        pulseaudio \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        unzip \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl --fail --silent --show-error --location \
        --output /etc/apt/keyrings/docker.asc \
        https://download.docker.com/linux/ubuntu/gpg \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-buildx-plugin \
        docker-ce-cli \
        docker-compose-plugin \
    && useradd --create-home docker \
    && mkdir -p /home/docker/actions-runner \
    && case "${TARGETARCH}" in \
        amd64) runner_arch="x64"; runner_sha256="${RUNNER_X64_SHA256}" ;; \
        arm64) runner_arch="arm64"; runner_sha256="${RUNNER_ARM64_SHA256}" ;; \
        arm) \
            if [ "${TARGETVARIANT}" != "v7" ]; then \
                echo "Unsupported target architecture variant: linux/arm/${TARGETVARIANT}. Only linux/arm/v7 is supported." >&2; \
                exit 1; \
            fi; \
            runner_arch="arm"; runner_sha256="${RUNNER_ARM_SHA256}" ;; \
        *) echo "Unsupported target architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl --fail --silent --show-error --location \
        --output /tmp/actions-runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${runner_arch}-${RUNNER_VERSION}.tar.gz" \
    && echo "${runner_sha256}  /tmp/actions-runner.tar.gz" | sha256sum --check --strict \
    && tar --extract --gzip --file /tmp/actions-runner.tar.gz --directory /home/docker/actions-runner \
    && rm /tmp/actions-runner.tar.gz \
    && /home/docker/actions-runner/bin/installdependencies.sh \
    && chown -R docker:docker /home/docker \
    && rm -rf /var/lib/apt/lists/*

# Workaround for github-actions-cache-server: it reads ACTIONS_RESULTS_ORL
# while GitHub's runner binary uses ACTIONS_RESULTS_URL. This binary patch
# keeps compatibility with that cache server and should be revisited on runner
# upgrades.
RUN sed -i 's/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x55\x00\x52\x00\x4C\x00/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x4F\x00\x52\x00\x4C\x00/g' /home/docker/actions-runner/bin/Runner.Worker.dll

COPY --chown=docker:docker start.sh /home/docker/start.sh
RUN chmod +x /home/docker/start.sh

USER docker
WORKDIR /home/docker

ENV NODE_VERSION="${NODE_VERSION}" \
    NVM_DIR="/home/docker/.nvm"

RUN curl --fail --silent --show-error --location https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && npm install --global yarn

ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}"

ENTRYPOINT ["./start.sh"]
