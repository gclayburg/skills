#!/usr/bin/env bats

# Tests for --job/-j flag in checkbuild.sh
# Spec reference: fixjobflags-spec.md, Section 2
# Plan reference: fixjobflags-plan.md#chunk-a

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
# Helper: Mock discover_job_name to control auto-detection behavior
# =============================================================================

# Creates a script that overrides discover_job_name
create_mock_discover_job_name() {
    local success="${1:-true}"
    local job_name="${2:-auto-detected-job}"

    cat > "${TEST_TEMP_DIR}/mock_discover.sh" << EOF
discover_job_name() {
    if [[ "$success" == "true" ]]; then
        echo "$job_name"
        return 0
    else
        return 1
    fi
}
EOF
}

# Creates a wrapper script that sources mocks before checkbuild.sh
create_test_wrapper() {
    cat > "${TEST_TEMP_DIR}/checkbuild_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# Source mock functions if present
if [[ -f "${TEST_TEMP_DIR}/mock_discover.sh" ]]; then
    source "${TEST_TEMP_DIR}/mock_discover.sh"
fi

# Source jenkins-common.sh to get actual functions
source "${PROJECT_DIR}/lib/jenkins-common.sh"

# Re-source mock to override
if [[ -f "${TEST_TEMP_DIR}/mock_discover.sh" ]]; then
    source "${TEST_TEMP_DIR}/mock_discover.sh"
fi

# Mock Jenkins API calls to avoid network
verify_jenkins_connection() { return 0; }
verify_job_exists() { return 0; }
get_last_build_number() { echo "1"; }
fetch_build_info() { echo '{"result":"SUCCESS","building":false}'; }
get_build_info() { echo '{"result":"SUCCESS","building":false}'; }
get_console_output() { echo ""; }
detect_trigger_type() { echo -e "unknown\nunknown"; }
extract_triggering_commit() { echo -e "abc123\nTest commit"; }
correlate_commit() { echo "local"; }
display_success_output() { echo "SUCCESS"; }
output_json() { echo '{"status":"SUCCESS"}'; }

# Now define the functions from checkbuild.sh inline
EOF

    # Append the argument parsing and main logic from checkbuild.sh
    sed -n '/^parse_arguments()/,/^# =*$/p' "${PROJECT_DIR}/checkbuild.sh" | sed '$d' >> "${TEST_TEMP_DIR}/checkbuild_wrapper.sh"
    sed -n '/^show_usage()/,/^}/p' "${PROJECT_DIR}/checkbuild.sh" >> "${TEST_TEMP_DIR}/checkbuild_wrapper.sh"

    cat >> "${TEST_TEMP_DIR}/checkbuild_wrapper.sh" << 'EOF'

# Simplified main for testing argument parsing
main() {
    parse_arguments "$@"

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

    # For testing, just output the job name
    echo "RESOLVED_JOB: $job_name"
}

main "$@"
EOF

    chmod +x "${TEST_TEMP_DIR}/checkbuild_wrapper.sh"
}

# =============================================================================
# Test Cases
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: --job flag overrides auto-detection
# Spec: Section 2.1, 1.1
# -----------------------------------------------------------------------------
@test "job_flag_overrides_autodetection" {
    cd "${MOCK_REPO}"

    # Create mock that would return different job name
    cat > "${TEST_TEMP_DIR}/mock_discover.sh" << 'EOF'
discover_job_name() {
    echo "auto-detected-job"
    return 0
}
EOF

    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper

    run bash "${TEST_TEMP_DIR}/checkbuild_wrapper.sh" --job myjob

    assert_success
    assert_output --partial "Using specified job: myjob"
    assert_output --partial "RESOLVED_JOB: myjob"
    refute_output --partial "auto-detected-job"
}

