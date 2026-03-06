#!/usr/bin/env bats

# Tests for buildgit status command - follow mode
# Spec reference: buildgit-spec.md, buildgit status -f/--follow
# Plan reference: buildgit-plan.md, Chunk 5

load test_helper

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # Store original environment
    ORIG_JENKINS_URL="${JENKINS_URL:-}"
    ORIG_JENKINS_USER_ID="${JENKINS_USER_ID:-}"
    ORIG_JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"

    # Set up mock Jenkins environment
    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    # Create a test git repository
    TEST_REPO="${TEST_TEMP_DIR}/repo"
    mkdir -p "${TEST_REPO}"
    cd "${TEST_REPO}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"

    # Add a remote origin (needed for job name discovery)
    git remote add origin "git@github.com:testorg/test-repo.git"
}

teardown() {
    # Clean up temporary directory
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi

    # Restore original environment
    export JENKINS_URL="${ORIG_JENKINS_URL}"
    export JENKINS_USER_ID="${ORIG_JENKINS_USER_ID}"
    export JENKINS_API_TOKEN="${ORIG_JENKINS_API_TOKEN}"
}

# =============================================================================
# Helper: Create wrapper for follow mode testing
# =============================================================================

# Create wrapper that simulates a build lifecycle
# Arguments:
#   $1 - initial building state (true/false)
#   $2 - final result after building completes (SUCCESS, FAILURE, etc.)
#   $3 - number of poll cycles before build completes
create_follow_test_wrapper() {
    local initial_building="${1:-true}"
    local final_result="${2:-SUCCESS}"
    local poll_cycles="${3:-2}"

    # Create a modified copy of buildgit
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    # Initialize file-based counter (persists across subshells)
    echo "0" > "${TEST_TEMP_DIR}/build_info_calls"

    # Write the wrapper script with proper variable substitution
cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

# Source buildgit without executing main
_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

# Override poll interval for faster tests
POLL_INTERVAL=1
MAX_BUILD_TIME=30
# Speed up settle loop to 1 stable poll (avoids waiting 3s in CI)
MONITOR_SETTLE_STABLE_POLLS=1

# Override Jenkins API functions with mocks
verify_jenkins_connection() {
    return 0
}

verify_job_exists() {
    local job_name="$1"
    JOB_URL="${JENKINS_URL}/job/${job_name}"
    return 0
}

jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        echo '{"duration":120000}'
        return 0
    fi
    echo ""
    return 1
}

get_last_build_number() {
    echo "42"
}

get_build_info() {
    # Use file-based counter for persistence across command substitution subshells
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_info_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_info_calls"

    if [[ $count -le __POLL_CYCLES__ ]]; then
        # Build still in progress
        echo '{"number":42,"result":"null","building":__INITIAL_BUILDING__,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        # Build completed
        echo '{"number":42,"result":"__FINAL_RESULT__","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    fi
}

# Mock get_all_stages to avoid HTTP timeout in CI (stage tracking not needed for these tests)
get_all_stages() {
    echo "[]"
}

# Mock fetch_test_results to avoid HTTP timeout in CI
fetch_test_results() {
    echo ""
}

get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}

get_current_stage() {
    echo "Build"
}

# Set job name to skip auto-detection
JOB_NAME="test-repo"

wrapper_args=()
for arg in "$@"; do
    if [[ "$arg" == "--threads" ]]; then
        THREADS_MODE=true
        continue
    fi
    wrapper_args+=("$arg")
done

# Call the status command with follow mode
cmd_status -f --prior-jobs 0 "${wrapper_args[@]}"
WRAPPER_END

    # Replace placeholders with actual values (portable: temp file + mv works on both macOS and Linux)
    sed "s|__POLL_CYCLES__|${poll_cycles}|g; s|__INITIAL_BUILDING__|${initial_building}|g; s|__FINAL_RESULT__|${final_result}|g" \
        "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" \
        && mv "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

create_follow_line_progress_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/follow_line_progress.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

date() {
    if [[ "${1:-}" == "+%s" ]]; then
        echo "${FAKE_NOW_SECONDS:-1706700000}"
        return 0
    fi
    command date "$@"
}

jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        if [[ "${MOCK_LAST_SUCCESS_KIND:-duration}" == "none" ]]; then
            echo '{}'
        else
            echo '{"number":41,"duration":250000}'
        fi
        return 0
    fi
    if [[ "${1:-}" == *"/job/ralph1/api/json?tree=builds[number,building,timestamp,result]{0,10}" ]]; then
        if [[ "${MOCK_RUNNING_BUILDS:-single}" == "two" ]]; then
            echo '{"builds":[{"number":42,"building":true,"timestamp":1706700000000},{"number":43,"building":true,"timestamp":1706700010000}]}'
        elif [[ "${MOCK_RUNNING_BUILDS:-single}" == "mixed-order" ]]; then
            echo '{"builds":[{"number":44,"building":true,"timestamp":1706700020000},{"number":42,"building":true,"timestamp":1706700000000},{"number":43,"building":true,"timestamp":1706700010000}]}'
        else
            echo '{"builds":[{"number":42,"building":true,"timestamp":1706700000000}]}'
        fi
        return 0
    fi
    if [[ "${1:-}" == "/queue/api/json" ]]; then
        if [[ "${MOCK_QUEUE_STATE:-none}" == "queued" ]]; then
            echo '{"items":[{"id":910,"task":{"name":"ralph1"},"blocked":true,"buildable":false,"why":"Build #218 is already in progress  ETA: 1m 34s","inQueueSince":1706700000000}]}'
        else
            echo '{"items":[]}'
        fi
        return 0
    fi
    echo ""
    return 1
}

