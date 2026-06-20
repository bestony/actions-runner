#!/usr/bin/env bash

set -Eeuo pipefail

RUNNER_HOME="/home/docker/actions-runner"

log() {
    local level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*"
}

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        log "ERROR" "Required environment variable ${name} is not set."
        exit 1
    fi
}

require_env "REPO"
require_env "TOKEN"

if [[ "${TOKEN}" == "null" ]]; then
    log "ERROR" "TOKEN must be a valid self-hosted runner registration token."
    exit 1
fi

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"

log "INFO" "Configuring GitHub Actions runner."
log "INFO" "Repository: ${REPO}"
log "INFO" "Runner name: ${RUNNER_NAME}"
log "INFO" "Runner work directory: ${RUNNER_WORKDIR}"
if [[ -n "${RUNNER_LABELS:-}" ]]; then
    log "INFO" "Runner labels: ${RUNNER_LABELS}"
fi

cd "${RUNNER_HOME}" || exit 1

config_args=(
    --unattended
    --replace
    --url "https://github.com/${REPO}"
    --token "${TOKEN}"
    --name "${RUNNER_NAME}"
    --work "${RUNNER_WORKDIR}"
)

if [[ -n "${RUNNER_LABELS:-}" ]]; then
    config_args+=(--labels "${RUNNER_LABELS}")
fi

log "INFO" "Registering runner."
./config.sh "${config_args[@]}"

cleanup() {
    local exit_code=$?
    trap - INT TERM EXIT

    log "INFO" "Removing runner registration."
    if ! ./config.sh remove --unattended --token "${TOKEN}"; then
        log "WARN" "Runner cleanup failed. The runner may need to be removed manually in GitHub settings."
    fi

    exit "${exit_code}"
}

trap cleanup INT TERM EXIT

log "INFO" "Starting runner process."
./run.sh
