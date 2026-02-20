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

# Call the status command with follow mode
cmd_status -f "$@"
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
            echo '{"duration":250000}'
        fi
        return 0
    fi
    echo ""
    return 1
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
cmd_status -f "$@"
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
cmd_status -f "$@"
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
cmd_status -f "$@"
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
cmd_status --follow "$@"
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
    assert_output --partial "Job test-repo #42"
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
    assert_output --partial "Job test-repo #42"
}

@test "status_follow_line_non_tty" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "true" "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --once 2>&1"

    assert_success
    refute_output --partial "IN_PROGRESS Job test-repo #42 ["
    assert_output --partial "SUCCESS"
}

@test "status_follow_line_n_prior_builds" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_n_prior_wrapper "42" "false"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" -n 3 --line --once=0 2>&1"

    assert_failure
    assert_output --partial "Job test-repo #40"
    assert_output --partial "Job test-repo #41"
    assert_output --partial "Job test-repo #42"
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

@test "status_follow_line_once_timeout" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_follow_test_wrapper "false" "SUCCESS" "0"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --once=1 2>&1"

    assert_failure
    assert_output --partial "no new build detected for 1 seconds"
}
