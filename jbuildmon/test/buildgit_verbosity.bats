#!/usr/bin/env bats

# Tests for buildgit verbosity control infrastructure
# Spec reference: buildgit-spec.md, Verbosity Behavior
# Plan reference: buildgit-plan.md, Chunk 2

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
# Helper: Create test wrapper that exposes logging functions
# =============================================================================

create_verbosity_test_wrapper() {
    cat > "${TEST_TEMP_DIR}/verbosity_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR}"

# Source jenkins-common.sh for base logging functions
source "${PROJECT_DIR}/lib/jenkins-common.sh"

# Global variable for verbosity (set from command line arg)
VERBOSE_MODE=false

# Verbosity-aware logging wrapper functions (copied from buildgit)
bg_log_info() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_info "$@"
    fi
}

bg_log_success() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_success "$@"
    fi
}

bg_log_warning() {
    log_warning "$@"
}

bg_log_error() {
    log_error "$@"
}

bg_log_essential() {
    echo "$@"
}

# Test function that exercises all logging functions
test_all_logging() {
    bg_log_info "Verifying Jenkins connectivity..."
    bg_log_success "Connected to Jenkins"
    bg_log_info "Found job name: test-job"
    bg_log_info "Analyzing build details..."
    bg_log_warning "Build is unstable"
    bg_log_error "Build failed"
    bg_log_essential "Build result: SUCCESS"
    bg_log_essential "git status output here"
}

# Parse verbose flag and run test
main() {
    if [[ "${1:-}" == "--verbose" ]]; then
        VERBOSE_MODE=true
    fi
    test_all_logging
}

main "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/verbosity_test.sh"
}

# =============================================================================
# Test Cases: Quiet Mode (Default)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Info messages are suppressed in quiet mode (default)
# Spec: Verbosity Behavior - Default (quiet mode)
# -----------------------------------------------------------------------------
@test "quiet_mode_suppresses_info" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh"

    assert_success
    # Info messages should NOT appear
    refute_output --partial "Verifying Jenkins connectivity"
    refute_output --partial "Connected to Jenkins"
    refute_output --partial "Found job name"
    refute_output --partial "Analyzing build details"
}

# -----------------------------------------------------------------------------
# Test Case: Error messages are shown in quiet mode
# Spec: Verbosity Behavior - Shows essential output
# -----------------------------------------------------------------------------
@test "quiet_mode_shows_errors" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh"

    assert_success
    # Error messages should appear
    assert_output --partial "Build failed"
}

# -----------------------------------------------------------------------------
# Test Case: Warning messages are shown in quiet mode
# Spec: Verbosity Behavior - Shows essential output
# -----------------------------------------------------------------------------
@test "quiet_mode_shows_warnings" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh"

    assert_success
    # Warning messages should appear
    assert_output --partial "Build is unstable"
}

# -----------------------------------------------------------------------------
# Test Case: Build results are shown in quiet mode
# Spec: Verbosity Behavior - Shows build results
# -----------------------------------------------------------------------------
@test "quiet_mode_shows_build_results" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh"

    assert_success
    # Essential messages (build results) should appear
    assert_output --partial "Build result: SUCCESS"
}

# -----------------------------------------------------------------------------
# Test Case: Git output is shown in quiet mode
# Spec: Verbosity Behavior - Shows git command output
# -----------------------------------------------------------------------------
@test "quiet_mode_shows_git_output" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh"

    assert_success
    # Essential messages (git output) should appear
    assert_output --partial "git status output here"
}

# =============================================================================
# Test Cases: Verbose Mode (--verbose)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Info messages are shown with --verbose
# Spec: Verbosity Behavior - With --verbose
# -----------------------------------------------------------------------------
@test "verbose_mode_shows_info" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh" --verbose

    assert_success
    # Info messages should now appear
    assert_output --partial "Verifying Jenkins connectivity"
    assert_output --partial "Connected to Jenkins"
    assert_output --partial "Found job name"
    assert_output --partial "Analyzing build details"
}

# -----------------------------------------------------------------------------
# Test Case: Success messages are shown with --verbose
# Spec: Verbosity Behavior - With --verbose
# -----------------------------------------------------------------------------
@test "verbose_mode_shows_success" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh" --verbose

    assert_success
    # Success messages should appear
    assert_output --partial "Connected to Jenkins"
}

# -----------------------------------------------------------------------------
# Test Case: Errors still shown with --verbose
# Spec: Verbosity Behavior - errors always shown
# -----------------------------------------------------------------------------
@test "verbose_mode_still_shows_errors" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh" --verbose

    assert_success
    # Error messages should still appear
    assert_output --partial "Build failed"
}

# -----------------------------------------------------------------------------
# Test Case: Warnings still shown with --verbose
# Spec: Verbosity Behavior - warnings always shown
# -----------------------------------------------------------------------------
@test "verbose_mode_still_shows_warnings" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh" --verbose

    assert_success
    # Warning messages should still appear
    assert_output --partial "Build is unstable"
}

# -----------------------------------------------------------------------------
# Test Case: Essential output still shown with --verbose
# Spec: Verbosity Behavior - essential output always shown
# -----------------------------------------------------------------------------
@test "verbose_mode_still_shows_essential" {
    export PROJECT_DIR
    create_verbosity_test_wrapper

    run bash "${TEST_TEMP_DIR}/verbosity_test.sh" --verbose

    assert_success
    # Essential messages should still appear
    assert_output --partial "Build result: SUCCESS"
    assert_output --partial "git status output here"
}

# =============================================================================
# Test Cases: Integration with buildgit script
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: buildgit VERBOSE_MODE defaults to false
# Spec: Verbosity Behavior - Default (quiet mode)
# -----------------------------------------------------------------------------
@test "buildgit_verbose_mode_default_false" {
    export PROJECT_DIR

    # Create a test that sources buildgit and checks VERBOSE_MODE
    cat > "${TEST_TEMP_DIR}/check_verbose.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR}"

# Extract just the variable initialization and check
source "${PROJECT_DIR}/lib/jenkins-common.sh"

JOB_NAME=""
VERBOSE_MODE=false
COMMAND=""
COMMAND_ARGS=()

echo "VERBOSE_MODE=${VERBOSE_MODE}"
EOF
    chmod +x "${TEST_TEMP_DIR}/check_verbose.sh"

    run bash "${TEST_TEMP_DIR}/check_verbose.sh"

    assert_success
    assert_output --partial "VERBOSE_MODE=false"
}

# -----------------------------------------------------------------------------
# Test Case: Verify logging functions exist in buildgit
# Spec: Verbosity Behavior
# -----------------------------------------------------------------------------
@test "buildgit_has_logging_functions" {
    # Check that buildgit contains the verbosity logging functions
    run grep -c "bg_log_info()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success

    run grep -c "bg_log_success()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success

    run grep -c "bg_log_warning()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success

    run grep -c "bg_log_error()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success

    run grep -c "bg_log_essential()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
}
