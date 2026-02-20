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
    return 0
}

verify_job_exists() {
    local job_name="\$1"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}

get_last_build_number() {
    echo "42"
}

get_build_info() {
    local build_num="\$2"
    if [[ -z "\$build_num" ]]; then
        build_num="42"
    fi
    echo '{"number":'"\$build_num"',"result":"${build_result}","building":${is_building},"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/'"\$build_num"'/"}'
}

get_console_output() {
    echo "Started by user testuser"
    echo "Checking out Revision abc1234567890"
}

get_current_stage() {
    echo "Build"
}

fetch_test_results() {
    echo '{"passCount":120,"failCount":0,"skipCount":0}'
}

# Call the status command
cmd_status "\$@"
WRAPPER_START

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper for --line=N tests with multiple build outcomes
create_status_line_count_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER_START
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local build_num="\$2"
    case "\$build_num" in
        42) echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}' ;;
        41) echo '{"number":41,"result":"FAILURE","building":false,"timestamp":1706699700000,"duration":90000,"url":"http://jenkins.example.com/job/test-repo/41/"}' ;;
        40) echo '{"number":40,"result":"SUCCESS","building":false,"timestamp":1706699400000,"duration":80000,"url":"http://jenkins.example.com/job/test-repo/40/"}' ;;
        *) echo "" ;;
    esac
}
get_console_output() { echo "Started by user testuser"; }
fetch_test_results() {
    local build_num="\$2"
    case "\$build_num" in
        42) echo '{"passCount":100,"failCount":0,"skipCount":2}' ;;
        41) echo '{"passCount":90,"failCount":1,"skipCount":3}' ;;
        40) echo '{"passCount":80,"failCount":0,"skipCount":0}' ;;
        *) echo "" ;;
    esac
}

cmd_status "\$@"
WRAPPER_START

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper for --line alignment tests with mixed status lengths
create_status_line_alignment_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER_START
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local build_num="\$2"
    case "\$build_num" in
        42) echo '{"number":42,"result":"UNSTABLE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}' ;;
        41) echo '{"number":41,"result":"SUCCESS","building":false,"timestamp":1706699700000,"duration":90000,"url":"http://jenkins.example.com/job/test-repo/41/"}' ;;
        *) echo "" ;;
    esac
}
get_console_output() { echo "Started by user testuser"; }
fetch_test_results() {
    local build_num="\$2"
    case "\$build_num" in
        42) echo '{"passCount":10,"failCount":2,"skipCount":0}' ;;
        41) echo '{"passCount":12,"failCount":0,"skipCount":0}' ;;
        *) echo "" ;;
    esac
}

cmd_status "\$@"
WRAPPER_START

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper to force color variables in non-TTY tests
create_status_forced_color_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER_START
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

COLOR_GREEN=$'\033[32m'
COLOR_RED=$'\033[31m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'
COLOR_DIM=$'\033[2m'
COLOR_RESET=$'\033[0m'

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() { echo "Started by user testuser"; }
fetch_test_results() {
    echo '{"passCount":120,"failCount":0,"skipCount":0}'
}

cmd_status "\$@"
WRAPPER_START

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper to force color variables with failing tests in line mode
create_status_forced_color_fail_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER_START
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

COLOR_GREEN=$'\033[32m'
COLOR_RED=$'\033[31m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'
COLOR_DIM=$'\033[2m'
COLOR_RESET=$'\033[0m'

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() { echo "Started by user testuser"; }
fetch_test_results() {
    echo '{"passCount":95,"failCount":2,"skipCount":3}'
}

cmd_status "\$@"
WRAPPER_START

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper for unknown test report in line mode
create_status_tests_unknown_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER_START
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() { echo "Started by user testuser"; }
fetch_test_results() {
    echo ""
}

cmd_status "\$@"
WRAPPER_START

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper for --no-tests checks: if fetch_test_results is called, fail fast
create_status_no_tests_guard_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" << WRAPPER_START
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"