_get_nested_stages() {
    local job_name="$1"
    local build_number="$2"

    if [[ "$build_number" == "41" ]]; then
        echo '[{"name":"Build","status":"SUCCESS","durationMillis":4000,"agent":"agent6 guthrie"},{"name":"Unit Tests A","status":"SUCCESS","durationMillis":138000,"agent":"agent6 guthrie"},{"name":"Unit Tests B","status":"SUCCESS","durationMillis":89000,"agent":"agent7 guthrie"},{"name":"Unit Tests C","status":"SUCCESS","durationMillis":126000,"agent":"agent8 guthrie"}]'
        return 0
    fi

    case "${MOCK_WFAPI_STATE:-single}" in
        single)
            echo '[{"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706700000000,"durationMillis":0,"agent":"agent6 guthrie"}]'
            ;;
        parallel)
            echo '[{"name":"Setup","status":"SUCCESS","startTimeMillis":1706699900000,"durationMillis":5000,"agent":"orch1"},{"name":"Unit Tests A","status":"IN_PROGRESS","startTimeMillis":1706699945000,"durationMillis":0,"agent":"agent6 guthrie","parallel_branch":"Unit Tests A"},{"name":"Unit Tests B","status":"IN_PROGRESS","startTimeMillis":1706699997000,"durationMillis":0,"agent":"agent7 guthrie","parallel_branch":"Unit Tests B"},{"name":"Unit Tests C","status":"IN_PROGRESS","startTimeMillis":1706700013000,"durationMillis":0,"agent":"agent8 guthrie","parallel_branch":"Unit Tests C"}]'
            ;;
        parallel_lagged)
            echo '[{"name":"Unit Tests A","status":"SUCCESS","durationMillis":35,"agent":"","parallel_branch":"Unit Tests A","parallel_wrapper":"Unit Tests"},{"name":"Unit Tests B","status":"IN_PROGRESS","startTimeMillis":1706699945000,"durationMillis":29205,"agent":"agent7 guthrie","parallel_branch":"Unit Tests B","parallel_wrapper":"Unit Tests"},{"name":"Unit Tests C","status":"SUCCESS","durationMillis":-12,"agent":"","parallel_branch":"Unit Tests C","parallel_wrapper":"Unit Tests"},{"name":"Unit Tests D","status":"SUCCESS","durationMillis":-11,"agent":"agent8_sixcore","parallel_branch":"Unit Tests D","parallel_wrapper":"Unit Tests"},{"name":"Unit Tests","status":"SUCCESS","durationMillis":29340,"agent":"","is_parallel_wrapper":true,"parallel_branches":["Unit Tests A","Unit Tests B","Unit Tests C","Unit Tests D"]}]'
            ;;
        wrapper_agent_fallback|wrapper_agent_no_console|wrapper_agent_no_pipeline_scope)
            echo '[{"name":"Build Handle->Compile","status":"IN_PROGRESS","startTimeMillis":1706700010000,"durationMillis":0,"agent":"agent8_sixcore","parallel_branch":"Build Handle","parallel_wrapper":"Trigger Component Builds"},{"name":"Build SignalBoot->System Diagnostics","status":"IN_PROGRESS","startTimeMillis":1706700011000,"durationMillis":0,"agent":"agent7 guthrie","parallel_branch":"Build SignalBoot","parallel_wrapper":"Trigger Component Builds"},{"name":"Trigger Component Builds","status":"IN_PROGRESS","startTimeMillis":1706700005000,"durationMillis":0,"agent":"orchestrator1","is_parallel_wrapper":true,"parallel_branches":["Build Handle","Build SignalBoot"]}]'
            ;;
        unknown)
            echo '[{"name":"Brand New Stage","status":"IN_PROGRESS","startTimeMillis":1706700023000,"durationMillis":0,"agent":"agent6 guthrie"}]'
            ;;
        overflow)
            echo '[{"name":"Stage 1","status":"IN_PROGRESS","startTimeMillis":1706700000000,"durationMillis":0,"agent":"agent1"},{"name":"Stage 2","status":"IN_PROGRESS","startTimeMillis":1706700001000,"durationMillis":0,"agent":"agent2"},{"name":"Stage 3","status":"IN_PROGRESS","startTimeMillis":1706700002000,"durationMillis":0,"agent":"agent3"},{"name":"Stage 4","status":"IN_PROGRESS","startTimeMillis":1706700003000,"durationMillis":0,"agent":"agent4"},{"name":"Stage 5","status":"IN_PROGRESS","startTimeMillis":1706700004000,"durationMillis":0,"agent":"agent5"},{"name":"Stage 6","status":"IN_PROGRESS","startTimeMillis":1706700005000,"durationMillis":0,"agent":"agent6"},{"name":"Stage 7","status":"IN_PROGRESS","startTimeMillis":1706700006000,"durationMillis":0,"agent":"agent7"},{"name":"Stage 8","status":"IN_PROGRESS","startTimeMillis":1706700007000,"durationMillis":0,"agent":"agent8"},{"name":"Stage 9","status":"IN_PROGRESS","startTimeMillis":1706700008000,"durationMillis":0,"agent":"agent9"},{"name":"Stage 10","status":"IN_PROGRESS","startTimeMillis":1706700009000,"durationMillis":0,"agent":"agent10"},{"name":"Stage 11","status":"IN_PROGRESS","startTimeMillis":1706700010000,"durationMillis":0,"agent":"agent11"},{"name":"Stage 12","status":"IN_PROGRESS","startTimeMillis":1706700011000,"durationMillis":0,"agent":"agent12"}]'
            ;;
        long_name)
            echo '[{"name":"A very long stage name that should be truncated before the progress bar moves","status":"IN_PROGRESS","startTimeMillis":1706700000000,"durationMillis":0,"agent":"agent6 guthrie"}]'
            ;;
    esac
}

get_all_stages() {
    case "${MOCK_WFAPI_STATE:-single}" in
        parallel_lagged)
            echo '[{"name":"Unit Tests","status":"SUCCESS","startTimeMillis":1706699945000,"durationMillis":135},{"name":"Unit Tests A","status":"SUCCESS","startTimeMillis":1706699945000,"durationMillis":35},{"name":"Unit Tests B","status":"IN_PROGRESS","startTimeMillis":1706699945000,"durationMillis":29176},{"name":"Unit Tests C","status":"SUCCESS","startTimeMillis":1706699945000,"durationMillis":-12},{"name":"Unit Tests D","status":"SUCCESS","startTimeMillis":1706699945000,"durationMillis":-11}]'
            ;;
        wrapper_agent_fallback|wrapper_agent_no_console|wrapper_agent_no_pipeline_scope)
            echo '[{"name":"Trigger Component Builds","status":"IN_PROGRESS","startTimeMillis":1706700005000,"durationMillis":29000},{"name":"Build Handle","status":"IN_PROGRESS","startTimeMillis":1706700005000,"durationMillis":28000},{"name":"Build SignalBoot","status":"IN_PROGRESS","startTimeMillis":1706700006000,"durationMillis":27000}]'
            ;;
        *)
            command echo '[]'
            ;;
    esac
}

get_console_output() {
    case "${MOCK_WFAPI_STATE:-single}" in
        parallel_lagged)
            cat <<'EOF'
