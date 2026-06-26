# actions-runner

Dockerized GitHub Actions self-hosted runner for repositories that need Docker-based jobs. The image registers a runner when the container starts and removes that runner registration during normal container shutdown.

## Linux Quick Start

`latest` and `2.335.1` are multi-OS tags. Docker selects the Linux image on Linux Docker hosts and the Windows image on Windows Docker hosts when both platform images are present in the manifest.

Create the external network used by the sample Compose file:

```bash
docker network create runner
```

Create a local `.env` from the example and fill in the runner URL and registration token from GitHub's generated `config.sh` command:

```bash
cp .env.example .env
```

Run a single runner with the prebuilt Docker image:

```bash
docker run -d \
  --name actions-runner \
  --restart unless-stopped \
  --group-add "$(stat -c '%g' /var/run/docker.sock)" \
  -e RUNNER_URL=https://github.com/<owner>/<repo> \
  -e RUNNER_REGISTRATION_TOKEN=<token-from-config-sh-command> \
  -v /var/run/docker.sock:/var/run/docker.sock \
  bestony/actions-runner:latest
```

Start the cache service and runner:

```bash
docker compose up -d
```

Use `bestony/actions-runner:2.335.1` instead of `latest` when you want to pin the image to the current runner version. Production deployments should pin to a version tag instead of `latest`. The default Compose file starts multiple runner replicas and mounts the host Docker socket so workflows can build or run containers.

Linux runners support Docker by using the host Docker daemon through `/var/run/docker.sock`. The image includes Docker client tooling only: `docker`, Buildx, and the Docker Compose plugin. It does not install or start `dockerd` inside the runner container.

For Compose deployments, set `DOCKER_GID` in `.env` to the host socket group id when it differs from the default:

```bash
DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"
```

## Windows Quick Start

Windows runner containers require a Windows Docker host running Windows containers. They cannot run on a Linux Docker host. The default Windows image is based on `mcr.microsoft.com/windows/servercore:ltsc2022`, so the host must be compatible with Windows Server 2022 containers. Use `--isolation=hyperv` instead of `--isolation=process` when your host/container version combination requires Hyper-V isolation.

Run a single Windows runner:

```powershell
docker run -d `
  --name actions-runner `
  --restart unless-stopped `
  --isolation=process `
  -e RUNNER_URL=https://github.com/<owner>/<repo> `
  -e RUNNER_REGISTRATION_TOKEN=<token-from-config-cmd-command> `
  --mount type=npipe,source=\\.\pipe\docker_engine,target=\\.\pipe\docker_engine `
  bestony/actions-runner:latest
```

Or use the Windows Compose example:

```powershell
docker compose -f docker-compose.windows.yml up -d
```

The Windows image registers and runs a self-hosted runner only. It does not include the Linux cache-server binary patch, does not mount `/var/run/docker.sock`, and does not preinstall large toolchains such as Visual Studio Build Tools. Windows Docker workflows that need Docker access should use the Windows Docker named pipe mount shown above.

## Platform Support

| OS | Docker platform | GitHub runner asset | Support |
| --- | --- | --- | --- |
| Linux | `linux/amd64` | `actions-runner-linux-x64` | Stable |
| Linux | `linux/arm64` | `actions-runner-linux-arm64` | Stable |
| Linux | `linux/arm/v7` | `actions-runner-linux-arm` | Stable |
| Windows Server Core LTSC 2022 | `windows/amd64` | `actions-runner-win-x64` | Stable |
| Windows Server Core LTSC 2022 | `windows/arm64` | `actions-runner-win-arm64` | Experimental |

Windows ARM64 Dockerfile and CI paths exist, but publishing is best-effort. If the Windows Server Core base image or the GitHub-hosted Windows build environment does not support `windows/arm64`, CI skips that platform in the unified manifest.

## Configuration

Required variables:

| Variable | Description |
| --- | --- |
| `RUNNER_URL` | GitHub runner destination URL from the official `config.sh --url` command, for example `https://github.com/owner/repo` or `https://github.com/org`. Preferred over `REPO`. |
| `RUNNER_REGISTRATION_TOKEN` | Time-limited registration token from the official `config.sh --token` command. Preferred over `TOKEN`. |