_BUILDGIT_TESTING=1
source "\${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    local job_name="\$1"
    JOB_URL="\${JENKINS_URL}/job/\${job_name}"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    local build_num="\$2"
    case "\$build_num" in
        42) echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}' ;;
        41) echo '{"number":41,"result":"FAILURE","building":false,"timestamp":1706699700000,"duration":90000,"url":"http://jenkins.example.com/job/test-repo/41/"}' ;;
        40) echo '{"number":40,"result":"SUCCESS","building":false,"timestamp":1706699400000,"duration":80000,"url":"http://jenkins.example.com/job/test-repo/40/"}' ;;
        *) echo "" ;;
    esac
}
get_console_output() { echo "Started by user testuser"; }
fetch_test_results() {
    echo "fetch_test_results should not be called with --no-tests" >&2
    return 99
}

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

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --all

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

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --all

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

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --all

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

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --all

    # Exit code 2 for building
    [ "$status" -eq 2 ]
    assert_output --partial "BUILD IN PROGRESS"
}

# =============================================================================
# Test Cases: Error Handling
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Shows Jenkins error when Jenkins is unavailable
# Spec: Error Handling - Jenkins Unavailable
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

# =============================================================================
# Test Cases: Specific Build Number (positional argument)
# Spec reference: feature-status-job-number-spec.md
# =============================================================================

# Helper: Create wrapper that records the build number passed to get_build_info
create_build_number_test_wrapper() {
    local expected_build="${1:-42}"

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
    JOB_URL="\${JENKINS_URL}/job/\${1}"
    return 0
}
get_last_build_number() { echo "99"; }
get_build_info() {
    local job_name="\$1"
    local build_num="\$2"
    echo "REQUESTED_BUILD: \$build_num" >&2
    echo '{"number":'"${expected_build}"',"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/'"${expected_build}"'/"}'
}
get_console_output() { echo "Started by user testuser"; }

cmd_status "\$@"
WRAPPER
    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# Helper: Create wrapper where get_build_info returns empty for specific build
create_build_not_found_wrapper() {
    local not_found_build="${1:-9999}"

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
    JOB_URL="\${JENKINS_URL}/job/\${1}"
    return 0
}
get_last_build_number() { echo "50"; }
get_build_info() {
    # Return empty to simulate build not found
    echo ""
}
get_console_output() { echo ""; }

cmd_status "\$@"
WRAPPER
    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

# -----------------------------------------------------------------------------
# Test Case: Status with specific build number
# Spec: feature-status-job-number-spec.md, Section 1
# -----------------------------------------------------------------------------
@test "status_specific_build_number" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "31"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 31 --all

    assert_success
    assert_output --partial "#31"
    assert_output --partial "BUILD SUCCESSFUL"
    # Verify it requested build 31, not the latest (99)
    assert_output --partial "REQUESTED_BUILD: 31"
}

# -----------------------------------------------------------------------------
# Test Case: Status with build number and --json
# Spec: feature-status-job-number-spec.md, Section 6
# -----------------------------------------------------------------------------
@test "status_specific_build_number_with_json" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "31"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 31 --json

    assert_success
    assert_output --partial '"job":'
    assert_output --partial '"build":'
}

# -----------------------------------------------------------------------------
# Test Case: Status with --json before build number (order independent)
# Spec: feature-status-job-number-spec.md, Section 1
# -----------------------------------------------------------------------------
@test "status_json_before_build_number" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "31"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --json 31

    assert_success
    assert_output --partial '"job":'
    assert_output --partial '"build":'
}

# -----------------------------------------------------------------------------
# Test Case: Invalid build number (not a positive integer)
# Spec: feature-status-job-number-spec.md, Section 1
# -----------------------------------------------------------------------------
@test "status_invalid_build_number_text" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "42"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" abc

    assert_failure
    assert_output --partial "Invalid build number: abc"
    assert_output --partial "must be a positive integer"
}

@test "status_invalid_build_number_zero" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "42"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 0

    assert_failure
    assert_output --partial "Invalid build number: 0"
}

@test "status_invalid_build_number_negative" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "42"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -5

    assert_failure
    # -5 will be caught as an unknown option
    assert_output --partial "Unknown option for status command: -5"
}