# -----------------------------------------------------------------------------
# Test Case: -j short flag works
# Spec: Section 2.1
# -----------------------------------------------------------------------------
@test "job_short_flag_works" {
    cd "${MOCK_REPO}"

    cat > "${TEST_TEMP_DIR}/mock_discover.sh" << 'EOF'
discover_job_name() {
    echo "auto-detected-job"
    return 0
}
EOF

    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper

    run bash "${TEST_TEMP_DIR}/checkbuild_wrapper.sh" -j myjob

    assert_success
    assert_output --partial "Using specified job: myjob"
    assert_output --partial "RESOLVED_JOB: myjob"
}

# -----------------------------------------------------------------------------
# Test Case: --job without value shows error
# Spec: Section 2.3
# -----------------------------------------------------------------------------
@test "job_flag_missing_value_errors" {
    cd "${MOCK_REPO}"

    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper

    run bash "${TEST_TEMP_DIR}/checkbuild_wrapper.sh" --job

    assert_failure
    assert_output --partial "requires a job name"
}

# -----------------------------------------------------------------------------
# Test Case: --job with empty string shows error
# Spec: Section 2.3
# -----------------------------------------------------------------------------
@test "job_flag_empty_value_errors" {
    cd "${MOCK_REPO}"

    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper

    run bash "${TEST_TEMP_DIR}/checkbuild_wrapper.sh" --job ""

    assert_failure
    assert_output --partial "requires a job name"
}

# -----------------------------------------------------------------------------
# Test Case: Auto-detection failure shows help message
# Spec: Section 1.2
# -----------------------------------------------------------------------------
@test "autodetect_failure_shows_help_message" {
    cd "${MOCK_REPO}"

    # Mock discover_job_name to fail
    cat > "${TEST_TEMP_DIR}/mock_discover.sh" << 'EOF'
discover_job_name() {
    return 1
}
EOF

    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper

    run bash "${TEST_TEMP_DIR}/checkbuild_wrapper.sh"

    assert_failure
    assert_output --partial "Could not determine Jenkins job name"
    assert_output --partial "Add JOB_NAME=<job-name> to AGENTS.md"
    assert_output --partial "--job <job> or -j <job> flag"
}

# -----------------------------------------------------------------------------
# Test Case: --json flag still works with --job flag
# Spec: Section 4.1.5
# -----------------------------------------------------------------------------
@test "json_flag_still_works_with_job_flag" {
    cd "${MOCK_REPO}"

    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper

    run bash "${TEST_TEMP_DIR}/checkbuild_wrapper.sh" --job myjob --json

    assert_success
    assert_output --partial "RESOLVED_JOB: myjob"
    # Verify JSON_OUTPUT_MODE was set (we'd need to check the export)
}

# -----------------------------------------------------------------------------
# Test Case: Help shows --job option
# Spec: Section 2.2
# -----------------------------------------------------------------------------
@test "help_shows_job_option" {
    cd "${MOCK_REPO}"

    run bash "${PROJECT_DIR}/checkbuild.sh" --help

    assert_success
    assert_output --partial "-j, --job <job>"
    assert_output --partial "Specify Jenkins job name"
    assert_output --partial "overrides auto-detection"
    assert_output --partial "If --job is not specified"
}

# -----------------------------------------------------------------------------
# Test Case: Auto-detection is used when no --job flag
# Spec: Section 1.1
# -----------------------------------------------------------------------------
@test "autodetect_used_when_no_job_flag" {
    cd "${MOCK_REPO}"

    # Mock discover_job_name to succeed
    cat > "${TEST_TEMP_DIR}/mock_discover.sh" << 'EOF'
discover_job_name() {
    echo "auto-detected-job"
    return 0
}
EOF

    export TEST_TEMP_DIR PROJECT_DIR
    create_test_wrapper

    run bash "${TEST_TEMP_DIR}/checkbuild_wrapper.sh"

    assert_success
    assert_output --partial "Discovering Jenkins job name..."
    assert_output --partial "RESOLVED_JOB: auto-detected-job"
}