[Pipeline] { (Unit Tests)
[Pipeline] parallel
[Pipeline] { (Branch: Unit Tests A)
[Pipeline] { (Branch: Unit Tests B)
[Pipeline] { (Branch: Unit Tests C)
[Pipeline] { (Branch: Unit Tests D)
[Pipeline] stage
[Pipeline] { (Unit Tests A)
[Pipeline] stage
[Pipeline] { (Unit Tests B)
[Pipeline] stage
[Pipeline] { (Unit Tests C)
[Pipeline] stage
[Pipeline] { (Unit Tests D)
[Pipeline] node
Running on agent8_sixcore in /tmp/ws
[Pipeline] node
Running on agent8_sixcore in /tmp/ws@2
[Pipeline] node
Running on agent7 guthrie in /tmp/ws
[Pipeline] node
Running on agent6 guthrie in /tmp/ws
EOF
            ;;
        wrapper_agent_fallback)
            cat <<'EOF'
Running on orchestrator1 in /tmp/ws
[Pipeline] stage
[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] { (Branch: Build Handle)
[Pipeline] { (Branch: Build SignalBoot)
[Pipeline] stage
[Pipeline] { (Build Handle)
[Pipeline] build
[Pipeline] node
Running on agent8_sixcore in /tmp/ws@2
[Pipeline] stage
[Pipeline] { (Build SignalBoot->System Diagnostics)
[Pipeline] node
Running on agent7 guthrie in /tmp/ws@3
EOF
            ;;
        wrapper_agent_no_pipeline_scope)
            cat <<'EOF'
[Pipeline] stage
[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] { (Branch: Build Handle)
[Pipeline] { (Branch: Build SignalBoot)
[Pipeline] stage
[Pipeline] { (Build Handle->Compile)
[Pipeline] node
Running on agent8_sixcore in /tmp/ws@2
[Pipeline] stage
[Pipeline] { (Build SignalBoot->System Diagnostics)
[Pipeline] node
Running on agent7 guthrie in /tmp/ws@3
EOF
            ;;
        wrapper_agent_no_console)
            echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

case "${1:-}" in
    determinate)
        FAKE_NOW_SECONDS=1706700035
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000}' "100000" "0"
        ;;
    unknown)
        FAKE_NOW_SECONDS=1706700035
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000}' "" "3"
        ;;
    over)
        FAKE_NOW_SECONDS=1706700180
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000}' "120000" "0"
        ;;
    two_builds)
        FAKE_NOW_SECONDS=1706700035
        MOCK_RUNNING_BUILDS=two
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "100000" "0"
        ;;
    queued)
        FAKE_NOW_SECONDS=1706700035
        MOCK_RUNNING_BUILDS=two
        MOCK_QUEUE_STATE=queued
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "100000" "3" "true"
        ;;
    mixed_order)
        FAKE_NOW_SECONDS=1706700035
        MOCK_RUNNING_BUILDS=mixed-order
        _display_follow_line_progress "ralph1" "43" '{"timestamp":1706700010000,"building":true}' "100000" "0"
        ;;
    threads_single)
        FAKE_NOW_SECONDS=1706700035
        THREADS_MODE=true
        MOCK_WFAPI_STATE=single
        _prime_follow_progress_estimates "ralph1"
        estimate_ms="${_FOLLOW_BUILD_ESTIMATE_MS:-}"
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "$estimate_ms" "0" "false" "$(_get_follow_active_stages "ralph1" "42")"
        ;;
    threads_parallel)
        FAKE_NOW_SECONDS=1706700035
        THREADS_MODE=true
        MOCK_WFAPI_STATE=parallel
        _prime_follow_progress_estimates "ralph1"
        estimate_ms="${_FOLLOW_BUILD_ESTIMATE_MS:-}"
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "$estimate_ms" "0" "false" "$(_get_follow_active_stages "ralph1" "42")"
        ;;
    threads_unknown)
        FAKE_NOW_SECONDS=1706700035
        THREADS_MODE=true
        MOCK_WFAPI_STATE=unknown
        _prime_follow_progress_estimates "ralph1"
        estimate_ms="${_FOLLOW_BUILD_ESTIMATE_MS:-}"
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "$estimate_ms" "3" "false" "$(_get_follow_active_stages "ralph1" "42")"
        ;;
    threads_overflow)
        FAKE_NOW_SECONDS=1706700035
        THREADS_MODE=true
        MOCK_WFAPI_STATE=overflow
        export LINES=10
        _prime_follow_progress_estimates "ralph1"
        estimate_ms="${_FOLLOW_BUILD_ESTIMATE_MS:-}"
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "$estimate_ms" "0" "false" "$(_get_follow_active_stages "ralph1" "42")"
        ;;
    threads_long_name)
        FAKE_NOW_SECONDS=1706700035
        THREADS_MODE=true
        MOCK_WFAPI_STATE=long_name
        export COLUMNS=70
        _prime_follow_progress_estimates "ralph1"
        estimate_ms="${_FOLLOW_BUILD_ESTIMATE_MS:-}"
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "$estimate_ms" "0" "false" "$(_get_follow_active_stages "ralph1" "42")"
        ;;
    threads_parallel_lagged)
        FAKE_NOW_SECONDS=1706700035
        THREADS_MODE=true
        MOCK_WFAPI_STATE=parallel_lagged
        _prime_follow_progress_estimates "ralph1"
        estimate_ms="${_FOLLOW_BUILD_ESTIMATE_MS:-}"
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "$estimate_ms" "0" "false" "$(_get_follow_active_stages "ralph1" "42")"
        ;;
    active_wrapper_agent_fallback)
        MOCK_WFAPI_STATE=wrapper_agent_fallback
        _get_follow_active_stages "ralph1" "42"
        ;;
    active_wrapper_agent_no_console)
        MOCK_WFAPI_STATE=wrapper_agent_no_console
        _get_follow_active_stages "ralph1" "42"
        ;;
    active_wrapper_agent_no_pipeline_scope)
        MOCK_WFAPI_STATE=wrapper_agent_no_pipeline_scope
        _get_follow_active_stages "ralph1" "42"
        ;;
    threads_wrapper_agent_fallback)
        FAKE_NOW_SECONDS=1706700035
        THREADS_MODE=true
        MOCK_WFAPI_STATE=wrapper_agent_fallback
        _prime_follow_progress_estimates "ralph1"
        estimate_ms="${_FOLLOW_BUILD_ESTIMATE_MS:-}"
        _display_follow_line_progress "ralph1" "42" '{"timestamp":1706700000000,"building":true}' "$estimate_ms" "0" "false" "$(_get_follow_active_stages "ralph1" "42")"
        ;;
    estimate)
        _get_last_successful_build_duration "ralph1"
        ;;
    *)
        echo "unknown action" >&2
        exit 1
        ;;
esac
WRAPPER_END

    chmod +x "${TEST_TEMP_DIR}/follow_line_progress.sh"
}

# Create wrapper for -n with follow mode tests
# Supports builds 40-43: latest can be 42 (completed) or 43 (in-progress)
# Arguments:
#   $1 - latest_build_number (42 or 43)
#   $2 - latest_building: whether latest build is in-progress (true/false)
create_follow_n_prior_wrapper() {
    local latest_build="${1:-42}"
    local latest_building="${2:-false}"

    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    # Counter for latest build polling (file-based for cross-subshell persistence)
    echo "0" > "${TEST_TEMP_DIR}/build_latest_calls"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=30

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}

get_last_build_number() {
    echo "__LATEST_BUILD__"
}

get_build_info() {
    local build_num="${2:-__LATEST_BUILD__}"
    case "$build_num" in
        __LATEST_BUILD__)
            local calls
            calls=$(cat "${TEST_TEMP_DIR}/build_latest_calls")
            calls=$((calls + 1))
            echo "$calls" > "${TEST_TEMP_DIR}/build_latest_calls"
            if [[ "__LATEST_BUILDING__" == "true" && $calls -le 2 ]]; then
                echo '{"number":__LATEST_BUILD__,"result":"null","building":true,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/__LATEST_BUILD__/"}'
            else
                echo '{"number":__LATEST_BUILD__,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":60000,"url":"http://jenkins.example.com/job/test-repo/__LATEST_BUILD__/"}'
            fi
            ;;
        42)
            echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706699700000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
            ;;
        41)
            echo '{"number":41,"result":"FAILURE","building":false,"timestamp":1706699400000,"duration":90000,"url":"http://jenkins.example.com/job/test-repo/41/"}'
            ;;
        40)
            echo '{"number":40,"result":"SUCCESS","building":false,"timestamp":1706699100000,"duration":80000,"url":"http://jenkins.example.com/job/test-repo/40/"}'
            ;;
        *)
            echo ""
            ;;
    esac
}

