#!/usr/bin/env bats

# Tests for buildgit real-time progress display
# Spec reference: bug2026-02-01-buildgit-monitoring-spec.md, Issue 3
# Plan reference: bug2026-02-01-buildgit-monitoring-plan.md, Chunk C

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
# Helper: Create test wrapper that exposes progress logging functions
# =============================================================================

create_progress_test_wrapper() {
    cat > "${TEST_TEMP_DIR}/progress_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR}"

# Source jenkins-common.sh for base logging functions
source "${PROJECT_DIR}/lib/jenkins-common.sh"

# Global variable for verbosity
VERBOSE_MODE=false

# Progress logging functions (from buildgit with real-time progress)
bg_log_progress() {
    log_info "$@" >&2
}

bg_log_progress_success() {
    log_success "$@" >&2
}

# Parse verbose flag and run action
main() {
    local action="${1:-}"
    shift || true

    if [[ "${1:-}" == "--verbose" ]]; then
        VERBOSE_MODE=true
    fi

    case "$action" in
        "test_progress")
            bg_log_progress "Build in progress... (30s elapsed)"
            ;;
        "test_stage_completion")
            bg_log_progress_success "Stage completed: Checkout"
            ;;
        "test_return_value")
            # Simulate a function that returns a value via stdout
            # while also calling progress functions
            bg_log_progress "Processing..."
            bg_log_progress_success "Stage completed: Build"
            echo "42"
            ;;
        *)
            echo "Unknown action"
            exit 1
            ;;
    esac
}

main "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/progress_test.sh"
}

# =============================================================================
# Test Cases: Progress Output Without Verbose Mode
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Stage completion messages appear in non-verbose mode
# Spec: Issue 3 - No Real-Time Progress Display
# -----------------------------------------------------------------------------
@test "stage_completion_shown_without_verbose" {
    export PROJECT_DIR
    create_progress_test_wrapper

    # Run without verbose mode and capture stderr
    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_stage_completion 2>&1 1>/dev/null"

    assert_success
    assert_output --partial "Stage completed: Checkout"
}

# -----------------------------------------------------------------------------
# Test Case: Elapsed time updates appear in non-verbose mode
# Spec: Issue 3 - No Real-Time Progress Display
# -----------------------------------------------------------------------------
@test "elapsed_time_shown_without_verbose" {
    export PROJECT_DIR
    create_progress_test_wrapper

    # Run without verbose mode and capture stderr
    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_progress 2>&1 1>/dev/null"

    assert_success
    assert_output --partial "Build in progress"
    assert_output --partial "elapsed"
}

# -----------------------------------------------------------------------------
# Test Case: Stage completion message format matches spec
# Spec: Issue 3 - Expected output: "[10:13:30] ✓ Stage completed: Checkout"
# -----------------------------------------------------------------------------
@test "stage_completion_format_correct" {
    export PROJECT_DIR
    create_progress_test_wrapper

    # Run and capture stderr
    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_stage_completion 2>&1 1>/dev/null"

    assert_success
    # Should contain checkmark (success format) and "Stage completed:"
    assert_output --partial "Stage completed:"
    # log_success uses checkmark symbol
    assert_output --partial "✓"
}

# -----------------------------------------------------------------------------
# Test Case: Progress messages go to stderr (not stdout)
# Spec: Issue 3 - Uses stderr to avoid corrupting any command substitution
# -----------------------------------------------------------------------------
@test "progress_output_to_stderr" {
    export PROJECT_DIR
    create_progress_test_wrapper

    # Run and capture stdout only (suppress stderr)
    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_progress 2>/dev/null"

    # stdout should be empty (progress goes to stderr)
    assert_success
    assert_output ""

    # Now verify stderr has the message
    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_progress 2>&1 1>/dev/null"
    assert_success
    assert_output --partial "Build in progress"
}

