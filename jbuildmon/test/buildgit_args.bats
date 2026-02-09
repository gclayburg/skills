#!/usr/bin/env bats

# Tests for buildgit global argument parsing
# Spec reference: buildgit-spec.md, Global Options and Command Syntax Summary
# Plan reference: buildgit-plan.md, Chunk 1

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
# Helper: Create test wrapper that exposes parsed values
# =============================================================================

create_args_test_wrapper() {
    cat > "${TEST_TEMP_DIR}/buildgit_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR}"

# Source jenkins-common.sh for logging functions
source "${PROJECT_DIR}/lib/jenkins-common.sh"

# Global variables
JOB_NAME=""
VERBOSE_MODE=false
COMMAND=""
COMMAND_ARGS=()

# Extract show_usage from buildgit
show_usage() {
    cat <<USAGE_EOF
Usage: buildgit [global-options] <command> [command-options] [arguments]

A unified interface for git operations with Jenkins CI/CD integration.

Global Options:
  -j, --job <name>    Specify Jenkins job name (overrides auto-detection)
  -h, --help          Show this help message
  --verbose           Enable verbose output for debugging

Commands:
  status [-f|--follow] [--json] [git-status-options]
                      Display combined git and Jenkins build status
  push [--no-follow] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] Trigger and monitor Jenkins build
  <any-git-command>   Passed through to git
USAGE_EOF
}

# Extract parse_global_options from buildgit
parse_global_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--job)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires a job name"
                    exit 1
                fi
                JOB_NAME="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -*)
                log_error "Unknown global option: $1"
                echo ""
                show_usage
                exit 1
                ;;
            *)
                COMMAND="$1"
                shift
                COMMAND_ARGS=("$@")
                return 0
                ;;
        esac
    done
}

# Test main that outputs parsed values
main() {
    parse_global_options "$@"

    if [[ -z "$COMMAND" ]]; then
        show_usage
        exit 1
    fi

    # Output parsed values for test verification
    echo "JOB_NAME: ${JOB_NAME}"
    echo "VERBOSE_MODE: ${VERBOSE_MODE}"
    echo "COMMAND: ${COMMAND}"
    echo "COMMAND_ARGS: ${COMMAND_ARGS[*]:-}"
}

main "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/buildgit_test.sh"
}

# =============================================================================
# Test Cases: Job Flag Parsing
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: -j short flag extracts job name correctly
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_global_job_short_flag" {
    export PROJECT_DIR
    create_args_test_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -j myjob status

    assert_success
    assert_output --partial "JOB_NAME: myjob"
    assert_output --partial "COMMAND: status"
}

# -----------------------------------------------------------------------------
# Test Case: --job long flag extracts job name correctly
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_global_job_long_flag" {
    export PROJECT_DIR
    create_args_test_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" --job myjob status

    assert_success
    assert_output --partial "JOB_NAME: myjob"
    assert_output --partial "COMMAND: status"
}

# -----------------------------------------------------------------------------
# Test Case: --verbose sets verbose mode
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_global_verbose_flag" {
    export PROJECT_DIR
    create_args_test_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" --verbose status

    assert_success
    assert_output --partial "VERBOSE_MODE: true"
    assert_output --partial "COMMAND: status"
}

# -----------------------------------------------------------------------------
# Test Case: -h shows usage and exits 0
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_global_help_short" {
    run "${PROJECT_DIR}/buildgit" -h

    assert_success
    assert_output --partial "Usage: buildgit"
    assert_output --partial "-j, --job <name>"
    assert_output --partial "--verbose"
}

# -----------------------------------------------------------------------------
# Test Case: --help shows usage and exits 0
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_global_help_long" {
    run "${PROJECT_DIR}/buildgit" --help

    assert_success
    assert_output --partial "Usage: buildgit"
    assert_output --partial "-j, --job <name>"
    assert_output --partial "--verbose"
    assert_output --partial "Commands:"
}

# -----------------------------------------------------------------------------
# Test Case: Multiple global options parsed correctly
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_global_multiple_options" {
    export PROJECT_DIR
    create_args_test_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -j myjob --verbose status

    assert_success
    assert_output --partial "JOB_NAME: myjob"
    assert_output --partial "VERBOSE_MODE: true"
    assert_output --partial "COMMAND: status"
}

# -----------------------------------------------------------------------------
# Test Case: No command shows usage and exits 1
# Spec: Command Syntax
# -----------------------------------------------------------------------------
@test "parse_global_no_command" {
    run "${PROJECT_DIR}/buildgit"

    assert_failure
    assert_output --partial "Usage: buildgit"
}

# -----------------------------------------------------------------------------
# Test Case: Options after command are passed through as command args
# Spec: Command Syntax
# -----------------------------------------------------------------------------
@test "parse_global_options_before_command" {
    export PROJECT_DIR
    create_args_test_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -j myjob status --json -f

    assert_success
    assert_output --partial "JOB_NAME: myjob"
    assert_output --partial "COMMAND: status"
    assert_output --partial "COMMAND_ARGS: --json -f"
}

# -----------------------------------------------------------------------------
# Test Case: -j without value shows error
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_job_missing_value" {
    run "${PROJECT_DIR}/buildgit" -j

    assert_failure
    assert_output --partial "requires a job name"
}

# -----------------------------------------------------------------------------
# Test Case: --job without value shows error
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_job_long_missing_value" {
    run "${PROJECT_DIR}/buildgit" --job

    assert_failure
    assert_output --partial "requires a job name"
}

# -----------------------------------------------------------------------------
# Test Case: --job with empty string shows error
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_job_empty_value" {
    run "${PROJECT_DIR}/buildgit" --job "" status

    assert_failure
    assert_output --partial "requires a job name"
}

# -----------------------------------------------------------------------------
# Test Case: Unknown global option shows error
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_unknown_global_option" {
    run "${PROJECT_DIR}/buildgit" --unknown-option status

    assert_failure
    assert_output --partial "Unknown global option: --unknown-option"
}

# -----------------------------------------------------------------------------
# Test Case: Global options with no job value when followed by command
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_job_flag_followed_by_command" {
    # When -j is followed directly by a command (no value), it should error
    run "${PROJECT_DIR}/buildgit" -j status

    # -j expects an argument, so "status" becomes the job name
    # With no command remaining, it shows usage and exits 1
    assert_failure
    assert_output --partial "Usage: buildgit"
}

# -----------------------------------------------------------------------------
# Test Case: Verbose flag order doesn't matter
# Spec: Global Options
# -----------------------------------------------------------------------------
@test "parse_verbose_before_job" {
    export PROJECT_DIR
    create_args_test_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" --verbose -j myjob status

    assert_success
    assert_output --partial "JOB_NAME: myjob"
    assert_output --partial "VERBOSE_MODE: true"
    assert_output --partial "COMMAND: status"
}

# -----------------------------------------------------------------------------
# Test Case: Command args include everything after command
# Spec: Command Syntax
# -----------------------------------------------------------------------------
@test "parse_command_args_preserved" {
    export PROJECT_DIR
    create_args_test_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" push origin main --force

    assert_success
    assert_output --partial "COMMAND: push"
    assert_output --partial "COMMAND_ARGS: origin main --force"
}