get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}

get_current_stage() {
    echo "Build"
}

# Mock HTTP functions to avoid real connections in CI (bats sandbox)
get_all_stages() {
    echo "[]"
}

get_failed_stage() {
    echo ""
}

fetch_test_results() {
    echo ""
}

JOB_NAME="test-repo"
cmd_status -f --prior-jobs 0 "$@"
WRAPPER_END

    sed -e "s|__LATEST_BUILD__|${latest_build}|g" \
        -e "s|__LATEST_BUILDING__|${latest_building}|g" \
        "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" \
        && mv "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Create wrapper that simulates detecting a new build
create_new_build_detection_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    # Counter for build-number progression (file-based for subshell persistence)
    echo "0" > "${TEST_TEMP_DIR}/build_number_calls"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="__PROJECT_DIR__"
export TEST_TEMP_DIR="__TEST_TEMP_DIR__"

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=30

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}

# Simulate build number progression
get_last_build_number() {
    local calls
    calls=$(cat "${TEST_TEMP_DIR}/build_number_calls")
    calls=$((calls + 1))
    echo "$calls" > "${TEST_TEMP_DIR}/build_number_calls"
    # First few calls return 42, then return 43 to simulate new build
    if [[ $calls -le 3 ]]; then
        echo "42"
    else
        echo "43"
    fi
}

get_build_info() {
    local build_num="${2:-42}"

    if [[ "$build_num" == "42" ]]; then
        echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        echo '{"number":43,"result":"SUCCESS","building":false,"timestamp":1706700060000,"duration":90000,"url":"http://jenkins.example.com/job/test-repo/43/"}'
    fi
}

get_console_output() {
    echo "Started by user testuser"
}

get_current_stage() {
    echo "Build"
}

# Mock HTTP functions to avoid real connections in CI (bats sandbox)
get_all_stages() {
    echo "[]"
}

get_failed_stage() {
    echo ""
}

fetch_test_results() {
    echo ""
}

JOB_NAME="test-repo"
cmd_status -f --prior-jobs 0 "$@"
WRAPPER

    # Substitute paths (portable: temp file + mv works on both macOS and Linux)
    sed "s|__PROJECT_DIR__|${PROJECT_DIR}|g; s|__TEST_TEMP_DIR__|${TEST_TEMP_DIR}|g" \
        "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" \
        && mv "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# =============================================================================
