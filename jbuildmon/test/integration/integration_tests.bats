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

    INTEGRATION_JOB="$(_get_integration_job)"
}

_get_integration_job() {
    local branch="${BRANCH_NAME:-}"

    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="main"
    fi

    echo "buildgit-integration-test/${branch}"
}

_cache_dir() {
    echo "${BATS_FILE_TMPDIR}/integration-cache"
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

        sleep 1
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

        sleep 1
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

        sleep 1
    done

    echo "Timed out waiting for build #${build_number} of ${job_name} to complete" >&2
    return 1
}

_extract_stage_lines() {
    local source_file="$1"
    grep 'Stage:' "$source_file" || true
}

_normalized_stage_names() {
    local source_file="$1"

    _extract_stage_lines "$source_file" | sed -E '
        s/^\[[^]]+\][[:space:]]+[^[:space:]]+[[:space:]]+Stage:[[:space:]]*//
        s/^║[0-9]+[[:space:]]+//
        s/^\[[^]]+\][[:space:]]+//
        s/[[:space:]]+\([^()]*\)$//
    '
}

_assert_stage_patterns() {
    local source_file="$1"
    local stage_lines
    stage_lines=$(_extract_stage_lines "$source_file")

    [[ -n "$stage_lines" ]]

    echo "$stage_lines" | grep -Eq 'Stage: \[[^]]+\] Setup \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║1 \[[^]]+\] Quick Task \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║2 \[[^]]+\] Slow Pipeline->Compile \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║2 \[[^]]+\] Slow Pipeline->Package \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║2 \[[^]]+\] Slow Pipeline \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║3 \[[^]]+\] Default Pipeline->Lint \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║3 \[[^]]+\] Default Pipeline->Analyze \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║3 \[[^]]+\] Default Pipeline->Report \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage:   ║3 \[[^]]+\] Default Pipeline \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage: \[[^]]+\] Parallel Work \([^)]+\)'
    echo "$stage_lines" | grep -Eq 'Stage: \[[^]]+\] Finalize \([^)]+\)'
}

_line_number_for_pattern() {
    local source_file="$1"
    local pattern="$2"

    grep -nE "$pattern" "$source_file" | head -1 | cut -d: -f1
}

_extract_agent_for_pattern() {
    local source_file="$1"
    local pattern="$2"

    grep -E "$pattern" "$source_file" | head -1 | sed -E 's/.*\[([^]]+)\].*/\1/' | xargs
}

_extract_stage_duration_text() {
    local source_file="$1"
    local pattern="$2"

    grep -E "$pattern" "$source_file" | head -1 | sed -E 's/.*\(([^()]*)\)$/\1/'
}

_duration_to_seconds() {
    local duration_text="$1"
    local total=0
    local value

    if [[ "$duration_text" == "<1s" ]]; then
        echo 0
        return 0
    fi

    if [[ "$duration_text" =~ ^([0-9]+)h ]]; then
        value="${BASH_REMATCH[1]}"
        total=$((total + value * 3600))
    fi
    if [[ "$duration_text" =~ ([0-9]+)m ]]; then
        value="${BASH_REMATCH[1]}"
        total=$((total + value * 60))
    fi
    if [[ "$duration_text" =~ ([0-9]+)s ]]; then
        value="${BASH_REMATCH[1]}"
        total=$((total + value))
    fi

    echo "$total"
}

