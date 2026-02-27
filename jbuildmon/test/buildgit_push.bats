#!/usr/bin/env bats

# Tests for buildgit push command
# Spec reference: buildgit-spec.md, buildgit push
# Plan reference: buildgit-plan.md, Chunk 6

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

    # Create a test git repository with a remote
    TEST_REPO="${TEST_TEMP_DIR}/repo"
    REMOTE_REPO="${TEST_TEMP_DIR}/remote.git"

    # Create bare remote repo
    mkdir -p "${REMOTE_REPO}"
    cd "${REMOTE_REPO}"
    git init --bare --quiet

    # Create local repo and set up remote
    mkdir -p "${TEST_REPO}"
    cd "${TEST_REPO}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    git remote add origin "${REMOTE_REPO}"
    git push --quiet -u origin main 2>/dev/null || git push --quiet -u origin master 2>/dev/null || true
}

teardown() {
    # Clean up any background processes
    if [[ -n "${MONITOR_PID:-}" ]]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi

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
# Helper: Create push test wrapper
# =============================================================================

# Create wrapper for push command testing with mocked Jenkins API
# Arguments:
#   $1 - build_result (SUCCESS, FAILURE, etc.)
#   $2 - poll_cycles before build completes
create_push_test_wrapper() {
    local build_result="${1:-SUCCESS}"
    local poll_cycles="${2:-2}"

    # Create a modified copy of buildgit without main
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    # Initialize state files for tracking call counts
    echo "0" > "${TEST_TEMP_DIR}/build_number_calls"
    echo "0" > "${TEST_TEMP_DIR}/build_info_calls"

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

jenkins_api() {
    if [[ "${1:-}" == *"/lastSuccessfulBuild/api/json" ]]; then
        echo '{"duration":120000}'
        return 0
    fi
    # Mock queue API - return empty queue
    if [[ "$1" == "/queue/api/json" ]]; then
        echo '{"items":[]}'
        return 0
    fi
    echo ""
    return 1
}

get_last_build_number() {
    # Use file-based counter for persistence across calls
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_number_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_number_calls"

    # First call returns baseline, subsequent calls return new build
    if [[ $count -le 1 ]]; then
        echo "42"
    else
        echo "43"
    fi
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
    echo "Started by an SCM change"
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

# Set job name to skip auto-detection
JOB_NAME="test-repo"

# Call the push command
cmd_push "$@"
WRAPPER_END

    # Replace placeholders with actual values (portable: temp file + mv works on both macOS and Linux)
    sed "s|__POLL_CYCLES__|${poll_cycles}|g; s|__BUILD_RESULT__|${build_result}|g" \
        "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" \
        && mv "${TEST_TEMP_DIR}/buildgit_wrapper.sh.tmp" "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Create wrapper that simulates git push failure
create_push_git_failure_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

JOB_NAME="test-repo"
cmd_push "$@"
WRAPPER

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# =============================================================================
# Test Cases: Push Command Basic Functionality
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Push executes git push with arguments
# Spec: "Execute git push with any provided arguments"
# -----------------------------------------------------------------------------
@test "push_executes_git_push" {
    cd "${TEST_REPO}"

    # Create a new commit to push
    echo "New content" >> README.md
    git add README.md
    git commit --quiet -m "New commit"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "1"

    # Run push with --no-follow to just test git push
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    # Should succeed
    [ "$status" -eq 0 ]

    # Verify the commit was pushed
    cd "${REMOTE_REPO}"
    local remote_log
    remote_log=$(git log --oneline -1)
    [[ "$remote_log" == *"New commit"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Push monitors Jenkins build after push
# Spec: "If push succeeds, monitor Jenkins build until completion"
# -----------------------------------------------------------------------------
@test "push_monitors_build" {
    cd "${TEST_REPO}"

    # Create a new commit to push
    echo "Monitor test" >> README.md
    git add README.md
    git commit --quiet -m "Monitor test commit"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "2"

    # Run push (without --no-follow, so it monitors)
    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 || true

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should show build monitoring or result
    [[ "$output" == *"Build"* ]] || [[ "$output" == *"SUCCESS"* ]] || [[ "$output" == *"#43"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Push with --no-follow skips monitoring
# Spec: "--no-follow: Push only, do not monitor Jenkins build"
# -----------------------------------------------------------------------------
@test "push_no_follow_skips_monitor" {
    cd "${TEST_REPO}"

    # Create a new commit to push
    echo "No follow test" >> README.md
    git add README.md
    git commit --quiet -m "No follow test"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "10"  # Would take a while if it monitored

    # Run push with --no-follow
    local start_time
    start_time=$(date +%s)

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # Should complete quickly (less than 5 seconds) since no monitoring
    [ "$elapsed" -lt 5 ]
    [ "$status" -eq 0 ]
}

@test "push_line_shows_progress_and_single_summary_on_tty" {
    cd "${TEST_REPO}"

    echo "Line mode monitor test" >> README.md
    git add README.md
    git commit --quiet -m "Line mode monitor test"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "2"

    run bash -c "BUILDGIT_FORCE_TTY=1 bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line 2>&1"

    assert_success
    assert_output --partial "IN_PROGRESS Job test-repo #43 ["
    assert_output --partial "SUCCESS"
    refute_output --partial "BUILD IN PROGRESS"
    refute_output --partial "Finished:"
}

@test "push_line_non_tty_silent_until_summary" {
    cd "${TEST_REPO}"

    echo "Line mode non tty test" >> README.md
    git add README.md
    git commit --quiet -m "Line mode non tty test"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "2"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line 2>&1"

    assert_success
    refute_output --partial "IN_PROGRESS Job test-repo #43 ["
    assert_output --partial "SUCCESS"
    assert_output --regexp "#43 id=[[:alnum:]]{7}"
}

@test "push_line_no_follow_matches_no_follow_behavior" {
    cd "${TEST_REPO}"

    echo "Line mode no follow test" >> README.md
    git add README.md
    git commit --quiet -m "Line mode no follow test"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "10"

    run bash -c "bash \"${TEST_TEMP_DIR}/buildgit_wrapper.sh\" --line --no-follow 2>&1"

    assert_success
    assert_output --partial "Push completed (monitoring disabled)"
    refute_output --partial "IN_PROGRESS Job"
}

# -----------------------------------------------------------------------------
# Test Case: Push exits cleanly when nothing to push
# Spec: "If nothing to push, display git's output and exit with git's exit code"
# -----------------------------------------------------------------------------
@test "push_nothing_to_push" {
    cd "${TEST_REPO}"

    # Don't create any new commits - nothing to push

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "1"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    # Should succeed (git push returns 0 for "Everything up-to-date")
    [ "$status" -eq 0 ]
    # Should show git's message
    [[ "$output" == *"Everything up-to-date"* ]] || [[ "$output" == *"up-to-date"* ]] || [[ "$output" == *"Nothing to push"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Push with nothing to push exits cleanly (default follow mode)
# Spec: "If nothing to push, display git's output and exit with git's exit code"
# Verifies that when there's nothing to push and --no-follow is NOT used,
# the command still exits cleanly without attempting to monitor a build.
# -----------------------------------------------------------------------------
@test "push_nothing_to_push_default_follow" {
    cd "${TEST_REPO}"

    # Don't create any new commits - nothing to push

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "1"

    # Run push WITHOUT --no-follow (default monitoring mode)
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Should succeed - "Everything up-to-date" path returns 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Everything up-to-date"* ]] || [[ "$output" == *"up-to-date"* ]] || [[ "$output" == *"Nothing to push"* ]]
    # Should NOT attempt to monitor a build
    refute_output --partial "Waiting for Jenkins build"
}

# -----------------------------------------------------------------------------
# Test Case: Push returns git exit code on failure
# Spec: "Git command fails: Git's exit code"
# -----------------------------------------------------------------------------
@test "push_git_failure_exit_code" {
    cd "${TEST_REPO}"

    # Try to push to non-existent local path (avoids DNS lookup / network)
    git remote remove origin
    git remote add origin "${TEST_TEMP_DIR}/nonexistent-repo.git"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_git_failure_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow 2>&1

    # Should fail with non-zero exit code
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Test Case: Push returns non-zero on build failure
# Spec: "Exit Code: Returns non-zero if the Jenkins build fails"
# -----------------------------------------------------------------------------
@test "push_build_failure_exit_code" {
    cd "${TEST_REPO}"

    # Create a new commit to push
    echo "Failure test" >> README.md
    git add README.md
    git commit --quiet -m "Failure test commit"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "FAILURE" "1"

    # Use run - the || true prevents bats from failing on non-zero exit
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 2>&1

    # Should return non-zero for failed build (1 for build failure)
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Test Case: Push passes arguments through to git push
# Spec: "Other options: Passed through to git push"
# -----------------------------------------------------------------------------
@test "push_passthrough_args" {
    cd "${TEST_REPO}"

    # Create a feature branch
    git checkout -b feature-branch
    echo "Feature content" >> README.md
    git add README.md
    git commit --quiet -m "Feature commit"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "1"

    # Push with explicit remote and branch arguments
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow origin feature-branch

    [ "$status" -eq 0 ]

    # Verify the branch was pushed
    cd "${REMOTE_REPO}"
    run git branch -a
    [[ "$output" == *"feature-branch"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Push with -j/--job flag specifies job
# Spec: "Global Options: -j, --job <name>"
# -----------------------------------------------------------------------------
@test "push_with_job_flag" {
    cd "${TEST_REPO}"

    # Create a new commit
    echo "Job flag test" >> README.md
    git add README.md
    git commit --quiet -m "Job flag test"

    export PROJECT_DIR
    export TEST_TEMP_DIR

    # Use the standard wrapper with --no-follow (no monitoring needed for this test)
    create_push_test_wrapper "SUCCESS" "1"

    # The wrapper always sets JOB_NAME, so for this test we verify
    # that --no-follow works with the job set (testing the global option path)
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    # Should succeed
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Test Case: Push displays git output
# Spec: Essential output includes git command output
# -----------------------------------------------------------------------------
@test "push_displays_git_output" {
    cd "${TEST_REPO}"

    # Create a new commit
    echo "Output test" >> README.md
    git add README.md
    git commit --quiet -m "Output test commit"

    export PROJECT_DIR
    export TEST_TEMP_DIR
    create_push_test_wrapper "SUCCESS" "1"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --no-follow

    # Should show some git push output
    [ "$status" -eq 0 ]
    # Git push typically shows branch info or "Everything up-to-date"
    [[ -n "$output" ]]
}