# Test Cases: Follow Mode Basic Functionality
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Follow mode monitors a current in-progress build
# Spec: "-f, --follow: monitor current build if in progress"
# -----------------------------------------------------------------------------
@test "follow_monitors_current_build" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR

    # Build in-progress: follow mode should monitor it and show result when done
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"
    assert_success

    # Should show follow mode entered the monitoring path for an in-progress build.
    # "BUILD IN PROGRESS" banner appears immediately when monitoring starts.
    [[ "$output" == *"BUILD IN PROGRESS"* ]] || [[ "$output" == *"BUILDING"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode shows waiting message after build completes
# Spec: "Displays 'Waiting for next build of <job>...' between builds"
# -----------------------------------------------------------------------------
@test "follow_waits_for_next_build" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build already complete (not building)
    create_follow_test_wrapper "false" "SUCCESS" "1"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=1 2>&1"
    assert_failure

    assert_output --partial "no new build detected for 1 seconds"
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode detects and monitors new builds
# Spec: "-f, --follow: wait indefinitely for subsequent builds"
# -----------------------------------------------------------------------------
@test "follow_detects_new_build" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_new_build_detection_wrapper

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=20 2>&1"
    assert_success
    assert_output --partial "#43"
}

# -----------------------------------------------------------------------------
# Test Case: Ctrl+C exits cleanly with appropriate message
# Spec: "Exit with Ctrl+C"
# Note: Testing actual SIGINT handling is unreliable in bats, so we verify
#       the cleanup handler is defined and test timeout-based exit instead.
# -----------------------------------------------------------------------------
@test "follow_ctrl_c_exits_cleanly" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR

    # Create wrapper that will be terminated by timeout
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=30

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() { echo "Started by user testuser"; }
get_current_stage() { echo "Build"; }
get_all_stages() { echo "[]"; }
get_failed_stage() { echo ""; }
fetch_test_results() { echo ""; }

JOB_NAME="test-repo"
cmd_status -f --prior-jobs 0 "$@"
WRAPPER_END

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Run in once mode to exercise follow path without external process control.
    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=1 2>&1"
    assert_failure

    # Verify follow mode entered once mode path.
    assert_output --partial "Follow mode enabled (once, timeout=1s)"

    # Verify the cleanup handler function exists in buildgit
    grep -q "_follow_mode_cleanup" "${PROJECT_DIR}/buildgit"
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode displays each build result
# Spec: buildgit status -f displays result for each build
# -----------------------------------------------------------------------------
@test "follow_displays_results" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build in-progress: completes after 2 polls
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"
    assert_success

    # Should show build information
    [[ "$output" == *"Build"* ]] || [[ "$output" == *"#42"* ]] || [[ "$output" == *"SUCCESS"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode with -f short option
# Spec: "-f, --follow"
# -----------------------------------------------------------------------------
@test "follow_short_option_works" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "false" "SUCCESS" "1"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=1 2>&1"
    assert_failure

    # Should enter follow mode (shows waiting message or build status)
    assert_output --partial "no new build detected for 1 seconds"
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode with --follow long option
# Spec: "-f, --follow"
# -----------------------------------------------------------------------------
@test "follow_long_option_works" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR

    # Create wrapper that uses --follow instead of -f
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=30

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() { echo "Started by user testuser"; }
get_current_stage() { echo "Build"; }
get_all_stages() { echo "[]"; }
get_failed_stage() { echo ""; }
fetch_test_results() { echo ""; }

JOB_NAME="test-repo"
cmd_status --follow --prior-jobs 0 "$@"
WRAPPER

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=1 2>&1"
    assert_failure

    # Should enter follow mode
    assert_output --partial "no new build detected for 1 seconds"
}

# =============================================================================
# Test Cases: Completed Build Header Display (bug-status-f-missing-header-spec)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Follow mode shows full header for completed SUCCESS build
# Spec: bug-status-f-missing-header-spec.md - completed builds show header
# -----------------------------------------------------------------------------
@test "follow_completed_success_shows_header" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build in-progress (building=true), result=SUCCESS, completes after 2 polls
    # Tests that follow mode shows header after monitoring an in-progress build
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"
    assert_success

    # Monitoring path shows BUILD IN PROGRESS banner followed by Finished line
    [[ "$output" == *"BUILD IN PROGRESS"* ]]

    # Should show build metadata
    [[ "$output" == *"Job:"* ]]
    [[ "$output" == *"Build:"*"#42"* ]]
    [[ "$output" == *"Status:"* ]]
    [[ "$output" == *"Trigger:"* ]]

    # Should show Finished line
    [[ "$output" == *"Finished: SUCCESS"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode shows full header for completed FAILURE build
# Spec: bug-status-f-missing-header-spec.md - completed builds show header
# -----------------------------------------------------------------------------
@test "follow_completed_failure_shows_header" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build in-progress (building=true), result=FAILURE, completes after 2 polls
    create_follow_test_wrapper "true" "FAILURE" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"
    assert_failure

    # Monitoring path shows BUILD IN PROGRESS banner followed by Finished line
    [[ "$output" == *"BUILD IN PROGRESS"* ]]

    # Should show build metadata
    [[ "$output" == *"Job:"* ]]
    [[ "$output" == *"Build:"*"#42"* ]]
    [[ "$output" == *"Status:"* ]]
    [[ "$output" == *"Trigger:"* ]]

    # Should show Finished line
    [[ "$output" == *"Finished: FAILURE"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode does not duplicate Finished line for completed builds
# Spec: bug-status-f-missing-header-spec.md - no duplicate output
# -----------------------------------------------------------------------------
@test "follow_completed_build_no_duplicate_finished" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"
    assert_success

    # Count occurrences of "Finished: SUCCESS" - should appear exactly once
    local count
    count=$(echo "$output" | grep -c "Finished: SUCCESS" || true)
    [[ "$count" -eq 1 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode shows console URL for completed builds
# Spec: bug-status-f-missing-header-spec.md - header includes console URL
# -----------------------------------------------------------------------------
@test "follow_completed_build_shows_console_url" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"
    assert_success

    # Should show console URL
    [[ "$output" == *"Console:"*"console"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode with --once exits after first completed build
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "follow_once_completed_build_exits_without_waiting" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build in-progress: --once monitors it and exits when done (no indefinite wait)
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"

    assert_success
    refute_output --partial "Waiting for next build"
    refute_output --partial "Press Ctrl+C to stop monitoring"
    assert_output --partial "Finished: SUCCESS"
}

# -----------------------------------------------------------------------------
# Test Case: --once without -f is rejected
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_once_requires_follow" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status --once

    assert_failure
    assert_output --partial "Error: --once requires --follow (-f)"
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode with --once returns non-zero for failed build
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "follow_once_exit_code_failure" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "FAILURE" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"

    assert_failure
    assert_output --partial "Finished: FAILURE"
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode with --once and --json outputs JSON and exits
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "follow_once_json_outputs_json" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once --json 2>&1"

    assert_success
    assert_output --partial '"status": "SUCCESS"'
    assert_output --partial '"number": 42'
}

# -----------------------------------------------------------------------------
# Test Case: --once exits 0 when build result is SUCCESS
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_once_exit_code_success" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"

    assert_success
    assert_output --partial "Finished: SUCCESS"
}

# -----------------------------------------------------------------------------
# Test Case: When no build starts within timeout, exits with error code 2
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_once_timeout" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build 42 is already completed; get_last_build_number always returns 42
    # so _follow_wait_for_new_build_timeout will never find a new build
    create_follow_test_wrapper "false" "SUCCESS" "0"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=1 2>&1"

    assert_failure
    assert_output --partial "no new build detected for 1 seconds"
}

# -----------------------------------------------------------------------------
# Test Case: --once=20 monitors a build and exits when complete
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_once_custom_timeout" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build in-progress; --once=20 gives plenty of time, exits when build completes
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=20 2>&1"

    assert_success
    assert_output --partial "Finished: SUCCESS"
}

# -----------------------------------------------------------------------------
# Test Case: --once=<invalid> produces usage error
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_once_invalid_timeout" {
    run "${PROJECT_DIR}/buildgit" status -f --once=abc

    assert_failure
    assert_output --partial "--once value must be a non-negative integer"

    run "${PROJECT_DIR}/buildgit" status -f --once=-1

    assert_failure
    assert_output --partial "--once value must be a non-negative integer"
}

# -----------------------------------------------------------------------------
# Test Case: status -f with no running build does NOT display prior completed build
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_no_stale_replay" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build 42 is already completed; follow mode should NOT replay it
    create_follow_test_wrapper "false" "SUCCESS" "0"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=1 2>&1"
    assert_failure

    # Stale build 42 should NOT be displayed
    [[ "$output" != *"BUILD SUCCESSFUL"* ]] || {
        echo "FAIL: stale build was replayed: $output" >&2
        return 1
    }

    # Timeout confirms we waited for a new build instead of replaying stale output.
    assert_output --partial "no new build detected"
}

# -----------------------------------------------------------------------------
# Test Case: status -f --once with no running build does NOT display prior build
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_once_no_stale_replay" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Build 42 is already completed; --once=1 should time out (not display stale build)
    create_follow_test_wrapper "false" "SUCCESS" "0"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once=1 2>&1"

    assert_failure
    # Timeout error should appear
    assert_output --partial "no new build detected"
    # Stale build output must NOT appear
    refute_output --partial "BUILD SUCCESSFUL"
}

# -----------------------------------------------------------------------------
# Test Case: Info message shows (once, timeout=Ns) and omits "Press Ctrl+C"
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_once_info_message" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once 2>&1"

    assert_success
    assert_output --partial "once, timeout=10s"
    refute_output --partial "Press Ctrl+C"
}

# -----------------------------------------------------------------------------
# Test Case: -n 2 -f displays 2 prior completed builds then follows
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_n_prior_builds" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Latest build is 42 (completed); builds 41 and 42 are available as prior
    create_follow_n_prior_wrapper "42" "false"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" -n 2 --once=1 2>&1"
    assert_failure

    # Both prior builds should be displayed (41=FAILURE, 42=SUCCESS)
    [[ "$output" == *"BUILD FAILED"* ]]
    [[ "$output" == *"BUILD SUCCESSFUL"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: -n 2 -f --once displays 2 prior builds then applies timeout
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_n_once_prior_builds" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Latest build is 42 (completed); builds 41 and 42 shown, then timeout
    create_follow_n_prior_wrapper "42" "false"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" -n 2 --once=1 2>&1"

    assert_failure
    # Prior builds should have been displayed
    assert_output --partial "BUILD FAILED"
    assert_output --partial "BUILD SUCCESSFUL"
    # Timeout error should also appear
    assert_output --partial "no new build detected"
}

# -----------------------------------------------------------------------------
# Test Case: In-progress build does not count toward -n prior builds
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_n_inprogress_not_counted" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Latest build is 43 (in-progress); -n 2 should show 42 and 41, NOT 43
    create_follow_n_prior_wrapper "43" "true"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" -n 2 --once=20 2>&1"
    assert_success

    # Build 41 (FAILURE) should be shown — proves 43 was skipped and we went back to 41
    [[ "$output" == *"BUILD FAILED"* ]]
    # Build 42 (SUCCESS) should also be shown as prior
    [[ "$output" == *"BUILD SUCCESSFUL"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: -n prior builds are shown BEFORE --once timeout countdown begins
# Spec: 2026-02-16_add-once-flag-to-status-f-spec.md
# -----------------------------------------------------------------------------
@test "status_follow_n_prior_before_timeout" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    # Latest build is 42 (completed); --once=0 exits immediately after prior builds
    create_follow_n_prior_wrapper "42" "false"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" -n 2 --once=0 2>&1"

    assert_failure
    # Prior builds MUST appear (displayed before timeout countdown)
    assert_output --partial "BUILD FAILED"
    assert_output --partial "BUILD SUCCESSFUL"
    # Immediate timeout (0 seconds)
    assert_output --partial "no new build detected for 0 seconds"
}

@test "status_follow_line_completed_output" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --once 2>&1"

    assert_success
    assert_output --partial "SUCCESS"
    assert_output --regexp "#42 id=[[:alnum:]]{7}"
    assert_output --partial "Tests=?/?/? Took"
}

@test "status_follow_line_once_exit_code_failure" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "FAILURE" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --once 2>&1"

    assert_failure
    assert_output --partial "FAILURE"
    assert_output --regexp "#42 id=[[:alnum:]]{7}"
}

@test "status_follow_line_non_tty" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --once 2>&1"

    assert_success
    refute_output --partial "IN_PROGRESS #42 id="
    assert_output --partial "SUCCESS"
}

