# actions-runner

Dockerized GitHub Actions self-hosted runner for repositories that need Docker-based jobs. The image registers a runner when the container starts and removes that runner registration during normal container shutdown.

## Quick Start

Create the external network used by the sample Compose file:

```bash
docker network create runner
```

Create a local `.env` from the example and fill in your repository and self-hosted runner registration token:

```bash
cp .env.example .env
```

Run a single runner with the prebuilt Docker image:

```bash
docker run -d \
  --name actions-runner \
  --restart unless-stopped \
  -e REPO=<owner>/<repo> \
  -e TOKEN=<your-github-runner-registration-token> \
  -v /var/run/docker.sock:/var/run/docker.sock \
  bestony/actions-runner:latest
```

Start the cache service and runner:

```bash
docker compose up -d
```

Use `bestony/actions-runner:2.335.1` instead of `latest` when you want to pin the image to the current runner version. The default Compose file starts multiple runner replicas and mounts the host Docker socket so workflows can build or run containers.

## Configuration

Required variables:

| Variable | Description |
| --- | --- |
| `REPO` | GitHub repository in `owner/repo` format. |
| `TOKEN` | GitHub self-hosted runner registration token for `REPO`. |

Optional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `ACTIONS_RESULTS_URL` | `http://cache:3000/` | Cache server URL used by the bundled cache workaround. |
| `RUNNER_NAME` | Container hostname | GitHub runner name. |
| `RUNNER_LABELS` | Empty | Comma-separated custom labels passed to `config.sh --labels`. |
| `RUNNER_WORKDIR` | `_work` | Runner working directory. |
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

`TOKEN` is the short-lived self-hosted runner registration token from GitHub, not a personal access token. Generate it from your repository settings:

```text
Repository Settings -> Actions -> Runners -> New self-hosted runner
```

Copy the token from the generated `config.sh --token ...` command into `.env` as `TOKEN`. Registration tokens expire, so start the container soon after generating the token. For organization runners, generate the token from the organization's self-hosted runner settings instead of repository settings.

Never commit real `.env` files, tokens, OAuth credentials, or database connection strings.

## Security Notes

Mounting `/var/run/docker.sock` gives workflows broad control over the host Docker daemon. A workflow that can run arbitrary Docker commands through this socket can usually gain host-level control. Only use this image with repositories, workflows, and contributors you trust.

Self-hosted runners execute code from your workflows. Avoid attaching highly privileged tokens, cloud credentials, or production secrets to repositories that run untrusted pull requests.

The startup script does not print the registration token. It only logs non-sensitive runner configuration and cleanup status.

## Cache Server

The sample Compose file includes `ghcr.io/falcondev-oss/github-actions-cache-server`. The image patches `Runner.Worker.dll` from `ACTIONS_RESULTS_URL` to `ACTIONS_RESULTS_ORL` to match that cache server's expected environment variable name. This is a compatibility workaround and should be checked whenever `RUNNER_VERSION` changes.

To disable the cache service, remove the `cache` service from `docker-compose.yml` and unset `ACTIONS_RESULTS_URL`.

## Scaling

The sample uses Compose replicas. Keep `RUNNER_NAME` empty when running multiple replicas so each container uses its hostname as a unique runner name. If you set a fixed `RUNNER_NAME` with more than one replica, runners will replace each other's registration.

Resource limits in `docker-compose.yml` are examples. Tune them to match your job workload and host capacity.

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
```

## Troubleshooting

`TOKEN must be a valid self-hosted runner registration token`: check that `.env` contains the registration token from GitHub's self-hosted runner setup command, not a personal access token or placeholder value.

Runner registration fails with an authentication error: registration tokens expire. Generate a fresh token from GitHub repository or organization runner settings and restart the container.

`docker compose config` fails on resource fields: memory values must include units such as `1024M` or `1G`; CPU values are quoted strings in this repository's sample file.

Runner remains visible in GitHub after container shutdown: cleanup may fail if the container is force-killed or loses network access. Remove stale runners from the repository's self-hosted runner settings.

Container logs should never contain your registration token. If a token appears in logs, rotate it immediately and open a security report.

## References

- [GitHub Actions self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [source blog](https://baccini-al.medium.com/creating-a-dockerfile-for-dynamically-creating-github-actions-self-hosted-runners-5994cc08b9fb)
- [testdriven.io](https://testdriven.io/blog/github-actions-docker/)
