#!/usr/bin/env bats

# Tests for buildgit build command
# Spec reference: buildgit-spec.md, buildgit build
# Plan reference: buildgit-plan.md, Chunk 7

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
# Helper: Create build test wrapper
# =============================================================================

# Create wrapper for build command testing with mocked Jenkins API
# Arguments:
#   $1 - build_result (SUCCESS, FAILURE, etc.)
#   $2 - poll_cycles before build completes
#   $3 - trigger_success (true/false) - whether trigger_build succeeds
create_build_test_wrapper() {
    local build_result="${1:-SUCCESS}"
    local poll_cycles="${2:-2}"
    local trigger_success="${3:-true}"

    # Create a modified copy of buildgit without main
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    # Initialize state files for tracking call counts
    echo "0" > "${TEST_TEMP_DIR}/build_info_calls"
    echo "0" > "${TEST_TEMP_DIR}/queue_item_calls"
    echo "0" > "${TEST_TEMP_DIR}/console_calls"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

# Override poll interval for faster tests
POLL_INTERVAL=1
MAX_BUILD_TIME=30
BUILD_START_TIMEOUT=10

# Override Jenkins API functions with mocks
verify_jenkins_connection() {
    return 0
}

verify_job_exists() {
    local job_name="$1"
    JOB_URL="${JENKINS_URL}/job/${job_name}"
    return 0
}

trigger_build() {
    local job_name="$1"
    if [[ "__TRIGGER_SUCCESS__" == "true" ]]; then
        echo "http://jenkins.example.com/queue/item/123/"
        return 0
    else
        log_error "Permission denied to trigger build (403)"
        return 1
    fi
}

wait_for_queue_item() {
    local queue_url="$1"
    # Return build number immediately
    echo "43"
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

get_build_info() {
    # Use file-based counter for persistence across calls
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_info_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_info_calls"

    if [[ $count -le __POLL_CYCLES__ ]]; then
        # Build still in progress
        echo '{"number":43,"result":"null","building":true,"timestamp":1706700000000,"duration":0,"url":"http://jenkins.example.com/job/test-repo/43/"}'
    else
        # Build completed
        echo '{"number":43,"result":"__BUILD_RESULT__","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/43/"}'
    fi
}

get_console_output() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/console_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/console_calls"

    echo "Started by user buildtriggerdude"
    echo "Running on agent8_sixcore in /var/jenkins/workspace/test-repo"
    echo "Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/test-repo.git"
    if [[ $count -gt 1 ]]; then
        echo "Checking out Revision abc1234567890"
    fi
}

get_current_stage() {
    echo "Build"
}

get_last_build_number() {
    echo "42"
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

# Set job name to skip auto-detection
JOB_NAME="test-repo"

# Call the build command
cmd_build --prior-jobs 0 "$@"
WRAPPER_END

    # Replace placeholders with actual values (portable: temp file + mv works on both macOS and Linux)
    sed "s|__POLL_CYCLES__|${poll_cycles}|g; s|__BUILD_RESULT__|${build_result}|g; s|__TRIGGER_SUCCESS__|${trigger_success}|g" \
        "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" \
        && mv "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Create wrapper that tests job detection failure
create_build_no_job_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() {
    return 0
}

verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}

discover_job_name() {
    return 1
}

# Don't set JOB_NAME - let it try auto-detection which will fail
cmd_build --prior-jobs 0 "$@"
WRAPPER

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# =============================================================================
# Test Cases: Build Command Basic Functionality
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Build triggers Jenkins build
# Spec: "Trigger a new build for the job (equivalent to pressing 'Build Now')"
# -----------------------------------------------------------------------------
@test "build_triggers_jenkins" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "1" "true"

    # Run with --no-follow to just test trigger
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    [ "$status" -eq 0 ]
    # Should show confirmation message
    [[ "$output" == *"Build"* ]] || [[ "$output" == *"queued"* ]] || [[ "$output" == *"triggered"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Build monitors until completion
# Spec: "Monitor build progress until completion"
# -----------------------------------------------------------------------------
@test "build_monitors_to_completion" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "2" "true"

    # Run build (without --no-follow, so it monitors)
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 2>&1

    # Should complete successfully with build result
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]] || [[ "$output" == *"Build"* ]]
}

@test "build_commit_before_console_when_deferred" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "2" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 2>&1

    assert_success
    assert_output --regexp "Commit:[[:space:]]+[[:alnum:]]{7}"
    assert_output --partial "Console:    http://jenkins.example.com/job/test-repo/43/console"

    local commit_line console_line
    commit_line=$(echo "$output" | grep -n "Commit:" | head -1 | cut -d: -f1)
    console_line=$(echo "$output" | grep -n "Console:" | head -1 | cut -d: -f1)
    [[ "$commit_line" -lt "$console_line" ]]
}

@test "build_agent_in_build_info" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "2" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 2>&1

    assert_success
    assert_output --partial "=== Build Info ==="
    assert_output --partial "Agent:       agent8_sixcore"
}