Backward-compatible aliases:

| Variable | Description |
| --- | --- |
| `REPO` | Repository in `owner/repo` format. Used only when `RUNNER_URL` is empty. |
| `TOKEN` | Registration token alias. Used only when `RUNNER_REGISTRATION_TOKEN` is empty. |

Official command mapping:

| GitHub command argument | Docker environment variable |
| --- | --- |
| `./config.sh --url https://github.com/<owner>/<repo>` | `RUNNER_URL=https://github.com/<owner>/<repo>` or `REPO=<owner>/<repo>` |
| `./config.sh --token <registration-token>` | `RUNNER_REGISTRATION_TOKEN=<registration-token>` or legacy `TOKEN=<registration-token>` |
| `.\config.cmd --url https://github.com/<owner>/<repo>` | `RUNNER_URL=https://github.com/<owner>/<repo>` or `REPO=<owner>/<repo>` |
| `.\config.cmd --token <registration-token>` | `RUNNER_REGISTRATION_TOKEN=<registration-token>` or legacy `TOKEN=<registration-token>` |

Optional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `ACTIONS_RESULTS_URL` | `http://cache:3000/` | Cache server URL used by the bundled cache workaround. |
| `RUNNER_NAME` | Container hostname | GitHub runner name. |
| `RUNNER_LABELS` | Empty | Comma-separated custom labels passed to `config.sh --labels`. |
| `RUNNER_WORKDIR` | `_work` | Runner working directory. |
| `RUNNER_EPHEMERAL` | `false` | Set to `true` to pass `--ephemeral` to `config.sh`. |
| `RUNNER_REPLICAS` | `4` | Compose replica count for the sample deployment. |
| `WINDOWS_CONTAINER_ISOLATION` | `process` | Windows Compose isolation mode. Use `hyperv` when host/container version compatibility requires it. |
| `DOCKER_GID` | `998` | Host Docker socket group id used by Linux Compose deployments. Set it with `stat -c '%g' /var/run/docker.sock` when Docker commands fail with socket permission errors. |
| `RUNNER_RESERVED_CPUS` | `0.5` | Compose CPU reservation. |
| `RUNNER_RESERVED_MEMORY` | `1024M` | Compose memory reservation. |
| `RUNNER_LIMIT_CPUS` | `2.0` | Compose CPU limit. |
| `RUNNER_LIMIT_MEMORY` | `4096M` | Compose memory limit. |

Build-time arguments:

| Argument | Default | Description |
| --- | --- | --- |
| `RUNNER_VERSION` | `2.335.1` | GitHub Actions runner version to download. |
| `RUNNER_X64_SHA256` | x64 runner tarball SHA-256 for the default version | Supply the matching checksum when overriding `RUNNER_VERSION`. |
| `RUNNER_ARM64_SHA256` | arm64 runner tarball SHA-256 for the default version | Supply the matching checksum when overriding `RUNNER_VERSION`. |
| `RUNNER_ARM_SHA256` | arm runner tarball SHA-256 for the default version | Supply the matching checksum when overriding `RUNNER_VERSION`. |
| `RUNNER_WIN_X64_SHA256` | Windows x64 runner zip SHA-256 for the default version | Supply the matching checksum when overriding `RUNNER_VERSION`. |
| `RUNNER_WIN_ARM64_SHA256` | Windows arm64 runner zip SHA-256 for the default version | Supply the matching checksum when overriding `RUNNER_VERSION`. |
| `NODE_VERSION` | `22.13.0` | Node.js version installed with nvm. |

Example build:

```bash
docker build \
  --build-arg RUNNER_VERSION=2.335.1 \
  -t actions-runner:test .
```

Linux platform builds:

```bash
docker build --platform linux/amd64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-amd64 .
docker build --platform linux/arm64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-arm64 .
docker build --platform linux/arm/v7 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-arm-v7 .
```

Windows build on a compatible Windows Docker host:

```powershell
docker build `
  -f Dockerfile.windows `
  --build-arg TARGETARCH=amd64 `
  --build-arg RUNNER_VERSION=2.335.1 `
  -t actions-runner:windows-ltsc2022-amd64 `
  .
