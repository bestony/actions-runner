# Contributing

Thank you for improving this Dockerized GitHub Actions runner image.

## Development Setup

Install the tools used by CI:

- Docker with Compose support
- ShellCheck
- Git

Run local verification before opening a pull request:

```bash
shellcheck start.sh
docker compose config
docker build --build-arg RUNNER_VERSION=2.335.1 -t actions-runner:test .
```

## Pull Requests

Keep pull requests focused on one reversible change. Include enough context for reviewers to understand runner behavior, Docker image impact, and security tradeoffs.

For changes that affect registration, cleanup, permissions, or Docker socket access, describe the failure mode you tested and confirm that logs do not expose `TOKEN`.

## Commit Messages

Use Conventional Commits:

```text
feat(runner): add custom label support
fix(compose): use string memory reservation
docs(security): document Docker socket risk
```

## Runner Version Updates

When changing `RUNNER_VERSION`:

1. Update the default `RUNNER_VERSION` in `Dockerfile`, `.github/workflows/docker-ci.yml`, and documentation.
2. Update `RUNNER_X64_SHA256` and `RUNNER_ARM64_SHA256` to match the new runner tarballs.
3. Rebuild the image locally.
4. Check whether the cache-server `Runner.Worker.dll` patch still applies.
