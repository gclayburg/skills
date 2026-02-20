#!/usr/bin/env bats

# Tests for buildgit follow mode build info banner display
# Spec reference: bug2026-02-01-buildgit-monitoring-spec.md, Issue 1
# Plan reference: bug2026-02-01-buildgit-monitoring-plan.md, Chunk B

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
# Helper: Create test wrapper with mocked Jenkins functions
# =============================================================================

create_banner_test_wrapper() {
    local mock_build_json="$1"
    local mock_console_output="$2"
    local mock_current_stage="$3"

    cat > "${TEST_TEMP_DIR}/banner_test.sh" << WRAPPER_EOF
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR}"

# Source jenkins-common.sh for display functions
source "\${PROJECT_DIR}/lib/jenkins-common.sh"

# Global variables
VERBOSE_MODE=false
JOB_NAME=""
POLL_INTERVAL=1
MAX_BUILD_TIME=60

# Verbosity-aware logging functions (from buildgit)
bg_log_info() {
    if [[ "\$VERBOSE_MODE" == "true" ]]; then
        log_info "\$@" >&2
    fi
}

bg_log_success() {
    if [[ "\$VERBOSE_MODE" == "true" ]]; then
        log_success "\$@" >&2
    fi
}

bg_log_warning() {
    log_warning "\$@"
}

bg_log_error() {
    log_error "\$@"
}

bg_log_essential() {
    echo "\$@"
}

# Mock functions that replace Jenkins API calls
get_build_info() {
    cat << 'MOCK_JSON'
${mock_build_json}
MOCK_JSON
}

get_console_output() {
    cat << 'MOCK_CONSOLE'
${mock_console_output}
MOCK_CONSOLE
}

get_current_stage() {
    echo "${mock_current_stage}"
}

get_last_build_number() {
    echo "53"
}

# _display_build_in_progress_banner function (from buildgit)
_display_build_in_progress_banner() {
    local job_name="\$1"
    local build_number="\$2"

    # Get build info
    local build_json
    build_json=\$(get_build_info "\$job_name" "\$build_number")

    if [[ -z "\$build_json" ]]; then
        bg_log_warning "Could not fetch build info for banner display"
        return 0
    fi

    # Get console output for trigger detection and commit extraction
    local console_output
    console_output=\$(get_console_output "\$job_name" "\$build_number" 2>/dev/null) || true

    # Detect trigger type
    local trigger_type trigger_user
    if [[ -n "\$console_output" ]]; then
        local trigger_info
        trigger_info=\$(detect_trigger_type "\$console_output")
        trigger_type=\$(echo "\$trigger_info" | head -1)
        trigger_user=\$(echo "\$trigger_info" | tail -1)
    else
        trigger_type="unknown"
        trigger_user="unknown"
    fi

    # Extract triggering commit
    local commit_info commit_sha commit_msg
    commit_info=\$(extract_triggering_commit "\$job_name" "\$build_number" "\$console_output")
    commit_sha=\$(echo "\$commit_info" | head -1)
    commit_msg=\$(echo "\$commit_info" | tail -1)

    # Correlate commit with local history
    local correlation_status
    correlation_status=\$(correlate_commit "\$commit_sha")

    # Get current stage
    local current_stage
    current_stage=\$(get_current_stage "\$job_name" "\$build_number" 2>/dev/null) || true

    # Display the banner using existing display function
    display_building_output "\$job_name" "\$build_number" "\$build_json" \\
        "\$trigger_type" "\$trigger_user" \\
        "\$commit_sha" "\$commit_msg" \\
        "\$correlation_status" "\$current_stage"
}

# Test harness
main() {
    local action="\${1:-}"

    case "\$action" in
        "display_banner")
            local job_name="\${2:-ralph1}"
            local build_number="\${3:-53}"
            _display_build_in_progress_banner "\$job_name" "\$build_number"
            ;;
        *)
            echo "Unknown action: \$action"
            exit 1
            ;;
    esac
}

main "\$@"
WRAPPER_EOF
    chmod +x "${TEST_TEMP_DIR}/banner_test.sh"
}

# =============================================================================
# Test Cases: Banner Display in Follow Mode
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Banner is displayed for in-progress build
# Spec: Issue 1 - Missing Build Information in Follow Mode
# -----------------------------------------------------------------------------
@test "follow_mode_shows_banner_for_in_progress_build" {
    create_banner_test_wrapper \
        '{"number": 53, "building": true, "result": null, "timestamp": 1706784684000, "duration": 0, "url": "http://jenkins.example.com/job/ralph1/53/"}' \
        'Started by user buildtriggerdude
Obtained Jenkinsfile from git ssh://git@server/ralph1.git
Running on agent1
> git checkout -f abc1234' \
        'Unit Tests'

    run bash "${TEST_TEMP_DIR}/banner_test.sh" display_banner ralph1 53

    assert_success
    # Check for BUILD IN PROGRESS banner
    assert_output --partial "BUILD IN PROGRESS"
}