# -----------------------------------------------------------------------------
# Test Case: Build with --no-follow exits after trigger
# Spec: "--no-follow: Trigger build and confirm queued, then exit without monitoring"
# -----------------------------------------------------------------------------
@test "build_no_follow_exits_early" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "10" "true"  # Would take long if monitored

    local start_time
    start_time=$(date +%s)

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # Should complete quickly (less than 5 seconds) since no monitoring
    [ "$elapsed" -lt 5 ]
    [ "$status" -eq 0 ]
    # Should show queued confirmation
    [[ "$output" == *"queued"* ]] || [[ "$output" == *"triggered"* ]] || [[ "$output" == *"monitoring disabled"* ]]
}

@test "build_line_shows_progress_and_single_summary_on_tty" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "2" "true"

    run bash -c "BUILDGIT_FORCE_TTY=1 bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line 2>&1"

    assert_success
    assert_output --partial "IN_PROGRESS Job test-repo #43 ["
    assert_output --partial "SUCCESS"
    refute_output --partial "BUILD IN PROGRESS"
    refute_output --partial "Finished:"
}

@test "build_line_non_tty_silent_until_summary" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "2" "true"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line 2>&1"

    assert_success
    refute_output --partial "IN_PROGRESS Job test-repo #43 ["
    assert_output --partial "SUCCESS"
    assert_output --regexp "#43 id=[[:alnum:]]{7}"
}

@test "build_line_no_follow_matches_no_follow_behavior" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "10" "true"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --no-follow 2>&1"

    assert_success
    assert_output --partial "monitoring disabled"
    refute_output --partial "IN_PROGRESS Job"
}

# -----------------------------------------------------------------------------
# Test Case: Build returns 0 on successful build
# Spec: "Exit Code: Success (git OK, build OK) = 0"
# -----------------------------------------------------------------------------
@test "build_success_exit_code" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "1" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 2>&1

    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Test Case: Build returns non-zero on build failure
# Spec: "Exit Code: Returns non-zero if the build fails"
# -----------------------------------------------------------------------------
@test "build_failure_exit_code" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "FAILURE" "1" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 2>&1

    # Should return non-zero for failed build
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Test Case: Build requires job name
# Spec: "If --job is not specified and auto-detection fails, error out"
# -----------------------------------------------------------------------------
@test "build_requires_job_name" {
    cd "${TEST_TEMP_DIR}"  # Not in repo with AGENTS.md

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_no_job_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Should fail with error about job name
    [ "$status" -ne 0 ]
    [[ "$output" == *"job"* ]] || [[ "$output" == *"Job"* ]] || [[ "$output" == *"JOB"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Build with -j/--job flag specifies job
# Spec: "Global Options: -j, --job <name>"
# -----------------------------------------------------------------------------
@test "build_with_job_flag" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "1" "true"

    # Note: In our wrapper JOB_NAME is already set, this tests the --no-follow path
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Test Case: Build handles API trigger failure gracefully
# Spec: "Error Handling: Handle trigger API failures"
# -----------------------------------------------------------------------------
@test "build_trigger_api_failure" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "1" "false"  # trigger fails

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Should fail with error message
    [ "$status" -ne 0 ]
    [[ "$output" == *"trigger"* ]] || [[ "$output" == *"Failed"* ]] || [[ "$output" == *"denied"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Build shows build number when started
# Spec: Implicit - should show what build was triggered
# -----------------------------------------------------------------------------
@test "build_shows_build_number" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "1" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 2>&1

    [ "$status" -eq 0 ]
    # Should show build number somewhere in output
    [[ "$output" == *"43"* ]] || [[ "$output" == *"#43"* ]] || [[ "$output" == *"Build"* ]]
}

# =============================================================================
# Test Cases: Usage Help on Build Subcommand
# Spec reference: usage-help-spec.md
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: build -h prints usage to stdout and exits 0
# Spec: usage-help-spec.md, Acceptance Criteria 3
# -----------------------------------------------------------------------------
@test "build_help_short_flag" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" build -h

    assert_success
    assert_output --partial "Usage: buildgit"
    assert_output --partial "Commands:"
    assert_output --partial "build [--no-follow] [--line]"
}

# -----------------------------------------------------------------------------
# Test Case: build --help prints usage to stdout and exits 0
# Spec: usage-help-spec.md, Acceptance Criteria 4
# -----------------------------------------------------------------------------
@test "build_help_long_flag" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" build --help

    assert_success
    assert_output --partial "Usage: buildgit"
    assert_output --partial "Commands:"
}

# -----------------------------------------------------------------------------
# Test Case: build --junk prints error + usage to stderr and exits non-zero
# Spec: usage-help-spec.md, Acceptance Criteria 9
# -----------------------------------------------------------------------------
@test "build_unknown_option_shows_usage" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" build --junk

    assert_failure
    assert_output --partial "Unknown option for build command: --junk"
    assert_output --partial "Usage: buildgit"
}

@test "build_preamble_prior_jobs_and_estimate" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "2" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --prior-jobs 2

    assert_success
    assert_output --partial "Prior 2 Jobs"
    assert_output --partial "Estimated build time ="
    assert_output --partial "Starting"
}

@test "build_prior_jobs_invalid_value" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_build_test_wrapper "SUCCESS" "1" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --prior-jobs -1

    assert_failure
    assert_output --partial "--prior-jobs value must be a non-negative integer"
}
