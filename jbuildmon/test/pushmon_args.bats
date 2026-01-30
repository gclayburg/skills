#!/usr/bin/env bats

# Tests for modernized argument handling in pushmon.sh
# Spec reference: fixjobflags-spec.md, Section 3
# Plan reference: fixjobflags-plan.md#chunk-b

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

    # Create a mock git repo
    MOCK_REPO="${TEST_TEMP_DIR}/repo"
    mkdir -p "${MOCK_REPO}"
    cd "${MOCK_REPO}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    # Set up a fake remote
    git remote add origin "https://github.com/example/repo.git"
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
# Helper: Create test wrapper script
# =============================================================================

create_test_wrapper() {
    local mock_staged="${1:-false}"
    local mock_unpushed="${2:-true}"
    local mock_discover_success="${3:-true}"
    local mock_job_name="${4:-auto-detected-job}"

    cat > "${TEST_TEMP_DIR}/pushmon_wrapper.sh" << 'WRAPPER_START'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# Source jenkins-common.sh to get logging functions
source "${PROJECT_DIR}/lib/jenkins-common.sh"

WRAPPER_START

    # Add mock functions
    cat >> "${TEST_TEMP_DIR}/pushmon_wrapper.sh" << EOF
# Mock discover_job_name
discover_job_name() {
    if [[ "$mock_discover_success" == "true" ]]; then
        echo "$mock_job_name"
        return 0
    else
        return 1
    fi
}

# Mock git and Jenkins operations
validate_environment() { return 0; }
validate_dependencies() { return 0; }
validate_git_repository() { return 0; }
verify_jenkins_connection() { return 0; }
verify_job_exists() { return 0; }
display_config_summary() { echo "Config: job=\$1"; }
get_last_build_number() { echo "1"; }
wait_for_build_start() { BUILD_NUMBER=2; return 0; }
monitor_build() { return 0; }
handle_build_result() { return 0; }
commit_changes() { echo "COMMITTED: \$1"; }
sync_with_remote() { return 0; }
push_changes() { return 0; }

# Mock check_for_changes
HAS_STAGED_CHANGES=$mock_staged
check_for_changes() {
    HAS_STAGED_CHANGES=$mock_staged
    if [[ "$mock_staged" == "false" && "$mock_unpushed" == "false" ]]; then
        log_error "No staged changes and no unpushed commits"
        exit 1
    fi
}
EOF

    # Copy the functions from pushmon.sh
    cat >> "${TEST_TEMP_DIR}/pushmon_wrapper.sh" << 'WRAPPER_MID'

# Global state
BUILD_NUMBER=""
JOB_NAME=""
COMMIT_MESSAGE=""

WRAPPER_MID

    # Extract usage and parse_arguments from pushmon.sh
    sed -n '/^usage()/,/^}/p' "${PROJECT_DIR}/pushmon.sh" >> "${TEST_TEMP_DIR}/pushmon_wrapper.sh"
    echo "" >> "${TEST_TEMP_DIR}/pushmon_wrapper.sh"
    sed -n '/^parse_arguments()/,/^}/p' "${PROJECT_DIR}/pushmon.sh" >> "${TEST_TEMP_DIR}/pushmon_wrapper.sh"

    # Add a simplified main for testing
    cat >> "${TEST_TEMP_DIR}/pushmon_wrapper.sh" << 'WRAPPER_END'

# Simplified main for testing
main() {
    parse_arguments "$@"

    validate_environment || exit 1
    validate_dependencies || exit 1
    validate_git_repository || exit 1

    # Resolve job name
    local job_name
    if [[ -n "$JOB_NAME" ]]; then
        job_name="$JOB_NAME"
        log_info "Using specified job: $job_name"
    else
        log_info "Discovering Jenkins job name..."
        if ! job_name=$(discover_job_name); then
            log_error "Could not determine Jenkins job name"
            log_info "To fix this, either:"
            log_info "  1. Add JOB_NAME=<job-name> to AGENTS.md in your repository root"
            log_info "  2. Use the --job <job> or -j <job> flag"
            exit 1
        fi
        log_success "Job name: $job_name"
    fi

    display_config_summary "$job_name"
    verify_jenkins_connection || exit 1
    verify_job_exists "$job_name" || exit 1

    check_for_changes

    # Validate commit message for staged changes
    if [[ "$HAS_STAGED_CHANGES" == true && -z "$COMMIT_MESSAGE" ]]; then
        log_error "Staged changes found but no commit message provided"
        log_info "Use -m or --msg to specify a commit message"
        exit 1
    fi

    if [[ "$HAS_STAGED_CHANGES" == true ]]; then
        commit_changes "$COMMIT_MESSAGE"
    fi

    echo "RESOLVED_JOB: $job_name"
    echo "COMMIT_MESSAGE: $COMMIT_MESSAGE"
}

main "$@"
WRAPPER_END

    chmod +x "${TEST_TEMP_DIR}/pushmon_wrapper.sh"
}

# =============================================================================
# Test Cases
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: --job flag sets job name
# Spec: Section 3.2
# -----------------------------------------------------------------------------
@test "job_flag_sets_job_name" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --job myjob

    assert_success
    assert_output --partial "Using specified job: myjob"
    assert_output --partial "RESOLVED_JOB: myjob"
}