@test "status_follow_threads_non_tty_ignored" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --threads --once 2>&1"

    assert_success
    refute_output --partial "[agent"
    assert_output --partial "SUCCESS"
}

@test "status_follow_full_mode_tty_keeps_full_completion_output" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    cat > "${TEST_TEMP_DIR}/follow_footer_probe.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=30
MONITOR_SETTLE_STABLE_POLLS=1

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        echo '{"duration":120000}'
        return 0
    fi
    echo ""
    return 1
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_info_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_info_calls"
    if [[ $count -le 2 ]]; then
        echo '{"number":42,"result":"null","building":true,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    fi
}
get_all_stages() { echo "[]"; }
fetch_test_results() { echo ""; }
get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}
get_current_stage() { echo "Build"; }
_status_stdout_is_tty() { return 0; }

_display_follow_line_progress() {
    echo "__STICKY_FOOTER__ $1 $2"
}
_clear_follow_line_progress() {
    echo "__STICKY_CLEAR__"
}

JOB_NAME="test-repo"
cmd_status -f --once --prior-jobs 0
WRAPPER_END
    chmod +x "${TEST_TEMP_DIR}/follow_footer_probe.sh"

    run bash -c "BUILDGIT_FORCE_TTY=1 bash \"${TEST_TEMP_DIR}/follow_footer_probe.sh\" 2>&1"

    assert_success
    assert_output --partial "BUILD IN PROGRESS"
    assert_output --partial "Finished: SUCCESS"
    refute_output --partial "Tests=?/?/? Took"
}

@test "status_follow_settle_loop_prints_late_stage_before_exit" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "1"

    cat > "${TEST_TEMP_DIR}/follow_settle_stage_probe.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=15
MONITOR_SETTLE_STABLE_POLLS=1
MONITOR_SETTLE_MAX_SECONDS=3

echo "0" > "${TEST_TEMP_DIR}/track_calls"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        echo '{"duration":120000}'
        return 0
    fi
    echo ""
    return 1
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_info_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_info_calls"
    if [[ $count -le 1 ]]; then
        echo '{"number":42,"result":"null","building":true,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    fi
}
get_all_stages() { echo "[]"; }
fetch_test_results() { echo ""; }
get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}
get_current_stage() { echo "Build"; }

_track_nested_stage_changes() {
    local job_name="$1"
    local build_number="$2"
    local previous_state="${3:-[]}"

    local count
    count=$(cat "${TEST_TEMP_DIR}/track_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/track_calls"

    if [[ $count -eq 1 ]]; then
        jq -n '{nested: [], printed: {}, parallel_state: {}, tracking_complete: false}'
    elif [[ $count -eq 2 ]]; then
        echo "[12:34:56] ℹ   Stage: [agent7        ] Deploy (3s)" >&2
        jq -n '{
            nested: [{name: "Deploy", status: "SUCCESS", durationMillis: 3000, agent: "agent7", nesting_depth: 0}],
            printed: {Deploy: {terminal: true}},
            parallel_state: {},
            tracking_complete: true
        }'
    else
        jq -n '{
            nested: [{name: "Deploy", status: "SUCCESS", durationMillis: 3000, agent: "agent7", nesting_depth: 0}],
            printed: {Deploy: {terminal: true}},
            parallel_state: {},
            tracking_complete: true
        }'
    fi
}

JOB_NAME="test-repo"
cmd_status -f --once --prior-jobs 0
WRAPPER_END
    chmod +x "${TEST_TEMP_DIR}/follow_settle_stage_probe.sh"

    run bash -c "bash \"${TEST_TEMP_DIR}/follow_settle_stage_probe.sh\" 2>&1"

    assert_success
    assert_output --partial "Stage: [agent7        ] Deploy (3s)"
    assert_output --partial "Finished: SUCCESS"
}

@test "status_follow_completion_stage_lines_match_tty_and_non_tty_output" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR

    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    echo "0" > "${TEST_TEMP_DIR}/build_info_calls"
    echo "0" > "${TEST_TEMP_DIR}/track_calls"

    cat > "${TEST_TEMP_DIR}/follow_completion_stage_wrapper.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=15
MONITOR_SETTLE_STABLE_POLLS=1
MONITOR_SETTLE_MAX_SECONDS=1

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        echo '{"duration":120000}'
        return 0
    fi
    echo ""
    return 1
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_info_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_info_calls"
    if [[ $count -le 1 ]]; then
        echo '{"number":42,"result":"null","building":true,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    fi
}
get_all_stages() { echo "[]"; }
fetch_test_results() { echo ""; }
get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}
get_current_stage() { echo "Build"; }
_display_follow_line_progress() { :; }
_clear_follow_line_progress() { :; }

_track_nested_stage_changes() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/track_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/track_calls"

    if [[ $count -eq 1 ]]; then
        jq -n '{nested: [], printed: {}, parallel_state: {}, tracking_complete: false}'
    elif [[ $count -eq 2 ]]; then
        echo "[12:34:56] ℹ   Stage: Deploy (3s)" >&2
        jq -n '{
            nested: [{name: "Deploy", status: "SUCCESS", durationMillis: 3000, nesting_depth: 0}],
            printed: {Deploy: {terminal: true}},
            parallel_state: {},
            tracking_complete: true
        }'
    else
        jq -n '{
            nested: [{name: "Deploy", status: "SUCCESS", durationMillis: 3000, nesting_depth: 0}],
            printed: {Deploy: {terminal: true}},
            parallel_state: {},
            tracking_complete: true
        }'
    fi
}