_ensure_all_cached() {
    local cache_dir failure_file lock_dir
    cache_dir="$(_cache_dir)"
    failure_file="$(_cache_file failure.txt)"
    lock_dir="$(_cache_file lock.lck)"
    mkdir -p "$cache_dir"

    if [[ -f "$(_cache_file ready)" ]]; then
        return 0
    fi
    if [[ -f "$failure_file" ]]; then
        cat "$failure_file" >&2
        return 1
    fi

    # mkdir-based mutex: only one parallel test runner does the real work
    if ! mkdir "$lock_dir" 2>/dev/null; then
        local deadline=$((SECONDS + 300))
        while (( SECONDS < deadline )); do
            if [[ -f "$(_cache_file ready)" ]]; then
                return 0
            fi
            if [[ -f "$failure_file" ]]; then
                cat "$failure_file" >&2
                return 1
            fi
            sleep 1
        done
        echo "_ensure_all_cached: timed out waiting for cache to become ready" >&2
        return 1
    fi

    # Check again after acquiring lock (another process may have just finished)
    if [[ -f "$(_cache_file ready)" ]]; then
        rmdir "$lock_dir" 2>/dev/null || true
        return 0
    fi

    if ! _wait_for_integration_job_indexed "$INTEGRATION_JOB" 180; then
        printf '%s\n' "Integration job branch was not indexed within 180s: ${INTEGRATION_JOB}" > "$failure_file"
        echo "Integration job branch was not indexed within 180s: ${INTEGRATION_JOB}" >&2
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
    fi

    # Trigger ONE build and capture live monitoring output.
    # MONITOR_SETTLE_MAX_SECONDS: after the sub-job completes (19s), the default
    # settle period polls for 45 iterations; each iteration also runs API calls
    # (~3-4s), so wall-clock settle time is 45×4≈180s. Capping at 10 reduces
    # settle to ~40s while still allowing 10 stable-state checks for stage data.
    local build_output build_rc
    set +e
    build_output=$(MONITOR_SETTLE_MAX_SECONDS=10 MONITOR_SETTLE_STABLE_POLLS=1 "${BUILDGIT}" --job "$INTEGRATION_JOB" build --prior-jobs 0 3>&- 2>&1)
    build_rc=$?
    set -e
    printf '%s\n' "$build_output" > "$(_cache_file build_monitor_output.txt)"
    printf '%s\n' "$build_rc" > "$(_cache_file build_monitor_exit_code.txt)"

    if [[ $build_rc -ne 0 ]]; then
        echo "$build_output" >&2
        printf '%s\n' "buildgit build failed for ${INTEGRATION_JOB}" > "$failure_file"
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
    fi

    # Extract build number from monitoring output to enable parallel status fetches
    local build_number
    build_number=$(printf '%s\n' "$build_output" | grep -E '^Build:[[:space:]]+#[0-9]+' | head -1 | sed 's/.*#//')
    if [[ -z "$build_number" ]]; then
        printf '%s\n' "Could not extract build number from buildgit build output for ${INTEGRATION_JOB}" > "$failure_file"
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
    fi
    printf '%s\n' "$build_number" > "$(_cache_file build_number.txt)"

    # Fetch status --json and status --all in parallel (3>&- avoids bats fd 3 inheritance)
    local json_tmp all_tmp
    json_tmp="$(_cache_dir)/json_out.tmp"
    all_tmp="$(_cache_dir)/all_out.tmp"
    local json_rc=0 all_rc=0

    set +e
    "${BUILDGIT}" --job "$INTEGRATION_JOB" status --json > "$json_tmp" 2>&1 3>&- &
    local json_pid=$!
    "${BUILDGIT}" --job "$INTEGRATION_JOB" status "$build_number" --all > "$all_tmp" 2>&1 3>&- &
    local all_pid=$!

    wait $json_pid; json_rc=$?
    wait $all_pid; all_rc=$?
    set -e

    mv "$json_tmp" "$(_cache_file status.json)"
    printf '%s\n' "$json_rc" > "$(_cache_file status_json_exit_code.txt)"
    mv "$all_tmp" "$(_cache_file status_all.txt)"
    printf '%s\n' "$all_rc" > "$(_cache_file status_all_exit_code.txt)"

    if [[ $json_rc -ne 0 || ! -s "$(_cache_file status.json)" ]]; then
        cat "$(_cache_file status.json)" >&2
        printf '%s\n' "Failed to capture JSON status for ${INTEGRATION_JOB}" > "$failure_file"
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
    fi

    if [[ $all_rc -ne 0 || ! -s "$(_cache_file status_all.txt)" ]]; then
        cat "$(_cache_file status_all.txt)" >&2
        printf '%s\n' "Failed to capture full status output for ${INTEGRATION_JOB} #${build_number}" > "$failure_file"
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
    fi

    touch "$(_cache_file ready)"
    touch "$(_cache_file build_monitor_ready)"
    rmdir "$lock_dir" 2>/dev/null || true
}

_ensure_build_complete() {
    _ensure_all_cached
}

_ensure_build_command_monitor_complete() {
    _ensure_all_cached
}

@test "parallel-substages: build completes successfully" {
    _ensure_build_complete

    local build_number json_file
    build_number=$(cat "$(_cache_file build_number.txt)")
    json_file="$(_cache_file status.json)"

    [[ -n "$build_number" ]]
    [[ -s "$json_file" ]]
    [[ "$(cat "$(_cache_file status_json_exit_code.txt)")" -eq 0 ]]
    [[ "$(jq -r '.build.number // empty' "$json_file")" == "$build_number" ]]
    [[ "$(jq -r '.build.status // empty' "$json_file")" == 'SUCCESS' ]]
}

@test "parallel-substages: snapshot output matches expected structure" {
    _ensure_build_complete

    local snapshot_file
    snapshot_file="$(_cache_file status_all.txt)"

    [[ "$(cat "$(_cache_file status_all_exit_code.txt)")" -eq 0 ]]
    _assert_stage_patterns "$snapshot_file"
}

@test "parallel-substages: monitoring output matches expected structure" {
    _ensure_build_command_monitor_complete

    local monitor_file
    monitor_file="$(_cache_file build_monitor_output.txt)"

    [[ -s "$monitor_file" ]]
    _assert_stage_patterns "$monitor_file"
}