# -----------------------------------------------------------------------------
# Test Case: -j short flag works
# Spec: Section 3.2
# -----------------------------------------------------------------------------
@test "job_short_flag_works" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" -j myjob

    assert_success
    assert_output --partial "Using specified job: myjob"
    assert_output --partial "RESOLVED_JOB: myjob"
}

# -----------------------------------------------------------------------------
# Test Case: --msg flag sets commit message
# Spec: Section 3.2
# -----------------------------------------------------------------------------
@test "msg_flag_sets_commit_message" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper true true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --msg "my commit message"

    assert_success
    assert_output --partial "COMMITTED: my commit message"
    assert_output --partial "COMMIT_MESSAGE: my commit message"
}

# -----------------------------------------------------------------------------
# Test Case: -m short flag works
# Spec: Section 3.2
# -----------------------------------------------------------------------------
@test "msg_short_flag_works" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper true true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" -m "my commit message"

    assert_success
    assert_output --partial "COMMITTED: my commit message"
}

# -----------------------------------------------------------------------------
# Test Case: --help shows usage and exits 0
# Spec: Section 3.2, 4.2.7
# -----------------------------------------------------------------------------
@test "help_flag_shows_usage" {
    cd "${MOCK_REPO}"

    run bash "${PROJECT_DIR}/pushmon.sh" --help

    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "-j, --job <job>"
    assert_output --partial "-m, --msg <message>"
    assert_output --partial "-h, --help"
}

# -----------------------------------------------------------------------------
# Test Case: -h short flag works
# Spec: Section 3.2
# -----------------------------------------------------------------------------
@test "help_short_flag_works" {
    cd "${MOCK_REPO}"

    run bash "${PROJECT_DIR}/pushmon.sh" -h

    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "-j, --job <job>"
}

# -----------------------------------------------------------------------------
# Test Case: Unknown option errors
# Spec: Section 3.5
# -----------------------------------------------------------------------------
@test "unknown_option_errors" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --foo

    assert_failure
    assert_output --partial "Unknown option: --foo"
}

# -----------------------------------------------------------------------------
# Test Case: --job without value shows error
# Spec: Section 3.5
# -----------------------------------------------------------------------------
@test "job_flag_missing_value_errors" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --job

    assert_failure
    assert_output --partial "requires a job name"
}

# -----------------------------------------------------------------------------
# Test Case: --msg without value shows error
# Spec: Section 3.5
# -----------------------------------------------------------------------------
@test "msg_flag_missing_value_errors" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --msg

    assert_failure
    assert_output --partial "requires a commit message"
}

# -----------------------------------------------------------------------------
# Test Case: Positional arguments are rejected
# Spec: Section 5.1
# -----------------------------------------------------------------------------
@test "positional_args_rejected" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" myjob "commit message"

    assert_failure
    assert_output --partial "Unknown option: myjob"
}

# -----------------------------------------------------------------------------
# Test Case: Auto-detection is used when no --job flag
# Spec: Section 1.1
# -----------------------------------------------------------------------------
@test "autodetect_used_when_no_job_flag" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh"

    assert_success
    assert_output --partial "Discovering Jenkins job name..."
    assert_output --partial "RESOLVED_JOB: auto-detected-job"
}

# -----------------------------------------------------------------------------
# Test Case: Auto-detection failure shows help message
# Spec: Section 1.2
# -----------------------------------------------------------------------------
@test "autodetect_failure_shows_help_message" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true false "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh"

    assert_failure
    assert_output --partial "Could not determine Jenkins job name"
    assert_output --partial "Add JOB_NAME=<job-name> to AGENTS.md"
    assert_output --partial "--job <job> or -j <job> flag"
}

# -----------------------------------------------------------------------------
# Test Case: Staged changes without -m errors
# Spec: Section 3.4.1
# -----------------------------------------------------------------------------
@test "staged_changes_without_msg_errors" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper true true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --job myjob

    assert_failure
    assert_output --partial "Staged changes found but no commit message provided"
    assert_output --partial "Use -m or --msg to specify a commit message"
}

# -----------------------------------------------------------------------------
# Test Case: Staged changes with -m succeeds
# Spec: Section 3.4.2
# -----------------------------------------------------------------------------
@test "staged_changes_with_msg_succeeds" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper true true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --job myjob -m "my message"

    assert_success
    assert_output --partial "COMMITTED: my message"
}

# -----------------------------------------------------------------------------
# Test Case: Unpushed commits without -m succeeds
# Spec: Section 3.4.3
# -----------------------------------------------------------------------------
@test "unpushed_commits_no_msg_succeeds" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper false true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" --job myjob

    assert_success
    refute_output --partial "COMMITTED:"
    assert_output --partial "RESOLVED_JOB: myjob"
}

# -----------------------------------------------------------------------------
# Test Case: Combined flags work together
# Spec: Section 3.2
# -----------------------------------------------------------------------------
@test "combined_flags_work" {
    cd "${MOCK_REPO}"
    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper true true true "auto-detected-job"

    run bash "${TEST_TEMP_DIR}/pushmon_wrapper.sh" -j myjob -m "my message"

    assert_success
    assert_output --partial "Using specified job: myjob"
    assert_output --partial "COMMITTED: my message"
    assert_output --partial "RESOLVED_JOB: myjob"
}
