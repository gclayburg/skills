#!/usr/bin/env bats

# Tests for buildgit status command - basic functionality
# Spec reference: buildgit-spec.md, buildgit status
# Plan reference: buildgit-plan.md, Chunk 4

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
# Helper: Create wrapper script with mocked Jenkins functions
# =============================================================================

create_status_test_wrapper() {
    local build_result="${1:-SUCCESS}"
    local is_building="${2:-false}"

    # Create a modified copy of buildgit:
    # 1. Remove the main() call at the end
    # 2. Replace SCRIPT_DIR with PROJECT_DIR for sourcing jenkins-common.sh
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER_START
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

# Source buildgit without executing main
_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

# Override Jenkins API functions with mocks
verify_jenkins_connection() {
    log_success "Connected to Jenkins"
    return 0
}

verify_job_exists() {
    local job_name="\$1"
    log_success "Job '\$job_name' found"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}

get_last_build_number() {
    echo "42"
}

get_build_info() {
    echo '{"number":42,"result":"${build_result}","building":${is_building},"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}

get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}

get_current_stage() {
    echo "Build"
}

# Call the status command
cmd_status "\$@"
WRAPPER_START

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper for Jenkins unavailable scenario
create_jenkins_unavailable_wrapper() {
    # Create a modified copy of buildgit:
    # 1. Remove the main() call at the end
    # 2. Replace SCRIPT_DIR with PROJECT_DIR for sourcing jenkins-common.sh
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

# Source buildgit without executing main
_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

# Override Jenkins API functions to simulate unavailability
verify_jenkins_connection() {
    log_error "Failed to connect to Jenkins (HTTP 503)"
    return 1
}

# Call the status command
cmd_status "\$@"
WRAPPER

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# =============================================================================
# Test Cases: Basic Status Output
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Status shows Jenkins build status
# Spec: buildgit status - "Display Jenkins build status"
# -----------------------------------------------------------------------------
@test "status_shows_jenkins_status" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Should show Jenkins build information
    assert_output --partial "BUILD SUCCESSFUL"
    assert_output --partial "Build:"
    assert_output --partial "#42"
}

# =============================================================================
# Test Cases: JSON Output
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: --json outputs JSON build status
# Spec: buildgit status Options - "--json: Output Jenkins status in JSON format"
# -----------------------------------------------------------------------------
@test "status_json_output" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --json

    assert_success
    # Should have JSON output for Jenkins status
    assert_output --partial '"job":'
    assert_output --partial '"build":'
    assert_output --partial '"status":'
}

# =============================================================================
# Test Cases: Job Flag
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Global --job flag is used for Jenkins status
# Spec: Global Options - "-j, --job <name>: Specify Jenkins job name"
# -----------------------------------------------------------------------------
@test "status_with_job_flag" {
    cd "${TEST_REPO}"

    # Create a modified copy of buildgit:
    # 1. Remove the main() call at the end
    # 2. Replace SCRIPT_DIR with PROJECT_DIR for sourcing jenkins-common.sh
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    # Create wrapper that checks job name
    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

# Source buildgit without executing main
_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    echo "VERIFIED_JOB: \$job_name"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/custom-job/42/"}'
}
get_console_output() { echo "Started by user testuser"; }

# Set the global JOB_NAME as if it came from global option parsing
JOB_NAME="custom-job"
cmd_status "\$@"
WRAPPER
    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    assert_success
    assert_output --partial "VERIFIED_JOB: custom-job"
}

# -----------------------------------------------------------------------------
# Test Case: --json works together with global --job flag
# Spec: Global Options + buildgit status Options
# -----------------------------------------------------------------------------
@test "status_json_with_job_flag" {
    cd "${TEST_REPO}"

    # Create wrapper that verifies job name AND outputs JSON
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    echo "VERIFIED_JOB: \$job_name"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/custom-job/42/"}'
}
get_console_output() { echo "Started by user testuser"; }

JOB_NAME="custom-job"
cmd_status "\$@"
WRAPPER
    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --json

    assert_success
    assert_output --partial "VERIFIED_JOB: custom-job"
    assert_output --partial '"job":'
    assert_output --partial '"status":'
}

# =============================================================================
# Test Cases: Exit Codes
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Exit 0 for successful build
# Spec: Exit Codes - "Success (git OK, build OK): 0"
# -----------------------------------------------------------------------------
@test "status_exit_code_success" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    assert_success  # exit code 0
    assert_output --partial "BUILD SUCCESSFUL"
}

# -----------------------------------------------------------------------------
# Test Case: Exit 1 for failed build
# Spec: Exit Codes - "Jenkins build fails: Non-zero"
# -----------------------------------------------------------------------------
@test "status_exit_code_failure" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    create_status_test_wrapper "FAILURE" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    assert_failure  # exit code non-zero (1)
    assert_output --partial "BUILD FAILED"
}

# -----------------------------------------------------------------------------
# Test Case: Exit 2 for in-progress build
# Spec: Exit Codes - matches checkbuild.sh behavior (exit 2 for building)
# -----------------------------------------------------------------------------
@test "status_exit_code_building" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    create_status_test_wrapper "null" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Exit code 2 for building
    [ "$status" -eq 2 ]
    assert_output --partial "BUILD IN PROGRESS"
}

# =============================================================================
# Test Cases: Error Handling
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Shows git status even when Jenkins is unavailable
# Spec: Error Handling - "Git operations should still be attempted and complete"
# -----------------------------------------------------------------------------
@test "status_jenkins_unavailable" {
    cd "${TEST_REPO}"

    export PROJECT_DIR
    create_jenkins_unavailable_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    # Should fail (Jenkins unavailable)
    assert_failure
    # Should show Jenkins error
    assert_output --partial "Failed to connect to Jenkins"
}

# NOTE: Follow mode tests have been moved to test/buildgit_status_follow.bats
# as part of Chunk 5 implementation.
