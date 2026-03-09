#!/usr/bin/env bats

load ../test_helper

_remove_test_mock_bin_from_path() {
    local entry
    local filtered=()

    IFS=':' read -r -a _path_entries <<< "${PATH}"
    for entry in "${_path_entries[@]}"; do
        if [[ "$entry" == "${TEST_DIR}/bin" ]]; then
            continue
        fi
        filtered+=("$entry")
    done

    PATH=$(IFS=:; echo "${filtered[*]}")
    export PATH
}

setup() {
    PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    BUILDGIT="${PROJECT_DIR}/buildgit"
    _remove_test_mock_bin_from_path

    if [[ -z "${JENKINS_URL:-}" ]]; then
        echo "JENKINS_URL is not set" >&2
        return 1
    fi
    if [[ -z "${JENKINS_USER_ID:-}" ]]; then
        echo "JENKINS_USER_ID is not set" >&2
        return 1
    fi
    if [[ -z "${JENKINS_API_TOKEN:-}" ]]; then
        echo "JENKINS_API_TOKEN is not set" >&2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is required for integration tests" >&2
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required for integration tests" >&2
        return 1
    fi
    if [[ ! -x "${BUILDGIT}" ]]; then
        echo "buildgit script not found at ${BUILDGIT}" >&2
        return 1
    fi

    THREADS_INTEGRATION_JOB="$(_get_threads_integration_job)"
}

_get_threads_integration_job() {
    local branch="${BRANCH_NAME:-}"

    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="main"
    fi

    echo "buildgit-integration-test-threads/${branch}"
}

_cache_dir() {
    echo "${BATS_FILE_TMPDIR}/threads-integration-cache"
}

_cache_file() {
    local name="$1"
    echo "$(_cache_dir)/${name}"
}

_jenkins_job_api_url() {
    local job_name="$1"
    local top_job="${job_name%%/*}"
    local branch_job="${job_name#*/}"
    local encoded_branch

    encoded_branch=$(printf '%s' "$branch_job" | jq -sRr @uri)
    echo "${JENKINS_URL}/job/${top_job}/job/${encoded_branch}/api/json"
}

_jenkins_build_api_url() {
    local job_name="$1"
    local build_number="$2"
    local top_job="${job_name%%/*}"
    local branch_job="${job_name#*/}"
    local encoded_branch

    encoded_branch=$(printf '%s' "$branch_job" | jq -sRr @uri)
    echo "${JENKINS_URL}/job/${top_job}/job/${encoded_branch}/${build_number}/api/json"
}

_trigger_integration_job_scan() {
    local job_name="$1"
    local top_job="${job_name%%/*}"
    local scan_url="${JENKINS_URL}/job/${top_job}/build?delay=0sec"
    local http_code

    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        -X POST \
        -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
        "$scan_url" 2>/dev/null) || return 1

    [[ "$http_code" == "200" || "$http_code" == "201" || "$http_code" == "302" ]]
}

_wait_for_integration_job_indexed() {
    local job_name="$1"
    local timeout_seconds="${2:-180}"
    local job_api_url
    local deadline=$((SECONDS + timeout_seconds))
    local http_code

    job_api_url=$(_jenkins_job_api_url "$job_name")

    if http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
        "$job_api_url" 2>/dev/null); then
        if [[ "$http_code" == "200" ]]; then
            return 0
        fi
    fi

    _trigger_integration_job_scan "$job_name" >/dev/null 2>&1 || true

    while (( SECONDS < deadline )); do
        if http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
            "$job_api_url" 2>/dev/null); then
            if [[ "$http_code" == "200" ]]; then
                return 0
            fi
        else
            http_code="000"
        fi

        sleep 5
    done

    echo "Integration job branch was not indexed within ${timeout_seconds}s: ${job_name} (${job_api_url})" >&2
    return 1
}