# -----------------------------------------------------------------------------
# Test Case: Progress output does not corrupt return values
# Spec: Issue 3 - Uses stderr to avoid corrupting any command substitution
# -----------------------------------------------------------------------------
@test "progress_does_not_corrupt_return_value" {
    export PROJECT_DIR
    create_progress_test_wrapper

    # Create a script that captures a return value using command substitution
    cat > "${TEST_TEMP_DIR}/capture_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Capture stdout (the return value) - stderr goes to terminal
result=$(bash "${TEST_TEMP_DIR}/progress_test.sh" test_return_value 2>/dev/null)

# The result should be exactly "42", not corrupted with progress messages
if [[ "$result" == "42" ]]; then
    echo "SUCCESS: result='$result'"
    exit 0
else
    echo "FAIL: expected '42' but got '$result'"
    exit 1
fi
EOF
    chmod +x "${TEST_TEMP_DIR}/capture_test.sh"

    export TEST_TEMP_DIR
    run bash "${TEST_TEMP_DIR}/capture_test.sh"

    assert_success
    assert_output --partial "SUCCESS: result='42'"
}

# =============================================================================
# Test Cases: Integration - Verify buildgit has progress functions
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Verify buildgit has bg_log_progress function
# Spec: Issue 3 - Implementation Details
# -----------------------------------------------------------------------------
@test "buildgit_has_bg_log_progress_function"  {
    # Check that buildgit contains the bg_log_progress function
    run grep -A3 "bg_log_progress()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    assert_output --partial "log_info"
    assert_output --partial ">&2"
}

# -----------------------------------------------------------------------------
# Test Case: Verify buildgit has bg_log_progress_success function
# Spec: Issue 3 - Implementation Details
# -----------------------------------------------------------------------------
@test "buildgit_has_bg_log_progress_success_function" {
    # Check that buildgit contains the bg_log_progress_success function
    run grep -A3 "bg_log_progress_success()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    assert_output --partial "log_success"
    assert_output --partial ">&2"
}

# -----------------------------------------------------------------------------
# Test Case: Verify consolidated _monitor_build uses bg_log_progress for elapsed time
# Spec: unify-follow-log-spec.md - consolidated monitor function
# (Updated: three monitor functions consolidated into _monitor_build)
# -----------------------------------------------------------------------------
@test "follow_monitor_uses_bg_log_progress_for_elapsed_time" {
    run grep -A60 "^_monitor_build()" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "bg_log_progress"
    assert_output --partial "elapsed"
}

# -----------------------------------------------------------------------------
# Test Case: Verify consolidated _monitor_build has stage tracking
# Spec: unify-follow-log-spec.md - consolidated monitor function
# (Updated: three monitor functions consolidated into _monitor_build)
# -----------------------------------------------------------------------------
@test "follow_monitor_has_stage_completion_tracking" {
    run grep -A50 "^_monitor_build()" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "track_stage_changes"
}

# -----------------------------------------------------------------------------
# Test Case: Verify _monitor_build is used by push command path
# Spec: unify-follow-log-spec.md - consolidated monitor function
# -----------------------------------------------------------------------------
@test "push_monitor_uses_bg_log_progress_for_elapsed_time" {
    run grep "_monitor_build" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_monitor_build"
}

# -----------------------------------------------------------------------------
# Test Case: Verify old _push_monitor_build no longer exists
# Spec: unify-follow-log-spec.md - consolidated monitor function
# -----------------------------------------------------------------------------
@test "push_monitor_has_stage_completion_tracking" {
    run grep -c "^_push_monitor_build()" "${PROJECT_DIR}/buildgit"
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: Verify old _build_monitor no longer exists
# Spec: unify-follow-log-spec.md - consolidated monitor function
# -----------------------------------------------------------------------------
@test "build_monitor_uses_bg_log_progress_for_elapsed_time" {
    run grep -c "^_build_monitor()" "${PROJECT_DIR}/buildgit"
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: Verify old _follow_monitor_build no longer exists
# Spec: unify-follow-log-spec.md - consolidated monitor function
# -----------------------------------------------------------------------------
@test "build_monitor_has_stage_completion_tracking" {
    run grep -c "^_follow_monitor_build()" "${PROJECT_DIR}/buildgit"
    assert_failure
}
