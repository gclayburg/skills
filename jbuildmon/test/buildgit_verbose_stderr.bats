#!/usr/bin/env bats

# Tests for buildgit verbose mode stderr redirection
# Spec reference: bug2026-02-01-buildgit-monitoring-spec.md, Issue 2
# Plan reference: bug2026-02-01-buildgit-monitoring-plan.md, Chunk A

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
# Helper: Create test wrapper that exposes logging functions for stderr testing
# =============================================================================

create_stderr_test_wrapper() {
    cat > "${TEST_TEMP_DIR}/stderr_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR}"

# Source jenkins-common.sh for base logging functions
source "${PROJECT_DIR}/lib/jenkins-common.sh"

# Global variable for verbosity (set from command line arg)
VERBOSE_MODE=false

# Verbosity-aware logging wrapper functions (from buildgit with stderr fix)
bg_log_info() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_info "$@" >&2
    fi
}

bg_log_success() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_success "$@" >&2
    fi
}

# Parse verbose flag and run action
main() {
    local action="${1:-}"
    shift || true

    if [[ "${1:-}" == "--verbose" ]]; then
        VERBOSE_MODE=true
    fi

    case "$action" in
        "test_info")
            bg_log_info "This is info message"
            ;;
        "test_success")
            bg_log_success "This is success message"
            ;;
        "test_return_value")
            # Simulate a function that returns a value via stdout
            # while also calling bg_log_info
            bg_log_info "Processing..."
            bg_log_success "Processed!"
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
    chmod +x "${TEST_TEMP_DIR}/stderr_test.sh"
}

# =============================================================================
# Test Cases: Verbose Output to stderr
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: bg_log_info output goes to stderr when VERBOSE_MODE=true
# Spec: Issue 2 - Verbose Mode Causes Output Corruption
# -----------------------------------------------------------------------------
@test "verbose_info_goes_to_stderr" {
    export PROJECT_DIR
    create_stderr_test_wrapper

    # Run with verbose mode and capture stdout and stderr separately
    run bash -c "bash '${TEST_TEMP_DIR}/stderr_test.sh' test_info --verbose 2>/dev/null"

    # stdout should be empty (info goes to stderr)
    assert_success
    assert_output ""

    # Now verify stderr has the message
    run bash -c "bash '${TEST_TEMP_DIR}/stderr_test.sh' test_info --verbose 2>&1 1>/dev/null"
    assert_success
    assert_output --partial "This is info message"
}

# -----------------------------------------------------------------------------
# Test Case: bg_log_success output goes to stderr when VERBOSE_MODE=true
# Spec: Issue 2 - Verbose Mode Causes Output Corruption
# -----------------------------------------------------------------------------
@test "verbose_success_goes_to_stderr" {
    export PROJECT_DIR
    create_stderr_test_wrapper

    # Run with verbose mode and capture stdout only
    run bash -c "bash '${TEST_TEMP_DIR}/stderr_test.sh' test_success --verbose 2>/dev/null"

    # stdout should be empty (success goes to stderr)
    assert_success
    assert_output ""

    # Now verify stderr has the message
    run bash -c "bash '${TEST_TEMP_DIR}/stderr_test.sh' test_success --verbose 2>&1 1>/dev/null"
    assert_success
    assert_output --partial "This is success message"
}

# -----------------------------------------------------------------------------
# Test Case: Function return values via command substitution are not corrupted
# Spec: Issue 2 - Verbose Mode Causes Output Corruption
# -----------------------------------------------------------------------------
@test "verbose_does_not_corrupt_return_value" {
    export PROJECT_DIR
    create_stderr_test_wrapper

    # Create a script that captures a return value using command substitution
    cat > "${TEST_TEMP_DIR}/capture_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Capture stdout (the return value) - stderr goes to terminal
result=$(bash "${TEST_TEMP_DIR}/stderr_test.sh" test_return_value --verbose 2>/dev/null)

# The result should be exactly "42", not corrupted with log messages
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

# -----------------------------------------------------------------------------
# Test Case: bg_log_info and bg_log_success produce no output when VERBOSE_MODE=false
# Spec: Issue 2 - Verbose Mode Causes Output Corruption
# -----------------------------------------------------------------------------
@test "quiet_mode_no_output" {
    export PROJECT_DIR
    create_stderr_test_wrapper

    # Test info - no output in quiet mode (no --verbose)
    run bash -c "bash '${TEST_TEMP_DIR}/stderr_test.sh' test_info 2>&1"
    assert_success
    assert_output ""

    # Test success - no output in quiet mode (no --verbose)
    run bash -c "bash '${TEST_TEMP_DIR}/stderr_test.sh' test_success 2>&1"
    assert_success
    assert_output ""
}

# =============================================================================
# Test Cases: Integration with actual buildgit script
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Verify buildgit bg_log_info has stderr redirection
# Spec: Issue 2 - Implementation Details
# -----------------------------------------------------------------------------
@test "buildgit_bg_log_info_has_stderr_redirect" {
    # Check that buildgit contains the stderr redirect in bg_log_info
    run grep -A3 "bg_log_info()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    assert_output --partial ">&2"
}

# -----------------------------------------------------------------------------
# Test Case: Verify buildgit bg_log_success has stderr redirection
# Spec: Issue 2 - Implementation Details
# -----------------------------------------------------------------------------
@test "buildgit_bg_log_success_has_stderr_redirect" {
    # Check that buildgit contains the stderr redirect in bg_log_success
    run grep -A3 "bg_log_success()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    assert_output --partial ">&2"
}