_wait_for_queue_build_number() {
    local queue_url="$1"
    local timeout_seconds="${2:-180}"
    local queue_api_url
    local deadline=$((SECONDS + timeout_seconds))

    if [[ "$queue_url" =~ /queue/item/([0-9]+) ]]; then
        queue_api_url="${JENKINS_URL}/queue/item/${BASH_REMATCH[1]}/api/json"
    else
        queue_api_url="${queue_url%/}/api/json"
    fi

    while (( SECONDS < deadline )); do
        local response
        response=$(curl -sS -f -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$queue_api_url" 2>/dev/null) || response=""

        if [[ -n "$response" ]]; then
            local build_number
            build_number=$(echo "$response" | jq -r '.executable.number // empty' 2>/dev/null)
            if [[ -n "$build_number" ]]; then
                echo "$build_number"
                return 0
            fi

            local cancelled
            cancelled=$(echo "$response" | jq -r '.cancelled // false' 2>/dev/null)
            if [[ "$cancelled" == "true" ]]; then
                echo "Queue item was cancelled" >&2
                return 1
            fi
        fi

        sleep 2
    done

    echo "Timed out waiting for Jenkins queue item to become executable: ${queue_url}" >&2
    return 1
}

_wait_for_specific_build_completion() {
    local job_name="$1"
    local build_number="$2"
    local timeout_seconds="${3:-180}"
    local deadline=$((SECONDS + timeout_seconds))
    local build_api_url

    build_api_url=$(_jenkins_build_api_url "$job_name" "$build_number")

    while (( SECONDS < deadline )); do
        local build_json
        build_json=$(curl -sS -f -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$build_api_url" 2>/dev/null) || build_json=""

        if [[ -n "$build_json" ]]; then
            local building
            building=$(echo "$build_json" | jq -r '.building // false' 2>/dev/null)
            if [[ "$building" == "false" ]]; then
                return 0
            fi
        fi

        sleep 3
    done

    echo "Timed out waiting for build #${build_number} of ${job_name} to complete" >&2
    return 1
}

_record_threads_failure() {
    local message="$1"
    printf '%s\n' "$message" > "$(_cache_file failure.txt)"
    echo "$message" >&2
    return 1
}

_ensure_threads_build_artifacts() {
    mkdir -p "$(_cache_dir)"

    if [[ -f "$(_cache_file ready)" ]]; then
        return 0
    fi
    if [[ -f "$(_cache_file failure.txt)" ]]; then
        cat "$(_cache_file failure.txt)" >&2
        return 1
    fi

    if ! _wait_for_integration_job_indexed "$THREADS_INTEGRATION_JOB" 180; then
        _record_threads_failure "Integration job branch was not indexed within 180s: ${THREADS_INTEGRATION_JOB}"
    fi

    local trigger_output trigger_rc queue_url build_number
    set +e
    trigger_output=$("${BUILDGIT}" --verbose --job "$THREADS_INTEGRATION_JOB" build --no-follow 2>&1)
    trigger_rc=$?
    set -e
    printf '%s\n' "$trigger_output" > "$(_cache_file trigger_output.txt)"

    if [[ $trigger_rc -ne 0 ]]; then
        echo "$trigger_output" >&2
        _record_threads_failure "Failed to trigger integration pipeline job ${THREADS_INTEGRATION_JOB}"
    fi

    queue_url=$(printf '%s\n' "$trigger_output" | sed -n 's/^.*Queue item: //p' | tail -1)
    if [[ -z "$queue_url" ]]; then
        echo "$trigger_output" >&2
        _record_threads_failure "buildgit did not report a Jenkins queue URL for ${THREADS_INTEGRATION_JOB}"
    fi

    if ! build_number=$(_wait_for_queue_build_number "$queue_url" 180); then
        _record_threads_failure "Could not resolve Jenkins build number for ${THREADS_INTEGRATION_JOB}"
    fi
    printf '%s\n' "$build_number" > "$(_cache_file build_number.txt)"

    local monitor_output monitor_rc
    set +e
    monitor_output=$(bash -c "BUILDGIT_FORCE_TTY=1 \"${BUILDGIT}\" --job \"${THREADS_INTEGRATION_JOB}\" --threads status -f --line --once=120 3>&- 2>&1")
    monitor_rc=$?
    set -e
    printf '%s\n' "$monitor_output" > "$(_cache_file monitor_output.txt)"
    printf '%s\n' "$monitor_rc" > "$(_cache_file monitor_exit_code.txt)"

    if [[ $monitor_rc -ne 0 ]]; then
        echo "$monitor_output" >&2
        _record_threads_failure "buildgit --threads monitoring failed for ${THREADS_INTEGRATION_JOB}"
    fi

    if ! _wait_for_specific_build_completion "$THREADS_INTEGRATION_JOB" "$build_number" 180; then
        _record_threads_failure "Integration pipeline build #${build_number} did not complete in time"
    fi

    local snapshot_output snapshot_rc json_output json_rc
    set +e
    snapshot_output=$("${BUILDGIT}" --job "$THREADS_INTEGRATION_JOB" status "$build_number" --all 2>&1)
    snapshot_rc=$?
    json_output=$("${BUILDGIT}" --job "$THREADS_INTEGRATION_JOB" status "$build_number" --json 2>&1)
    json_rc=$?
    set -e
    printf '%s\n' "$snapshot_output" > "$(_cache_file snapshot_output.txt)"
    printf '%s\n' "$snapshot_rc" > "$(_cache_file snapshot_exit_code.txt)"
    printf '%s\n' "$json_output" > "$(_cache_file status.json)"
    printf '%s\n' "$json_rc" > "$(_cache_file json_exit_code.txt)"

    if [[ $snapshot_rc -ne 0 || -z "$snapshot_output" ]]; then
        echo "$snapshot_output" >&2
        _record_threads_failure "Failed to capture full status output for ${THREADS_INTEGRATION_JOB} #${build_number}"
    fi
    if [[ $json_rc -ne 0 || -z "$json_output" ]]; then
        echo "$json_output" >&2
        _record_threads_failure "Failed to capture JSON status for ${THREADS_INTEGRATION_JOB} #${build_number}"
    fi

    touch "$(_cache_file ready)"
}

_extract_agent_for_fragment() {
    local source_file="$1"
    local fragment="$2"

    grep -E "$fragment" "$source_file" | head -1 | sed -E 's/.*\[([^]]+)\].*/\1/' | xargs
}

@test "threads-nested-parallel: monitor output shows simple and nested active branches" {
    _ensure_threads_build_artifacts

    local monitor_file
    monitor_file="$(_cache_file monitor_output.txt)"

    [[ -s "$monitor_file" ]]
    grep -Eq 'Simple Branch \[' "$monitor_file"
    grep -Eq 'Nested Branch->Step (A|B) \[' "$monitor_file"
    grep -Eq 'Default Nested->Step (X|Y) \[' "$monitor_file"
}

@test "threads-nested-parallel: nested branch uses different agent than simple branch" {
    _ensure_threads_build_artifacts

    local monitor_file simple_agent nested_agent
    monitor_file="$(_cache_file monitor_output.txt)"

    simple_agent=$(_extract_agent_for_fragment "$monitor_file" 'Simple Branch \[')
    nested_agent=$(_extract_agent_for_fragment "$monitor_file" 'Nested Branch->Step (A|B) \[')

    [[ -n "$simple_agent" ]]
    [[ -n "$nested_agent" ]]
    [[ "$simple_agent" != "$nested_agent" ]]
}

@test "threads-nested-parallel: snapshot output keeps nested branch structure" {
    _ensure_threads_build_artifacts

    local build_number snapshot_file json_file
    build_number=$(cat "$(_cache_file build_number.txt)")
    snapshot_file="$(_cache_file snapshot_output.txt)"
    json_file="$(_cache_file status.json)"

    [[ "$(cat "$(_cache_file snapshot_exit_code.txt)")" -eq 0 ]]
    [[ "$(cat "$(_cache_file json_exit_code.txt)")" -eq 0 ]]
    [[ "$(jq -r '.build.number // empty' "$json_file")" == "$build_number" ]]
    [[ "$(jq -r '.build.status // empty' "$json_file")" == "SUCCESS" ]]
    grep -Eq 'Stage:   ║1 \[[^]]+\] Simple Branch \([^)]+\)' "$snapshot_file"
    grep -Eq 'Stage:   ║2 \[[^]]+\] Nested Branch->Step A \([^)]+\)' "$snapshot_file"
    grep -Eq 'Stage:   ║2 \[[^]]+\] Nested Branch->Step B \([^)]+\)' "$snapshot_file"
    grep -Eq 'Stage:   ║2 \[[^]]+\] Nested Branch \([^)]+\)' "$snapshot_file"
    grep -Eq 'Stage:   ║3 \[[^]]+\] Default Nested->Step X \([^)]+\)' "$snapshot_file"
    grep -Eq 'Stage:   ║3 \[[^]]+\] Default Nested->Step Y \([^)]+\)' "$snapshot_file"
    grep -Eq 'Stage:   ║3 \[[^]]+\] Default Nested \([^)]+\)' "$snapshot_file"
    grep -Eq 'Stage: \[[^]]+\] Parallel Work \([^)]+\)' "$snapshot_file"
}