JOB_NAME="test-repo"
cmd_status -f --once --prior-jobs 0
WRAPPER_END
    chmod +x "${TEST_TEMP_DIR}/follow_completion_stage_wrapper.sh"

    run bash -c "BUILDGIT_FORCE_TTY=1 bash \"${TEST_TEMP_DIR}/follow_completion_stage_wrapper.sh\" 2>&1"

    assert_success
    assert_output --partial "Stage: Deploy (3s)"
    assert_output --partial "Finished: SUCCESS"

    local tty_stage_count
    tty_stage_count=$(printf '%s\n' "$output" | grep -c "Stage: Deploy (3s)" || true)
    [ "$tty_stage_count" -eq 1 ]

    echo "0" > "${TEST_TEMP_DIR}/build_info_calls"
    echo "0" > "${TEST_TEMP_DIR}/track_calls"

    run bash -c "bash \"${TEST_TEMP_DIR}/follow_completion_stage_wrapper.sh\" 2>&1"

    assert_success
    assert_output --partial "Stage: Deploy (3s)"
    assert_output --partial "Finished: SUCCESS"

    local non_tty_stage_count
    non_tty_stage_count=$(printf '%s\n' "$output" | grep -c "Stage: Deploy (3s)" || true)
    [ "$non_tty_stage_count" -eq 1 ]
}

@test "status_follow_completion_force_flushes_missing_terminal_stages" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "1"

    cat > "${TEST_TEMP_DIR}/follow_force_flush_probe.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=15
MONITOR_SETTLE_STABLE_POLLS=1
MONITOR_SETTLE_MAX_SECONDS=2

echo "0" > "${TEST_TEMP_DIR}/flush_calls"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        echo '{"duration":120000}'
        return 0
    fi
    echo ""
    return 1
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_info_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_info_calls"
    if [[ $count -le 1 ]]; then
        echo '{"number":42,"result":"null","building":true,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    fi
}
get_all_stages() { echo '[{"name":"Build","status":"SUCCESS","durationMillis":3000},{"name":"Deploy","status":"SUCCESS","durationMillis":3000}]'; }
fetch_test_results() { echo ""; }
get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}
get_current_stage() { echo "Build"; }

_track_nested_stage_changes() {
    jq -n '{
        parent: [{name: "Build", status: "SUCCESS", durationMillis: 3000}, {name: "Deploy", status: "SUCCESS", durationMillis: 3000}],
        nested: [{name: "Build", status: "SUCCESS", durationMillis: 3000, agent: "agent1", nesting_depth: 0}],
        printed: {Build: {terminal: true}},
        parallel_state: {},
        tracking_complete: false
    }'
}

_force_flush_completion_stages() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/flush_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/flush_calls"
    echo "[12:34:56] ℹ   Stage: Deploy (3s)" >&2
    jq -n '{
        parent: [{name: "Build", status: "SUCCESS", durationMillis: 3000}, {name: "Deploy", status: "SUCCESS", durationMillis: 3000}],
        nested: [
            {name: "Build", status: "SUCCESS", durationMillis: 3000, agent: "agent1", nesting_depth: 0},
            {name: "Deploy", status: "SUCCESS", durationMillis: 3000, agent: "agent7", nesting_depth: 0}
        ],
        printed: {Build: {terminal: true}, Deploy: {terminal: true}},
        parallel_state: {},
        tracking_complete: true
    }'
}

JOB_NAME="test-repo"
cmd_status -f --once --prior-jobs 0
WRAPPER_END
    chmod +x "${TEST_TEMP_DIR}/follow_force_flush_probe.sh"

    run bash -c "bash \"${TEST_TEMP_DIR}/follow_force_flush_probe.sh\" 2>&1"

    assert_success
    assert_output --partial "Stage: Deploy (3s)"
    assert_output --partial "Finished: SUCCESS"
}

@test "status_follow_settle_loop_ignores_counter_only_parallel_state_changes" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "1"

    cat > "${TEST_TEMP_DIR}/follow_settle_counter_probe.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
MAX_BUILD_TIME=15
MONITOR_SETTLE_STABLE_POLLS=1
MONITOR_SETTLE_MAX_SECONDS=5

echo "0" > "${TEST_TEMP_DIR}/track_calls"

sleep() { :; }

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        echo '{"duration":120000}'
        return 0
    fi
    echo ""
    return 1
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_info_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_info_calls"
    if [[ $count -le 1 ]]; then
        echo '{"number":42,"result":"null","building":true,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    fi
}
get_all_stages() {
    echo '[{"name":"Build","status":"SUCCESS","durationMillis":3000},{"name":"Deploy","status":"SUCCESS","durationMillis":3000}]'
}
fetch_test_results() { echo ""; }
get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}
get_current_stage() { echo "Build"; }

_track_nested_stage_changes() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/track_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/track_calls"

    if [[ $count -eq 1 ]]; then
        jq -n '{
            parent: [{name: "Build", status: "SUCCESS", durationMillis: 3000}, {name: "Deploy", status: "SUCCESS", durationMillis: 3000}],
            nested: [{name: "Build", status: "SUCCESS", durationMillis: 3000, agent: "agent1", nesting_depth: 0}],
            printed: {Build: {terminal: true}},
            parallel_state: {UnitTests: {stable_polls: 1, wrapper_stable_polls: 1, branch_state: {A: {stable_polls: 1, ready_to_print: false}}}},
            tracking_complete: false
        }'
    else
        jq -n --argjson count "$count" '{
            parent: [{name: "Build", status: "SUCCESS", durationMillis: 3000}, {name: "Deploy", status: "SUCCESS", durationMillis: 3000}],
            nested: [
                {name: "Build", status: "SUCCESS", durationMillis: 3000, agent: "agent1", nesting_depth: 0},
                {name: "Deploy", status: "SUCCESS", durationMillis: 3000, agent: "agent7", nesting_depth: 0}
            ],
            printed: {Build: {terminal: true}, Deploy: {terminal: true}},
            parallel_state: {UnitTests: {stable_polls: $count, wrapper_stable_polls: $count, branch_state: {A: {stable_polls: $count, ready_to_print: true}}}},
            tracking_complete: true
        }'
    fi
}

JOB_NAME="test-repo"
cmd_status -f --once --prior-jobs 0
echo "TRACK_CALLS=$(cat "${TEST_TEMP_DIR}/track_calls")"
WRAPPER_END
    chmod +x "${TEST_TEMP_DIR}/follow_settle_counter_probe.sh"

    run bash -c "bash \"${TEST_TEMP_DIR}/follow_settle_counter_probe.sh\" 2>&1"

    assert_success
    assert_output --partial "Finished: SUCCESS"
    assert_output --partial "TRACK_CALLS=4"
}

@test "status_follow_line_n_prior_builds" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_n_prior_wrapper "42" "false"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" -n 3 --line --once=0 2>&1"

    assert_failure
    assert_output --regexp "#40 id=[[:alnum:]]{7}"
    assert_output --regexp "#41 id=[[:alnum:]]{7}"
    assert_output --regexp "#42 id=[[:alnum:]]{7}"
    refute_output --partial "BUILD FAILED"
}