# -----------------------------------------------------------------------------
# Test Case: Follow mode with build number is an error
# Spec: feature-status-job-number-spec.md, Section 2
# -----------------------------------------------------------------------------
@test "status_follow_with_build_number_errors" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "31"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 31 -f

    assert_failure
    assert_output --partial "Cannot use --follow with a specific build number"
}

@test "status_follow_before_build_number_errors" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "31"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -f 31

    assert_failure
    assert_output --partial "Cannot use --follow with a specific build number"
}

# -----------------------------------------------------------------------------
# Test Case: Non-existent build number
# Spec: feature-status-job-number-spec.md, Section 4
# -----------------------------------------------------------------------------
@test "status_nonexistent_build_number" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_not_found_wrapper "9999"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 9999 --all

    assert_failure
    assert_output --partial "Build #9999 not found for job"
}

# -----------------------------------------------------------------------------
# Test Case: Without build number still fetches latest
# Spec: feature-status-job-number-spec.md, Section 3
# -----------------------------------------------------------------------------
@test "status_without_build_number_uses_latest" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "99"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --all

    assert_success
    # Should use the latest build (99) from get_last_build_number
    assert_output --partial "REQUESTED_BUILD: 99"
}

# =============================================================================
# Test Cases: Usage Help on Subcommand Help and Invalid Options
# Spec reference: usage-help-spec.md
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: status -h prints usage to stdout and exits 0
# Spec: usage-help-spec.md, Acceptance Criteria 1
# -----------------------------------------------------------------------------
@test "status_help_short_flag" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status -h

    assert_success
    assert_output --partial "Usage: buildgit"
    assert_output --partial "Commands:"
}

# -----------------------------------------------------------------------------
# Test Case: status --help prints usage to stdout and exits 0
# Spec: usage-help-spec.md, Acceptance Criteria 2
# -----------------------------------------------------------------------------
@test "status_help_long_flag" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status --help

    assert_success
    assert_output --partial "Usage: buildgit"
    assert_output --partial "Commands:"
}

# -----------------------------------------------------------------------------
# Test Case: status -junk prints error + usage to stderr and exits non-zero
# Spec: usage-help-spec.md, Acceptance Criteria 5
# -----------------------------------------------------------------------------
@test "status_unknown_short_option_shows_usage" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status -junk

    assert_failure
    assert_output --partial "Unknown option for status command: -junk"
    assert_output --partial "Usage: buildgit"
}

# -----------------------------------------------------------------------------
# Test Case: status --garbage prints error + usage to stderr and exits non-zero
# Spec: usage-help-spec.md, Acceptance Criteria 6
# -----------------------------------------------------------------------------
@test "status_unknown_long_option_shows_usage" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status --garbage

    assert_failure
    assert_output --partial "Unknown option for status command: --garbage"
    assert_output --partial "Usage: buildgit"
}

# -----------------------------------------------------------------------------
# Test Case: status abc (invalid build number) prints error + usage
# Spec: usage-help-spec.md, Acceptance Criteria 7
# -----------------------------------------------------------------------------
@test "status_invalid_build_number_shows_usage" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status abc

    assert_failure
    assert_output --partial "Invalid build number: abc"
    assert_output --partial "Usage: buildgit"
}

# -----------------------------------------------------------------------------
# Test Case: status 5 10 (unexpected argument) prints error + usage
# Spec: usage-help-spec.md, Acceptance Criteria 8
# -----------------------------------------------------------------------------
@test "status_unexpected_argument_shows_usage" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_build_number_test_wrapper "42"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 5 10

    assert_failure
    assert_output --partial "Unexpected argument: 10"
    assert_output --partial "Usage: buildgit"
}

# =============================================================================
# Test Cases: Quick One-Line Status
# Spec reference: 2026-02-15_quick-status-line-spec.md
# =============================================================================

@test "status_line_completed" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    assert_output --regexp "^SUCCESS[[:space:]]+Job test-repo #42 Tests=120/0/0 Took 2m 0s on [0-9]{4}-[0-9]{2}-[0-9]{2} \\(.*\\)$"
    line_count="$(printf "%s\n" "$output" | wc -l | tr -d ' ')"
    [ "$line_count" -eq 1 ]
}