@test "parallel-substages: sub-stages appear before branch summaries and wrapper" {
    _ensure_build_complete

    local snapshot_file compile_line package_line slow_summary_line lint_line report_line default_summary_line wrapper_line
    snapshot_file="$(_cache_file status_all.txt)"

    compile_line=$(_line_number_for_pattern "$snapshot_file" 'Slow Pipeline->Compile')
    package_line=$(_line_number_for_pattern "$snapshot_file" 'Slow Pipeline->Package')
    slow_summary_line=$(_line_number_for_pattern "$snapshot_file" 'Stage:   ║2 \[[^]]+\] Slow Pipeline \(')
    lint_line=$(_line_number_for_pattern "$snapshot_file" 'Default Pipeline->Lint')
    report_line=$(_line_number_for_pattern "$snapshot_file" 'Default Pipeline->Report')
    default_summary_line=$(_line_number_for_pattern "$snapshot_file" 'Stage:   ║3 \[[^]]+\] Default Pipeline \(')
    wrapper_line=$(_line_number_for_pattern "$snapshot_file" 'Stage: \[[^]]+\] Parallel Work \(')

    [[ -n "$compile_line" && -n "$package_line" && -n "$slow_summary_line" ]]
    [[ -n "$lint_line" && -n "$report_line" && -n "$default_summary_line" && -n "$wrapper_line" ]]
    (( compile_line < slow_summary_line ))
    (( package_line < slow_summary_line ))
    (( lint_line < default_summary_line ))
    (( report_line < default_summary_line ))
    (( slow_summary_line < wrapper_line ))
    (( default_summary_line < wrapper_line ))
}

@test "parallel-substages: slownode branch keeps an explicit agent label" {
    _ensure_build_complete

    local snapshot_file setup_agent slow_agent
    snapshot_file="$(_cache_file status_all.txt)"

    setup_agent=$(_extract_agent_for_pattern "$snapshot_file" 'Stage: \[[^]]+\] Setup')
    slow_agent=$(_extract_agent_for_pattern "$snapshot_file" 'Slow Pipeline->Compile')

    [[ -n "$setup_agent" ]]
    [[ -n "$slow_agent" ]]
}

@test "parallel-substages: default branch inherits the pipeline agent" {
    _ensure_build_complete

    local snapshot_file setup_agent default_agent
    snapshot_file="$(_cache_file status_all.txt)"

    setup_agent=$(_extract_agent_for_pattern "$snapshot_file" 'Stage: \[[^]]+\] Setup')
    default_agent=$(_extract_agent_for_pattern "$snapshot_file" 'Default Pipeline->Lint')

    [[ -n "$setup_agent" ]]
    [[ -n "$default_agent" ]]
    [[ "$setup_agent" == "$default_agent" ]]
}

@test "parallel-substages: aggregate durations reflect sequential branch work" {
    _ensure_build_complete

    local snapshot_file slow_duration_text default_duration_text wrapper_duration_text
    local slow_duration default_duration wrapper_duration
    snapshot_file="$(_cache_file status_all.txt)"

    slow_duration_text=$(_extract_stage_duration_text "$snapshot_file" 'Stage:   ║2 \[[^]]+\] Slow Pipeline \(')
    default_duration_text=$(_extract_stage_duration_text "$snapshot_file" 'Stage:   ║3 \[[^]]+\] Default Pipeline \(')
    wrapper_duration_text=$(_extract_stage_duration_text "$snapshot_file" 'Stage: \[[^]]+\] Parallel Work \(')

    slow_duration=$(_duration_to_seconds "$slow_duration_text")
    default_duration=$(_duration_to_seconds "$default_duration_text")
    wrapper_duration=$(_duration_to_seconds "$wrapper_duration_text")

    (( slow_duration >= 7 ))
    (( default_duration >= 7 ))
    (( wrapper_duration >= slow_duration ))
    (( wrapper_duration >= default_duration ))
}

@test "parallel-substages: build monitoring output matches snapshot stage set" {
    _ensure_build_complete
    _ensure_build_command_monitor_complete

    local snapshot_file build_monitor_file snapshot_names_file build_names_file
    snapshot_file="$(_cache_file status_all.txt)"
    build_monitor_file="$(_cache_file build_monitor_output.txt)"
    snapshot_names_file="$(_cache_file snapshot_stage_names.txt)"
    build_names_file="$(_cache_file build_stage_names.txt)"

    [[ "$(cat "$(_cache_file build_monitor_exit_code.txt)")" -eq 0 ]]

    _normalized_stage_names "$snapshot_file" | sort -u > "$snapshot_names_file"
    _normalized_stage_names "$build_monitor_file" | sort -u > "$build_names_file"

    diff -u "$snapshot_names_file" "$build_names_file"
}

@test "parallel-substages: build monitoring does not emit flat leaf stages after finalize" {
    _ensure_build_command_monitor_complete

    local build_monitor_file finalize_line duplicate_leaf_lines
    build_monitor_file="$(_cache_file build_monitor_output.txt)"
    finalize_line=$(_line_number_for_pattern "$build_monitor_file" 'Stage: \[[^]]+\] Finalize \(')

    [[ -n "$finalize_line" ]]

    duplicate_leaf_lines=$(tail -n +"$((finalize_line + 1))" "$build_monitor_file" | \
        grep -E 'Stage: (Lint|Compile|Analyze|Package|Report) \([^)]+\)' || true)

    [[ -z "$duplicate_leaf_lines" ]]
}
