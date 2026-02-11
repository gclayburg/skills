#!/usr/bin/env bats

# Tests for buildgit status command - follow mode
# Spec reference: buildgit-spec.md, buildgit status -f/--follow
# Plan reference: buildgit-plan.md, Chunk 5

load test_helper

# Kill a process and all its children (portable across macOS and Linux)
# Uses SIGKILL (-9) because SIGTERM is deferred during command substitution
# on Linux, which causes hangs when the process is blocked in $(...) subshells.
_kill_process_tree() {
    local pid="$1"
    # Kill children first (grandchildren become orphans but exit on their own)
    pkill -9 -P "$pid" 2>/dev/null || true
    # Kill the parent process
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

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
    # Clean up any background processes
    if [[ -n "${FOLLOW_PID:-}" ]]; then
        _kill_process_tree "$FOLLOW_PID"
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

# Safety: self-destruct after 8 seconds to prevent hanging in CI
( sleep 8 && kill -9 $$ 2>/dev/null ) &

# Source buildgit without executing main
_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

# Override poll interval for faster tests
POLL_INTERVAL=1
MAX_BUILD_TIME=30

# Override Jenkins API functions with mocks
verify_jenkins_connection() {
    return 0
}

verify_job_exists() {
    local job_name="$1"
    JOB_URL="${JENKINS_URL}/job/${job_name}"
    return 0
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

# Create wrapper that simulates detecting a new build
create_new_build_detection_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

# Safety: self-destruct after 8 seconds to prevent hanging in CI
( sleep 8 && kill -9 $$ 2>/dev/null ) &

export PROJECT_DIR="__PROJECT_DIR__"
export TEST_TEMP_DIR="__TEST_TEMP_DIR__"

# Track state
BUILD_NUMBER_CALLS=0
BUILD_INFO_CALLS=0

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
    BUILD_NUMBER_CALLS=$((BUILD_NUMBER_CALLS + 1))
    # First few calls return 42, then return 43 to simulate new build
    if [[ $BUILD_NUMBER_CALLS -le 3 ]]; then
        echo "42"
    else
        echo "43"
    fi
}

get_build_info() {
    BUILD_INFO_CALLS=$((BUILD_INFO_CALLS + 1))
    local build_num="${2:-42}"

    if [[ $BUILD_INFO_CALLS -le 2 ]]; then
        # First build - already completed
        echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
    else
        # New build detected and completed
        echo '{"number":43,"result":"SUCCESS","building":false,"timestamp":1706700060000,"duration":90000,"url":"http://jenkins.example.com/job/test-repo/43/"}'
    fi
}

get_console_output() {
    echo "Started by user testuser"
}

get_current_stage() {
    echo "Build"
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

    # Create wrapper with simple SUCCESS response
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << 'WRAPPER_END'
#!/usr/bin/env bash
set -euo pipefail

# Safety: self-destruct after 8 seconds to prevent hanging in CI
( sleep 8 && kill -9 $$ 2>/dev/null ) &

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

JOB_NAME="test-repo"
cmd_status -f "$@"
WRAPPER_END

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Run in background
    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    # Wait for output to be generated
    sleep 5

    # Kill the process
    _kill_process_tree "$FOLLOW_PID"

    # Check output
    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should show build result
    [[ "$output" == *"BUILD SUCCESSFUL"* ]] || [[ "$output" == *"SUCCESS"* ]]
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

    # Run in background
    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    # Wait for waiting message to appear
    sleep 5

    # Kill the process
    _kill_process_tree "$FOLLOW_PID"

    # Check output for waiting message
    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    [[ "$output" == *"Waiting for next build"* ]]
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

    # Run in background
    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    # Wait for new build detection
    sleep 6

    # Kill the process
    _kill_process_tree "$FOLLOW_PID"

    # Check output - should show multiple build results or waiting messages
    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should show waiting message at some point
    [[ "$output" == *"Waiting for next build"* ]]
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

# Safety: self-destruct after 8 seconds to prevent hanging in CI
( sleep 8 && kill -9 $$ 2>/dev/null ) &

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

JOB_NAME="test-repo"
cmd_status -f "$@"
WRAPPER_END

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Run with timeout (simulates forced termination)
    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    local bg_pid=$!
    sleep 4
    _kill_process_tree "$bg_pid"

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Verify follow mode was entered (waiting message shows)
    [[ "$output" == *"Waiting for next build"* ]]

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
    # Build completes quickly
    create_follow_test_wrapper "false" "SUCCESS" "1"

    # Run in background with short timeout
    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    # Wait for output to appear (poll instead of fixed sleep to avoid race conditions)
    local waited=0
    while [[ $waited -lt 8 ]]; do
        if [[ -s "${TEST_TEMP_DIR}/output.txt" ]]; then
            # Give a moment for more output to accumulate
            sleep 1
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Kill the process
    _kill_process_tree "$FOLLOW_PID"

    # Check that build result was displayed
    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

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

    # Run with -f option
    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    sleep 4
    _kill_process_tree "$FOLLOW_PID"

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should enter follow mode (shows waiting message or build status)
    [[ "$output" == *"Waiting for next build"* ]] || [[ "$output" == *"BUILD"* ]]
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

# Safety: self-destruct after 8 seconds to prevent hanging in CI
( sleep 8 && kill -9 $$ 2>/dev/null ) &

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

JOB_NAME="test-repo"
cmd_status --follow "$@"
WRAPPER

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    sleep 4
    _kill_process_tree "$FOLLOW_PID"

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should enter follow mode
    [[ "$output" == *"Waiting for next build"* ]] || [[ "$output" == *"BUILD"* ]]
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
    # Build already completed (building=false), result=SUCCESS, poll_cycles=0
    # poll_cycles=0 ensures first get_build_info call returns the final result
    create_follow_test_wrapper "false" "SUCCESS" "0"

    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    sleep 5
    _kill_process_tree "$FOLLOW_PID"

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should show BUILD SUCCESSFUL banner
    [[ "$output" == *"BUILD SUCCESSFUL"* ]]

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
    # Build already completed (building=false), result=FAILURE, poll_cycles=0
    create_follow_test_wrapper "false" "FAILURE" "0"

    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    sleep 5
    _kill_process_tree "$FOLLOW_PID"

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should show BUILD FAILED banner
    [[ "$output" == *"BUILD FAILED"* ]]

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
    create_follow_test_wrapper "false" "SUCCESS" "0"

    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    sleep 5
    _kill_process_tree "$FOLLOW_PID"

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

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
    create_follow_test_wrapper "false" "SUCCESS" "0"

    bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
    FOLLOW_PID=$!

    sleep 5
    _kill_process_tree "$FOLLOW_PID"

    local output
    output=$(cat "${TEST_TEMP_DIR}/output.txt")

    # Should show console URL
    [[ "$output" == *"Console:"*"console"* ]]
}