@test "status_line_in_progress" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "null" "true"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_failure
    assert_output --regexp "^IN_PROGRESS Job test-repo #42 Tests=\\?/\\?/\\? running for .* \\(started [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\\)$"
    line_count="$(printf "%s\n" "$output" | wc -l | tr -d ' ')"
    [ "$line_count" -eq 1 ]
}

@test "status_line_short_flag" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -l

    assert_success
    assert_output --partial "SUCCESS     Job test-repo #42 Tests=120/0/0 Took 2m 0s"
}

@test "status_all_short_flag_forces_full_output" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -a

    assert_success
    assert_output --partial "BUILD SUCCESSFUL"
}

@test "status_default_non_tty_is_line" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh"

    assert_success
    assert_output --regexp "^SUCCESS[[:space:]]+Job test-repo #42 Tests=120/0/0 Took 2m 0s on [0-9]{4}-[0-9]{2}-[0-9]{2} \\(.*\\)$"
}

@test "status_line_with_specific_build_number" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 31 --line

    assert_success
    assert_output --partial "SUCCESS     Job test-repo #31 Tests=120/0/0 Took 2m 0s"
}

@test "status_line_rejects_all" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line --all

    assert_failure
    assert_output --partial "Cannot use --line with --all"
    assert_output --partial "Usage: buildgit"
}

@test "status_line_rejects_json" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line --json

    assert_failure
    assert_output --partial "Cannot use --line with --json"
    assert_output --partial "Usage: buildgit"
}

@test "status_line_rejects_follow" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line --follow

    assert_failure
    assert_output --partial "Cannot use --line with --follow"
    assert_output --partial "Usage: buildgit"
}

@test "status_line_count_2" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_line_count_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 2 --line

    assert_success
    assert_output --partial "SUCCESS     Job test-repo #42"
    assert_output --partial "FAILURE     Job test-repo #41"
    line_count="$(printf "%s\n" "$output" | wc -l | tr -d ' ')"
    [ "$line_count" -eq 2 ]
}

@test "status_line_count_10_prints_available_history" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_line_count_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 10 --line

    assert_success
    assert_output --partial "SUCCESS     Job test-repo #42"
    assert_output --partial "FAILURE     Job test-repo #41"
    assert_output --partial "SUCCESS     Job test-repo #40"
    line_count="$(printf "%s\n" "$output" | wc -l | tr -d ' ')"
    [ "$line_count" -eq 3 ]
}

@test "status_line_with_build_number_and_count" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_line_count_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 41 -n 2 --line

    # Oldest-first: #40 (SUCCESS) on line 1, #41 (FAILURE) on line 2 (newest/last)
    assert_failure
    first_line="$(printf "%s\n" "$output" | sed -n '1p')"
    [ "${first_line#SUCCESS     Job test-repo #40}" != "$first_line" ]
    last_line="$(printf "%s\n" "$output" | tail -n 1)"
    [ "${last_line#FAILURE     Job test-repo #41}" != "$last_line" ]
}

@test "status_line_invalid_count_zero" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 0 --line

    assert_failure
    assert_output --partial "-n requires a positive integer argument"
    assert_output --partial "Usage: buildgit"
}

@test "status_line_invalid_count_text" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n abc --line

    assert_failure
    assert_output --partial "-n requires a positive integer argument"
    assert_output --partial "Usage: buildgit"
}

@test "status_line_equals_syntax_error" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line=5

    assert_failure
    assert_output --partial "--line does not accept a value"
    assert_output --partial "-n <count>"
    assert_output --partial "Usage: buildgit"
}

@test "status_line_n_no_arg_error" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n --line

    assert_failure
    assert_output --partial "-n requires a positive integer argument"
    assert_output --partial "Usage: buildgit"
}

@test "status_line_n_ordering_oldest_first" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_line_count_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 3 --line

    assert_success
    # Output must be in ascending build number order: #40, #41, #42
    line1="$(printf "%s\n" "$output" | sed -n '1p')"
    line2="$(printf "%s\n" "$output" | sed -n '2p')"
    line3="$(printf "%s\n" "$output" | sed -n '3p')"
    [ "${line1#*Job test-repo #40}" != "$line1" ]
    [ "${line2#*Job test-repo #41}" != "$line2" ]
    [ "${line3#*Job test-repo #42}" != "$line3" ]
}