# -----------------------------------------------------------------------------
# Test Case: Banner shows job name
# Spec: Issue 1 - Missing Build Information in Follow Mode
# -----------------------------------------------------------------------------
@test "follow_mode_banner_shows_job_name" {
    create_banner_test_wrapper \
        '{"number": 53, "building": true, "result": null, "timestamp": 1706784684000, "duration": 0, "url": "http://jenkins.example.com/job/ralph1/53/"}' \
        'Started by user testuser' \
        'Build'

    run bash "${TEST_TEMP_DIR}/banner_test.sh" display_banner ralph1 53

    assert_success
    assert_output --partial "Job:        ralph1"
}

# -----------------------------------------------------------------------------
# Test Case: Banner shows build number
# Spec: Issue 1 - Missing Build Information in Follow Mode
# -----------------------------------------------------------------------------
@test "follow_mode_banner_shows_build_number" {
    create_banner_test_wrapper \
        '{"number": 53, "building": true, "result": null, "timestamp": 1706784684000, "duration": 0, "url": "http://jenkins.example.com/job/ralph1/53/"}' \
        'Started by user testuser' \
        'Build'

    run bash "${TEST_TEMP_DIR}/banner_test.sh" display_banner ralph1 53

    assert_success
    assert_output --partial "Build:      #53"
}

# -----------------------------------------------------------------------------
# Test Case: Banner no longer shows current stage in header (stages streamed separately)
# Spec: unify-follow-log-spec.md, Section 2 - stages removed from header
# (Updated: stages removed from header per unified output spec)
# -----------------------------------------------------------------------------
@test "follow_mode_banner_shows_current_stage" {
    create_banner_test_wrapper \
        '{"number": 53, "building": true, "result": null, "timestamp": 1706784684000, "duration": 0, "url": "http://jenkins.example.com/job/ralph1/53/"}' \
        'Started by user testuser' \
        'Unit Tests'

    run bash "${TEST_TEMP_DIR}/banner_test.sh" display_banner ralph1 53

    assert_success
    # Stages are no longer displayed in the header per unified output spec
    # They are streamed separately by the monitoring loop
    assert_output --partial "BUILD IN PROGRESS"
}

# -----------------------------------------------------------------------------
# Test Case: Banner shows BUILDING status
# Spec: Issue 1 - Missing Build Information in Follow Mode
# -----------------------------------------------------------------------------
@test "follow_mode_banner_shows_building_status" {
    create_banner_test_wrapper \
        '{"number": 53, "building": true, "result": null, "timestamp": 1706784684000, "duration": 0, "url": "http://jenkins.example.com/job/ralph1/53/"}' \
        'Started by user testuser' \
        'Build'

    run bash "${TEST_TEMP_DIR}/banner_test.sh" display_banner ralph1 53

    assert_success
    assert_output --partial "BUILDING"
}

# =============================================================================
# Test Cases: Integration with buildgit script
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Verify buildgit has _display_build_in_progress_banner function
# Spec: Issue 1 - Implementation Details
# -----------------------------------------------------------------------------
@test "buildgit_has_display_banner_function" {
    run grep -c "_display_build_in_progress_banner()" "${PROJECT_DIR}/buildgit"
    assert_success
    # Should find the function definition (at least 1 match)
    [[ "$output" -ge 1 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Verify _cmd_status_follow calls banner function for in-progress builds
# Spec: Issue 1 - Implementation Details
# -----------------------------------------------------------------------------
@test "cmd_status_follow_calls_banner_for_in_progress_build" {
    # Check that _cmd_status_follow contains the banner function call
    run grep -A80 'if \[\[ "\$building" == "true" \]\]' "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_display_build_in_progress_banner"
}

# -----------------------------------------------------------------------------
# Test Case: Verify banner is called before monitoring loop
# Spec: Issue 1 - Banner appears before monitoring messages
# -----------------------------------------------------------------------------
@test "follow_mode_banner_before_monitoring" {
    # Verify _display_build_in_progress_banner appears before _monitor_build
    # by checking line numbers in the source file
    run bash -c "
        grep -n '_display_build_in_progress_banner\|_monitor_build' '${PROJECT_DIR}/buildgit' | \
        grep -v '()' | grep -v '^[0-9]*:#'
    "
    assert_success

    local banner_line monitor_line
    banner_line=$(echo "$output" | grep '_display_build_in_progress_banner' | tail -1 | cut -d: -f1)
    monitor_line=$(echo "$output" | grep '_monitor_build' | tail -1 | cut -d: -f1)

    # Banner should come before monitor in _cmd_status_follow
    [[ "$banner_line" -lt "$monitor_line" ]]
}
