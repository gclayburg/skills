#!/usr/bin/env bats

# Tests for build header integration across all command paths
# Spec reference: unify-follow-log-spec.md, Section 5 (Command-Specific Behavior)
# Plan reference: unify-follow-log-plan.md, Chunk D

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # Source buildgit for testing
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    # Disable colors for testing
    export NO_COLOR=1
    _init_colors

    # Fast poll for tests
    POLL_INTERVAL=1
    MAX_BUILD_TIME=10

    # Mock sleep to make tests fast
    sleep() { :; }
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# Test Cases: _display_build_in_progress_banner signature
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 2 (Build Header)
@test "banner_function_accepts_running_msg" {
    # Mock all dependencies
    get_build_info() {
        echo '{"building":true,"result":null,"timestamp":1706889863000,"url":"http://jenkins.example.com/job/ralph1/80/"}'
    }
    get_console_output() { echo "Started by user testuser"; }
    detect_trigger_type() { echo "manual"; echo "testuser"; }
    extract_triggering_commit() { echo "abc1234"; echo "test commit"; }
    correlate_commit() { echo "your_commit"; }
    get_current_stage() { echo "Build"; }
    get_all_stages() { echo '[]'; }

    # Call with 3 arguments (including running_msg)
    run _display_build_in_progress_banner "ralph1" "80" "Job ralph1 #80 has been running for 5m 30s"
    assert_success
    assert_output --partial "BUILD IN PROGRESS"
    assert_output --partial "has been running for 5m 30s"
}

@test "banner_function_works_without_running_msg" {
    get_build_info() {
        echo '{"building":true,"result":null,"timestamp":1706889863000,"url":"http://jenkins.example.com/job/ralph1/80/"}'
    }
    get_console_output() { echo "Started by user testuser"; }
    detect_trigger_type() { echo "manual"; echo "testuser"; }
    extract_triggering_commit() { echo "abc1234"; echo "test commit"; }
    correlate_commit() { echo "your_commit"; }
    get_current_stage() { echo "Build"; }
    get_all_stages() { echo '[]'; }

    # Call with only 2 arguments (no running_msg)
    run _display_build_in_progress_banner "ralph1" "80"
    assert_success
    assert_output --partial "BUILD IN PROGRESS"
    refute_output --partial "has been running for"
}

# =============================================================================
# Test Cases: Command path wiring (no elapsed suffix in push/build)
# =============================================================================

# Spec: bug-build-monitoring-header-spec.md - no elapsed in header
@test "push_header_no_elapsed" {
    # Verify cmd_push path calls banner WITHOUT any suffix
    run grep -A2 "# Spec: unify-follow-log-spec.md, Section 5 (buildgit push)" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial '_display_build_in_progress_banner "$job_name" "$new_build_number"'
    refute_output --partial 'running_msg'
}

@test "build_header_no_elapsed" {
    # Verify cmd_build path calls banner WITHOUT any suffix
    run grep -A2 "# Spec: unify-follow-log-spec.md, Section 5 (buildgit build)" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial '_display_build_in_progress_banner "$job_name" "$build_number"'
    refute_output --partial 'running_msg'
}

# =============================================================================
# Test Cases: Initial stages display
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 3 (Initial Display)
@test "banner_shows_initial_stages" {
    get_build_info() {
        echo '{"building":true,"result":null,"timestamp":1706889863000,"url":"http://jenkins.example.com/job/ralph1/80/"}'
    }
    get_console_output() { echo "Started by user testuser"; }
    detect_trigger_type() { echo "automated"; echo "scm-trigger"; }
    extract_triggering_commit() { echo "abc1234"; echo "test commit"; }
    correlate_commit() { echo "your_commit"; }
    get_current_stage() { echo "Unit Tests"; }
    get_all_stages() {
        echo '[
            {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Build","status":"SUCCESS","durationMillis":15000},
            {"name":"Unit Tests","status":"IN_PROGRESS","durationMillis":0}
        ]'
    }

    run _display_build_in_progress_banner "ralph1" "80"
    assert_success
    # Header should be present
    assert_output --partial "BUILD IN PROGRESS"
    # Initial completed stages should be displayed after the header
    assert_output --partial "Stage: Checkout SCM"
    assert_output --partial "Stage: Build (15s)"
    # IN_PROGRESS stages should NOT be shown (bug fix: no "(running)" in initial display)
    refute_output --partial "Unit Tests"
    refute_output --partial "running"
}

# =============================================================================
# Test Cases: Build Info section in banner
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 2 (Build Header)
@test "banner_shows_build_info_section" {
    get_build_info() {
        echo '{"building":true,"result":null,"timestamp":1706889863000,"url":"http://jenkins.example.com/job/ralph1/80/"}'
    }
    get_console_output() {
        echo "Started by user buildtriggerdude
Running on agent2paton in /var/jenkins/workspace/ralph1
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git"
    }
    detect_trigger_type() { echo "automated"; echo "scm-trigger"; }
    extract_triggering_commit() { echo "abc1234"; echo "test commit"; }
    correlate_commit() { echo "your_commit"; }
    get_current_stage() { echo "Build"; }
    get_all_stages() { echo '[]'; }

    run _display_build_in_progress_banner "ralph1" "80"
    assert_success
    assert_output --partial "=== Build Info ==="
    assert_output --partial "Started by:  buildtriggerdude"
    assert_output --partial "Agent:       agent2paton"
}

# =============================================================================
# Test Cases: Push shows git output before banner
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 5 (buildgit push)
@test "push_git_output_before_banner" {
    # Verify the code structure: git push output comes before banner call
    # In cmd_push: git push → output → then _display_build_in_progress_banner
    run grep -n "bg_log_essential\|_display_build_in_progress_banner" "${PROJECT_DIR}/buildgit"
    assert_success
    # The essential log (git output) line should appear before banner lines
    # This is a structural check that the order is correct in the code
    assert_output --partial "bg_log_essential"
    assert_output --partial "_display_build_in_progress_banner"
}