@test "status_line_n_without_line_mode_ignored" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_line_count_wrapper

    # -n without --line: ignored, full mode runs (no --all either, so TTY detection applies;
    # since tests run without a TTY, non-TTY default (line mode) kicks in showing 1 build)
    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 5

    # In non-TTY context the default is one-line mode; -n is silently ignored so only 1 build shown
    line_count="$(printf "%s\n" "$output" | wc -l | tr -d ' ')"
    [ "$line_count" -eq 1 ]
}

@test "status_line_count_exit_code_uses_last_line_only" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_line_count_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 3 --line

    # Last line is newest (#42, SUCCESS), so overall exit should be success
    assert_success
    assert_output --partial "FAILURE     Job test-repo #41"
    last_line="$(printf "%s\n" "$output" | tail -n 1)"
    [ "${last_line#SUCCESS     Job test-repo #42}" != "$last_line" ]
}

@test "status_line_result_padded" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    status_field="$(printf "%s\n" "$output" | awk -F' Job ' '{print $1}')"
    [ "$status_field" = "SUCCESS    " ]
    [ "${#status_field}" -eq 11 ]
}

@test "status_line_aligned_output" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_line_alignment_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 2 --line

    assert_failure
    line1="$(printf "%s\n" "$output" | sed -n '1p')"
    line2="$(printf "%s\n" "$output" | sed -n '2p')"
    prefix1="${line1%%Job*}"
    prefix2="${line2%%Job*}"
    col1=$(( ${#prefix1} + 1 ))
    col2=$(( ${#prefix2} + 1 ))
    [ "$col1" -eq "$col2" ]
}

@test "status_line_no_color_in_pipe" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    if printf "%s" "$output" | grep -q $'\033\['; then
        fail "Expected no ANSI color codes in non-TTY output"
    fi
}

@test "status_line_color_when_color_vars_set" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_forced_color_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    if ! printf "%s" "$output" | grep -Fq $'\033[32mSUCCESS    \033[0m Job test-repo #42'; then
        fail "Expected SUCCESS status field to be colored and padded"
    fi
    if ! printf "%s" "$output" | grep -Fq $' \033[32mTests=120/0/0\033[0m Took '; then
        fail "Expected Tests field to be green when failCount=0"
    fi
}

@test "status_line_tests_unknown" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_tests_unknown_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    assert_output --partial "SUCCESS     Job test-repo #42 Tests=?/?/? Took 2m 0s"
}

@test "status_line_took_wording" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_test_wrapper "SUCCESS" "false"

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    assert_output --partial " Took 2m 0s"
    refute_output --partial "completed in"
}

@test "status_line_tests_yellow_when_failures" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_forced_color_fail_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    if ! printf "%s" "$output" | grep -Fq $' \033[33mTests=95/2/3\033[0m Took '; then
        fail "Expected Tests field to be yellow when failCount>0"
    fi
}

@test "status_line_tests_unknown_no_color" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_tests_unknown_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line

    assert_success
    assert_output --partial "Tests=?/?/?"
    if printf "%s" "$output" | grep -Eq $'\\033\\[[0-9;]*mTests=\\?/\\?/\\?'; then
        fail "Expected unknown Tests field to be uncolored"
    fi
}

@test "status_line_no_tests_flag" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_no_tests_guard_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" --line --no-tests

    assert_success
    assert_output --partial "SUCCESS     Job test-repo #42 Tests=?/?/? Took 2m 0s"
}

@test "status_line_no_tests_with_count" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    create_status_no_tests_guard_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" -n 3 --line --no-tests

    assert_success
    line_count="$(printf "%s\n" "$output" | wc -l | tr -d ' ')"
    [ "$line_count" -eq 3 ]
    tests_unknown_count="$(printf "%s\n" "$output" | grep -Ec 'Tests=\?/\?/\?' || true)"
    [ "$tests_unknown_count" -eq 3 ]
}
