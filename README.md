# actions-runner

Dockerized GitHub Actions self-hosted runner for repositories that need Docker-based jobs. The image registers a runner when the container starts and removes that runner registration during normal container shutdown.

## Quick Start

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

Optional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `ACTIONS_RESULTS_URL` | `http://cache:3000/` | Cache server URL used by the bundled cache workaround. |
| `RUNNER_NAME` | Container hostname | GitHub runner name. |
| `RUNNER_LABELS` | Empty | Comma-separated custom labels passed to `config.sh --labels`. |
| `RUNNER_WORKDIR` | `_work` | Runner working directory. |
| `RUNNER_EPHEMERAL` | `false` | Set to `true` to pass `--ephemeral` to `config.sh`. |
| `RUNNER_REPLICAS` | `4` | Compose replica count for the sample deployment. |
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
| `NODE_VERSION` | `22.13.0` | Node.js version installed with nvm. |

Example build:

```bash
docker build \
  --build-arg RUNNER_VERSION=2.335.1 \
  -t actions-runner:test .
```

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

Self-hosted runners execute code from your workflows. GitHub recommends using self-hosted runners only with private repositories, because forks of public repositories can run dangerous code on the runner machine through pull requests. Be cautious with private or internal repositories that allow fork-based pull requests too.

Avoid attaching highly privileged tokens, cloud credentials, or production secrets to repositories that run untrusted pull requests.

The startup script does not print the registration token. It only logs non-sensitive runner configuration and cleanup status.

## Cache Server

The sample Compose file includes `ghcr.io/falcondev-oss/github-actions-cache-server`. The image patches `Runner.Worker.dll` from `ACTIONS_RESULTS_URL` to `ACTIONS_RESULTS_ORL` to match that cache server's expected environment variable name. This is a compatibility workaround and should be checked whenever `RUNNER_VERSION` changes.

To disable the cache service, remove the `cache` service from `docker-compose.yml` and unset `ACTIONS_RESULTS_URL`.

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
| `latest` | Current image built from the default branch. |
| `<runner-version>` | Current image for the configured GitHub Actions runner version, for example `2.335.1`. |
| `<git-sha>` | Image built from a specific commit. |
| `v*` | Release tag builds, when pushed. |

## Local Verification

Run the same checks used by CI:

```bash
shellcheck start.sh
docker compose config
docker build --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test .
docker build --platform linux/amd64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-amd64 .
docker build --platform linux/arm64 --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test-arm64 .
```

## Troubleshooting

`RUNNER_REGISTRATION_TOKEN/TOKEN must be a valid self-hosted runner registration token`: check that `.env` contains the registration token from GitHub's self-hosted runner setup command, not a personal access token, GitHub API token, or placeholder value.

`Set RUNNER_URL or REPO`: configure `RUNNER_URL=https://github.com/<owner>/<repo>` or the legacy `REPO=<owner>/<repo>` value. `RUNNER_URL` must match the scope used when the registration token was generated.

Runner registration fails with an authentication error: registration tokens expire. Generate a fresh token from GitHub repository or organization runner settings and restart the container.

`POST https://api.github.com/actions/runner-registration 404`: this usually means the registration token expired, the token scope does not match `RUNNER_URL`, the image is old enough to be incompatible with GitHub's current runner registration flow, or the value passed as the token is the wrong token type.

`docker compose config` fails on resource fields: memory values must include units such as `1024M` or `1G`; CPU values are quoted strings in this repository's sample file.

Runner remains visible in GitHub after container shutdown: cleanup may fail if the container is force-killed, loses network access, or the registration token has expired. Remove stale runners from the repository or organization self-hosted runner settings.

DockerHub tag is missing or still points to an older image: check whether the Docker CI workflow for the default branch has completed successfully. Until the workflow publishes, use a commit SHA tag that exists or build locally.

Container logs should never contain your registration token. If a token appears in logs, rotate it immediately and open a security report.

## References

- [GitHub Actions self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Adding self-hosted runners](https://docs.github.com/actions/hosting-your-own-runners/adding-self-hosted-runners)
- [Removing self-hosted runners](https://docs.github.com/actions/hosting-your-own-runners/removing-self-hosted-runners)
- [Self-hosted runners reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [source blog](https://baccini-al.medium.com/creating-a-dockerfile-for-dynamically-creating-github-actions-self-hosted-runners-5994cc08b9fb)
- [testdriven.io](https://testdriven.io/blog/github-actions-docker/)