@test "status_follow_line_rejects_json" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status -f --line --json

    assert_failure
    assert_output --partial "Cannot use --line with --json"
}

@test "status_follow_line_rejects_all" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status -f --line --all

    assert_failure
    assert_output --partial "Cannot use --line with --all"
}

@test "status_follow_line_progress_bar_format" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" determinate

    assert_success
    assert_output --partial "IN_PROGRESS Job ralph1 #42 [======>             ] 35% 35s / ~1m 40s"
}

@test "status_follow_line_estimate_from_last_success" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" estimate

    assert_success
    assert_output "250000"
}

@test "status_follow_line_no_prior_success" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash -c "MOCK_LAST_SUCCESS_KIND=none bash \"${TEST_TEMP_DIR}/follow_line_progress.sh\" estimate"

    assert_success
    assert_output ""

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" unknown
    assert_success
    assert_output --partial "~unknown"
    refute_output --partial "%"
}

@test "status_follow_line_over_estimate" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" over

    assert_success
    assert_output --partial "[====================] 150% 3m 0s / ~2m 0s"
}

@test "status_follow_line_multi_build_two_bars" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" two_builds

    assert_success
    assert_output --partial "IN_PROGRESS Job ralph1 #42 ["
    assert_output --partial "IN_PROGRESS Job ralph1 #43 ["
}

@test "status_follow_line_primary_build_stays_first" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" mixed_order

    assert_success
    local before_primary before_secondary
    before_primary="${output%%IN_PROGRESS Job ralph1 #43*}"
    before_secondary="${output%%IN_PROGRESS Job ralph1 #42*}"
    [[ ${#before_primary} -lt ${#before_secondary} ]]
}

@test "status_follow_line_queue_bar_includes_elapsed_and_estimate" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" queued

    assert_success
    assert_output --partial "QUEUED      Job ralph1 #44 ["
    assert_output --partial "35s in queue / ~1m 40s"
}

@test "status_follow_threads_single_stage_line_renders_above_primary_bar" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" threads_single

    assert_success
    assert_output --partial "  [agent6 guthrie] Build [====================] 875% 35s / ~4s"
    assert_output --partial "IN_PROGRESS Job ralph1 #42 [=>                  ] 14% 35s / ~4m 10s"
}

@test "status_follow_threads_parallel_stage_lines_follow_pipeline_order" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" threads_parallel

    assert_success
    assert_output --partial "  [agent6 guthrie] Unit Tests A [============>       ] 65% 1m 30s / ~2m 18s"
    assert_output --partial "  [agent7 guthrie] Unit Tests B [=======>            ] 42% 38s / ~1m 29s"
    assert_output --partial "  [agent8 guthrie] Unit Tests C [==>                 ] 17% 22s / ~2m 6s"
    local before_a before_b before_c
    before_a="${output%%Unit Tests A*}"
    before_b="${output%%Unit Tests B*}"
    before_c="${output%%Unit Tests C*}"
    [[ ${#before_a} -lt ${#before_b} ]]
    [[ ${#before_b} -lt ${#before_c} ]]
}

@test "status_follow_threads_synthesizes_missing_parallel_branches_when_wfapi_lags" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" threads_parallel_lagged

    assert_success
    assert_output --partial "Unit Tests A"
    assert_output --partial "Unit Tests B"
    assert_output --partial "Unit Tests C"
    assert_output --partial "Unit Tests D"
    refute_output --partial "Unit Tests A [>                   ] 0% 0s"
    refute_output --partial "Unit Tests C [>                   ] 0% 0s"
    refute_output --partial "Unit Tests D [>                   ] 0% 0s"
    refute_output --partial "  [agent6 guthrie] Unit Tests ["
}

@test "status_follow_threads_wrapper_stage_uses_pipeline_scope_agent_for_synthetic_branches" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" active_wrapper_agent_fallback

    assert_success
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build Handle") | .agent')" == "orchestrator1" ]]
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build SignalBoot") | .agent')" == "orchestrator1" ]]
}

@test "status_follow_threads_wrapper_stage_assigns_agents_to_both_parallel_branches" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" active_wrapper_agent_fallback

    assert_success
    [[ "$(echo "$output" | jq '[.[] | select(.synthetic_parallel_branch == true and (.agent // "") != "")] | length')" == "2" ]]
}

@test "status_follow_threads_downstream_stages_keep_downstream_agents_when_wrapper_is_synthesized" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" active_wrapper_agent_fallback

    assert_success
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build Handle->Compile") | .agent')" == "agent8_sixcore" ]]
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build SignalBoot->System Diagnostics") | .agent')" == "agent7 guthrie" ]]
}

@test "status_follow_threads_wrapper_stage_gracefully_degrades_without_console_output" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" active_wrapper_agent_no_console

    assert_success
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build Handle") | .agent')" == "" ]]
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build SignalBoot") | .agent')" == "" ]]
}

@test "status_follow_threads_wrapper_stage_gracefully_degrades_without_pipeline_scope_agent" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" active_wrapper_agent_no_pipeline_scope

    assert_success
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build Handle") | .agent')" == "" ]]
    [[ "$(echo "$output" | jq -r '.[] | select(.name == "Build SignalBoot") | .agent')" == "" ]]
}

@test "status_follow_threads_wrapper_stage_render_uses_orchestrator_agent" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" threads_wrapper_agent_fallback

    assert_success
    assert_output --partial "  [orchestrator1 ] Build Handle ["
    assert_output --partial "  [orchestrator1 ] Build SignalBoot ["
    assert_output --partial "  [agent8_sixcore] Build Handle->Compile ["
    assert_output --partial "  [agent7 guthrie] Build SignalBoot->Sy..."
}

@test "status_follow_threads_unknown_stage_uses_indeterminate_bar" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" threads_unknown

    assert_success
    assert_output --partial "  [agent6 guthrie] Brand New Stage [   <===>            ] 12s / ~unknown"
    refute_output --partial "Brand New Stage [   <===>            ] 12%"
}

@test "status_follow_threads_overflow_limits_stage_lines" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" threads_overflow

    assert_success
    assert_output --partial "Stage 7"
    refute_output --partial "Stage 8"
}

@test "status_follow_threads_truncates_stage_name_to_terminal_width" {
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_line_progress_wrapper
    export TEST_TEMP_DIR

    run bash "${TEST_TEMP_DIR}/follow_line_progress.sh" threads_long_name

    assert_success
    assert_output --partial "A very lon..."
    refute_output --partial "should be truncated before the progress bar moves"
}

@test "status_follow_line_once_timeout" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "false" "SUCCESS" "0"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --once=1 2>&1"

    assert_failure
    assert_output --partial "no new build detected for 1 seconds"
}

@test "status_follow_preamble_shows_prior_jobs_and_estimate" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --once --prior-jobs 2 2>&1"

    assert_success
    assert_output --partial "Prior 2 Jobs"
    assert_output --partial "Estimated build time ="
    assert_output --partial "Starting"
}
