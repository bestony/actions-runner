# Security Policy

## Reporting a Vulnerability

Please report security issues privately by opening a GitHub security advisory for this repository or by contacting the repository maintainer through the profile contact methods.

Do not open a public issue for:

- Leaked tokens, credentials, or private configuration
- Docker socket escape or host compromise findings
- Vulnerabilities in the image build chain
- Runner registration or cleanup flaws that expose repository access

Include the affected image tag or commit SHA, reproduction steps, expected impact, and any relevant logs with secrets removed.

## Secret Exposure

If a token or credential is exposed, including this project's `TOKEN` registration token:

1. Revoke or rotate the token immediately.
2. Remove any stale self-hosted runners from repository or organization settings.
3. Review workflow logs and host Docker activity for unexpected jobs.
4. File a private security report if the exposure was caused by this image or startup script.

## Runner Trust Boundary

This image is intended for trusted repositories and workflows. A self-hosted runner executes workflow code with access to the container environment and any mounted resources.

The sample Compose file mounts `/var/run/docker.sock`. This gives jobs access to the host Docker daemon and should be treated as highly privileged. Do not use this configuration for untrusted pull requests or repositories where arbitrary contributors can modify workflows.