```

Experimental Windows ARM64 builds use `--platform windows/arm64 --build-arg TARGETARCH=arm64` and only work when the base image and Docker host support that platform.

## Registration Token

`RUNNER_REGISTRATION_TOKEN` is the short-lived self-hosted runner registration token from GitHub, not a personal access token. GitHub generates it for the destination URL in the official setup flow, and the token expires after about one hour.

Generate it from your repository settings:

```text
Repository Settings -> Actions -> Runners -> New self-hosted runner
```

Copy the URL and token from the generated command into `.env`:

```bash
./config.sh --url https://github.com/<owner>/<repo> --token <registration-token>
```

Use:

```dotenv
RUNNER_URL=https://github.com/<owner>/<repo>
RUNNER_REGISTRATION_TOKEN=<registration-token>
```

For organization runners, generate the token from the organization's self-hosted runner settings and use the organization URL, for example `https://github.com/<org>`.

Do not reuse a token copied from old logs, issues, chat messages, or screenshots. Treat any pasted registration token as exposed and generate a fresh one in GitHub before starting the container.

Never commit real `.env` files, tokens, OAuth credentials, or database connection strings.

## Security Notes

Mounting `/var/run/docker.sock` gives workflows broad control over the host Docker daemon. A workflow that can run arbitrary Docker commands through this socket can usually gain host-level control. Only use this image with repositories, workflows, and contributors you trust.

Mounting `\\.\pipe\docker_engine` into a Windows runner container gives workflows broad control over the Windows host Docker daemon. Treat it with the same level of trust as the Linux Docker socket.

Self-hosted runners execute code from your workflows. GitHub recommends using self-hosted runners only with private repositories, because forks of public repositories can run dangerous code on the runner machine through pull requests. Be cautious with private or internal repositories that allow fork-based pull requests too.

Avoid attaching highly privileged tokens, cloud credentials, or production secrets to repositories that run untrusted pull requests.

The startup script does not print the registration token. It only logs non-sensitive runner configuration and cleanup status.

## Cache Server

The Linux sample Compose file includes `ghcr.io/falcondev-oss/github-actions-cache-server`. The Linux image patches `Runner.Worker.dll` from `ACTIONS_RESULTS_URL` to `ACTIONS_RESULTS_ORL` to match that cache server's expected environment variable name. This is a compatibility workaround and should be checked whenever `RUNNER_VERSION` changes.

To disable the cache service, remove the `cache` service from `docker-compose.yml` and unset `ACTIONS_RESULTS_URL`.

The Windows image does not include this cache-server patch. Use GitHub's default cache behavior on Windows unless you build and validate a Windows-specific cache integration.

## Scaling

The sample uses Compose replicas. Keep `RUNNER_NAME` empty when running multiple replicas so each container uses its hostname as a unique runner name. If you set a fixed `RUNNER_NAME` with more than one replica, runners will replace each other's registration.

`RUNNER_EPHEMERAL=true` configures an ephemeral runner with `config.sh --ephemeral`. Ephemeral runners are better suited to one-shot containers and autoscaling systems because GitHub assigns only one job to an ephemeral runner. Keep `RUNNER_EPHEMERAL=false` for long-lived Compose replicas unless your deployment starts fresh containers for jobs and preserves runner logs externally.

Resource limits in `docker-compose.yml` are examples. Tune them to match your job workload and host capacity.

## Cleanup

During normal shutdown, the container runs `config.sh remove --unattended`. GitHub's official remove flow uses a separate, time-limited remove token. This image attempts cleanup with the registration token it already has, so cleanup may fail after the token expires, if the container is force-killed, or if network access is unavailable.

If cleanup fails and the runner remains visible in GitHub, remove it from the repository or organization runner settings. GitHub automatically removes offline persistent runners after a longer stale period and offline ephemeral runners sooner, but force removal keeps the runner list accurate.

## Release Tags

Published images use these tags:

| Tag | Meaning |
| --- | --- |
| `latest` | Multi-OS manifest for the current image built from the default branch. |
| `<runner-version>` | Multi-OS manifest for the configured GitHub Actions runner version, for example `2.335.1`. |
| `<git-sha>` | Multi-OS manifest built from a specific commit. |
| `v*` | Multi-OS release tag manifest, when pushed. |
| `<runner-version>-linux-amd64` | Linux platform image used as a manifest source. |
| `<runner-version>-linux-arm64` | Linux platform image used as a manifest source. |
| `<runner-version>-linux-arm-v7` | Linux platform image used as a manifest source. |
| `<runner-version>-windows-ltsc2022-amd64` | Windows platform image used as a manifest source. |
| `<runner-version>-windows-ltsc2022-arm64` | Experimental Windows ARM64 platform image, published only when the build environment supports it. |

The unified manifest includes Linux amd64, Linux arm64, Linux arm/v7, and Windows amd64 when those platform builds succeed. Windows ARM64 is included only when the experimental build succeeds.

## Local Verification

Run the same checks used by CI:

```bash
shellcheck start.sh
bash tests/start-linux.sh
docker compose config
docker build --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test .
docker run --rm --entrypoint docker actions-runner:test --version
docker run --rm --entrypoint docker actions-runner:test compose version
docker build --platform linux/amd64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-amd64 .
docker build --platform linux/arm64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-arm64 .
docker build --platform linux/arm/v7 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-arm-v7 .
pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content .\start.ps1 -Raw))'
```

On a compatible Windows Docker host:

```powershell
docker compose -f docker-compose.windows.yml config
docker build -f Dockerfile.windows --build-arg TARGETARCH=amd64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-windows-amd64 .
docker build -f Dockerfile.windows --platform windows/arm64 --build-arg TARGETARCH=arm64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-windows-arm64 .
```

The Windows ARM64 build is experimental; a base-image or Docker-host platform failure should be recorded as an environment limitation rather than treated as a Windows x64 release blocker.

## Troubleshooting

`RUNNER_REGISTRATION_TOKEN/TOKEN must be a valid self-hosted runner registration token`: check that `.env` contains the registration token from GitHub's self-hosted runner setup command, not a personal access token, GitHub API token, or placeholder value.

`Set RUNNER_URL or REPO`: configure `RUNNER_URL=https://github.com/<owner>/<repo>` or the legacy `REPO=<owner>/<repo>` value. `RUNNER_URL` must match the scope used when the registration token was generated.

Runner registration fails with an authentication error: registration tokens expire. Generate a fresh token from GitHub repository or organization runner settings and restart the container.

`POST https://api.github.com/actions/runner-registration 404`: this usually means the registration token expired, the token scope does not match `RUNNER_URL`, the image is old enough to be incompatible with GitHub's current runner registration flow, or the value passed as the token is the wrong token type.

`docker compose config` fails on resource fields: memory values must include units such as `1024M` or `1G`; CPU values are quoted strings in this repository's sample file.

Docker commands fail with `permission denied` on `/var/run/docker.sock`: set `DOCKER_GID` in `.env` to the host socket group id with `stat -c '%g' /var/run/docker.sock`, then recreate the runner container. For single-container `docker run`, pass `--group-add "$(stat -c '%g' /var/run/docker.sock)"`.

Runner remains visible in GitHub after container shutdown: cleanup may fail if the container is force-killed, loses network access, or the registration token has expired. Remove stale runners from the repository or organization self-hosted runner settings.

DockerHub tag is missing or still points to an older image: check whether the Docker CI workflow for the default branch has completed successfully. Until the workflow publishes, use a commit SHA tag that exists or build locally.

Windows container fails to start on a Linux host: Windows containers require a Windows Docker host in Windows containers mode. Use the Linux image on Linux hosts.

Windows container fails with an OS version compatibility error: use a Windows host compatible with `servercore:ltsc2022`, switch to Hyper-V isolation if your environment supports it, or build a matching Windows base-image variant.

Container logs should never contain your registration token. If a token appears in logs, rotate it immediately and open a security report.

## References

- [GitHub Actions self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Adding self-hosted runners](https://docs.github.com/actions/hosting-your-own-runners/adding-self-hosted-runners)
- [Removing self-hosted runners](https://docs.github.com/actions/hosting-your-own-runners/removing-self-hosted-runners)
- [Self-hosted runners reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [source blog](https://baccini-al.medium.com/creating-a-dockerfile-for-dynamically-creating-github-actions-self-hosted-runners-5994cc08b9fb)
- [testdriven.io](https://testdriven.io/blog/github-actions-docker/)
