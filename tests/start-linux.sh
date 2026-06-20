#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
START_SCRIPT="${ROOT_DIR}/start.sh"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "${actual}" != "${expected}" ]]; then
        printf 'ERROR: %s\n' "${message}" >&2
        diff -u <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") >&2 || true
        exit 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "${haystack}" != *"${needle}"* ]]; then
        fail "${message}"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "${haystack}" == *"${needle}"* ]]; then
        fail "${message}"
    fi
}

create_fake_runner() {
    local runner_home="$1"

    cat >"${runner_home}/config.sh" <<'EOF'
#!/usr/bin/env bash
{
    printf 'config\n'
    for arg in "$@"; do
        printf '%s\n' "${arg}"
    done
    printf 'end\n'
} >>"${RUNNER_TEST_LOG}"
exit 0
EOF

    cat >"${runner_home}/run.sh" <<'EOF'
#!/usr/bin/env bash
printf 'run\n' >>"${RUNNER_TEST_LOG}"
exit 0
EOF

    chmod +x "${runner_home}/config.sh" "${runner_home}/run.sh"
}

run_start() {
    local output_file="$1"
    shift

    env "$@" bash "${START_SCRIPT}" >"${output_file}" 2>&1
}

test_primary_variables() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' RETURN

    create_fake_runner "${tmpdir}"

    local log_file="${tmpdir}/events.log"
    local output_file="${tmpdir}/output.log"
    run_start "${output_file}" \
        RUNNER_HOME="${tmpdir}" \
        RUNNER_TEST_LOG="${log_file}" \
        RUNNER_URL="https://github.com/example/repo/" \
        RUNNER_REGISTRATION_TOKEN="runner-secret-token" \
        RUNNER_NAME="runner-1" \
        RUNNER_LABELS="docker,linux" \
        RUNNER_WORKDIR="_custom" \
        RUNNER_EPHEMERAL="yes"

    local actual
    actual="$(cat "${log_file}")"

    local expected
    expected="$(cat <<'EOF'
config
--unattended
--replace
--url
https://github.com/example/repo
--token
runner-secret-token
--name
runner-1
--work
_custom
--ephemeral
--labels
docker,linux
end
run
config
remove
--unattended
--token
runner-secret-token
end
EOF
)"

    assert_eq "${expected}" "${actual}" "primary variable flow should pass expected runner arguments"
    assert_not_contains "$(cat "${output_file}")" "runner-secret-token" "startup logs must not print the registration token"
}

test_legacy_variables() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' RETURN

    create_fake_runner "${tmpdir}"

    local log_file="${tmpdir}/events.log"
    local output_file="${tmpdir}/output.log"
    run_start "${output_file}" \
        RUNNER_HOME="${tmpdir}" \
        RUNNER_TEST_LOG="${log_file}" \
        REPO="example/legacy" \
        TOKEN="legacy-runner-token"

    local actual
    actual="$(cat "${log_file}")"

    local expected
    expected="$(cat <<'EOF'
config
--unattended
--replace
--url
https://github.com/example/legacy
--token
legacy-runner-token
--name
EOF
)"

    assert_contains "${actual}" "${expected}" "legacy REPO/TOKEN variables should resolve runner URL and token"
    assert_contains "${actual}" $'\n--work\n_work\n' "legacy flow should use the default work directory"
    assert_not_contains "${actual}" "--ephemeral" "legacy flow should not enable ephemeral mode by default"
    assert_not_contains "$(cat "${output_file}")" "legacy-runner-token" "startup logs must not print legacy token"
}

test_pat_rejected() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' RETURN

    create_fake_runner "${tmpdir}"

    local output_file="${tmpdir}/output.log"
    set +e
    run_start "${output_file}" \
        RUNNER_HOME="${tmpdir}" \
        RUNNER_TEST_LOG="${tmpdir}/events.log" \
        RUNNER_URL="https://github.com/example/repo" \
        RUNNER_REGISTRATION_TOKEN="ghp_secret"
    local status=$?
    set -e

    if [[ "${status}" -eq 0 ]]; then
        fail "PAT-like token should be rejected"
    fi

    local output
    output="$(cat "${output_file}")"
    assert_contains "${output}" "not a PAT or GitHub API token" "PAT rejection should explain the token type problem"
    assert_not_contains "${output}" "ghp_secret" "PAT rejection logs must not print the rejected token"
}

test_primary_variables
test_legacy_variables
test_pat_rejected

printf 'Linux startup script tests passed.\n'
