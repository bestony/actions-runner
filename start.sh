#!/usr/bin/env bash

set -Eeuo pipefail

RUNNER_HOME="${RUNNER_HOME:-/home/docker/actions-runner}"

log() {
    local level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*" >&2
}

fail() {
    log "ERROR" "$*"
    exit 1
}

is_placeholder_value() {
    local value="${1:-}"

    case "${value}" in
        "" | [Nn][Uu][Ll][Ll] | [Nn][Oo][Nn][Ee] | [Uu][Nn][Dd][Ee][Ff][Ii][Nn][Ee][Dd] | \
            [Cc][Hh][Aa][Nn][Gg][Ee][Mm][Ee] | [Cc][Hh][Aa][Nn][Gg][Ee]-[Mm][Ee] | \
            [Tt][Oo][Dd][Oo] | owner/repo | OWNER/REPO | *"<"*">"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_runner_url() {
    if [[ -n "${RUNNER_URL:-}" ]]; then
        if is_placeholder_value "${RUNNER_URL}"; then
            fail "RUNNER_URL must be the GitHub URL from the official config.sh --url command, for example https://github.com/owner/repo."
        fi

        if [[ ! "${RUNNER_URL}" =~ ^https://[^[:space:]]+$ ]]; then
            fail "RUNNER_URL must be an https:// URL."
        fi

        printf '%s\n' "${RUNNER_URL%/}"
        return
    fi

    if [[ -z "${REPO:-}" ]]; then
        fail "Set RUNNER_URL or REPO. RUNNER_URL is preferred and should match the official config.sh --url value."
    fi

    if is_placeholder_value "${REPO}"; then
        fail "REPO must be an owner/repo value, or set RUNNER_URL to the full GitHub URL."
    fi

    if [[ "${REPO}" == http://* || "${REPO}" == https://* ]]; then
        fail "REPO must use owner/repo format. Use RUNNER_URL for a full URL."
    fi

    if [[ ! "${REPO}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
        fail "REPO must be in owner/repo format, or set RUNNER_URL to the full GitHub URL."
    fi

    printf 'https://github.com/%s\n' "${REPO}"
}

resolve_registration_token() {
    local token

    if [[ -n "${RUNNER_REGISTRATION_TOKEN:-}" ]]; then
        token="${RUNNER_REGISTRATION_TOKEN}"
    elif [[ -n "${TOKEN:-}" ]]; then
        token="${TOKEN}"
    else
        fail "Set RUNNER_REGISTRATION_TOKEN to the token from the official config.sh --token command."
    fi

    if is_placeholder_value "${token}"; then
        fail "RUNNER_REGISTRATION_TOKEN/TOKEN must be a valid self-hosted runner registration token."
    fi

    if [[ "${token}" =~ ^(ghp_|github_pat_|gho_|ghu_|ghs_|ghr_) ]]; then
        fail "RUNNER_REGISTRATION_TOKEN/TOKEN must be a self-hosted runner registration token, not a PAT or GitHub API token."
    fi

    printf '%s\n' "${token}"
}

normalize_bool() {
    local value="${1:-false}"

    case "${value}" in
        true | TRUE | True | 1 | yes | YES | Yes)
            printf 'true\n'
            ;;
        false | FALSE | False | 0 | no | NO | No | "")
            printf 'false\n'
            ;;
        *)
            fail "RUNNER_EPHEMERAL must be one of: true, false, 1, 0, yes, no."
            ;;
    esac
}

RUNNER_URL_VALUE="$(resolve_runner_url)"
REGISTRATION_TOKEN="$(resolve_registration_token)"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_EPHEMERAL_VALUE="$(normalize_bool "${RUNNER_EPHEMERAL:-false}")"

log "INFO" "Configuring GitHub Actions runner."
log "INFO" "Runner URL: ${RUNNER_URL_VALUE}"
log "INFO" "Runner name: ${RUNNER_NAME}"
log "INFO" "Runner work directory: ${RUNNER_WORKDIR}"
log "INFO" "Runner ephemeral: ${RUNNER_EPHEMERAL_VALUE}"
if [[ -n "${RUNNER_LABELS:-}" ]]; then
    log "INFO" "Runner labels: ${RUNNER_LABELS}"
fi

cd "${RUNNER_HOME}" || exit 1

config_args=(
    --unattended
    --replace
    --url "${RUNNER_URL_VALUE}"
    --token "${REGISTRATION_TOKEN}"
    --name "${RUNNER_NAME}"
    --work "${RUNNER_WORKDIR}"
)

if [[ "${RUNNER_EPHEMERAL_VALUE}" == "true" ]]; then
    config_args+=(--ephemeral)
fi

if [[ -n "${RUNNER_LABELS:-}" ]]; then
    config_args+=(--labels "${RUNNER_LABELS}")
fi

log "INFO" "Registering runner."
./config.sh "${config_args[@]}"

cleanup() {
    local exit_code=$?
    trap - INT TERM EXIT

    log "INFO" "Removing runner registration."
    if ! ./config.sh remove --unattended --token "${REGISTRATION_TOKEN}"; then
        log "WARN" "Runner cleanup failed. The runner may already be removed if ephemeral, or may need to be removed manually in GitHub settings."
    fi

    exit "${exit_code}"
}

trap cleanup INT TERM EXIT

log "INFO" "Starting runner process."
./run.sh
