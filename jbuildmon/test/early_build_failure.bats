#!/usr/bin/env bats

# Unit tests for early build failure console display
# Spec reference: buildgit-early-build-failure-spec.md

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
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# Test Cases: _display_early_failure_console helper
# =============================================================================

@test "early_failure_detected_when_no_stages" {
    get_all_stages() { echo "[]"; }

    local console="Started by user admin
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:
WorkflowScript: 3: error
Finished: FAILURE"

    run _display_early_failure_console "testjob" "42" "$console"
    assert_success
    assert_output --partial "=== Console Output ==="
    assert_output --partial "MultipleCompilationErrorsException"
    assert_output --partial "======================"
}

@test "early_failure_not_triggered_when_stages_exist" {
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }

    run _display_early_failure_console "testjob" "42" "some console output"
    assert_failure
}

@test "early_failure_shows_full_console_output" {
    get_all_stages() { echo "[]"; }

    local console="Line 1
Line 2
Line 3
org.codehaus.groovy.control.MultipleCompilationErrorsException
Line 5"

    run _display_early_failure_console "testjob" "42" "$console"
    assert_success
    assert_output --partial "Line 1"
    assert_output --partial "Line 2"
    assert_output --partial "Line 3"
    assert_output --partial "Line 5"
}

# =============================================================================
# Test Cases: _handle_build_completion with early failure
# =============================================================================

@test "completion_early_failure_shows_console_output" {
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    get_console_output() {
        echo "Started by user admin
Obtained Jenkinsfile from git
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed
Finished: FAILURE"
    }
    get_all_stages() { echo "[]"; }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Console Output ==="
    assert_output --partial "MultipleCompilationErrorsException"
    assert_output --partial "Finished: FAILURE"
}

@test "completion_early_failure_unstable_shows_console" {
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    get_console_output() {
        echo "Started by user admin
Some early error
Finished: UNSTABLE"
    }
    get_all_stages() { echo "[]"; }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Console Output ==="
    assert_output --partial "Some early error"
    assert_output --partial "Finished: UNSTABLE"
}

# =============================================================================
# Test Cases: Normal failures unchanged
# =============================================================================

@test "completion_with_stages_uses_test_results_not_console" {
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    get_console_output() {
        echo "some console output"
    }
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":10,"skipCount":0,"totalCount":11}'
    }
    display_test_results() {
        echo "=== Test Results ==="
        echo "  Total: 11 | Passed: 10 | Failed: 1"
        echo "===================="
    }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Test Results ==="
    refute_output --partial "=== Console Output ==="
}

@test "completion_success_unchanged" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS"}'
    }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_success
    assert_output --partial "Finished: SUCCESS"
    refute_output --partial "=== Console Output ==="
}

# =============================================================================
# Test Cases: _display_error_logs with early failure (status snapshot path)
# =============================================================================

@test "error_logs_early_failure_shows_full_console" {
    get_all_stages() { echo "[]"; }

    local console="Started by user admin
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed
WorkflowScript: 3: error
Finished: FAILURE"

    run _display_error_logs "testjob" "42" "$console"
    assert_success
    assert_output --partial "=== Console Output ==="
    assert_output --partial "MultipleCompilationErrorsException"
    # Should NOT show Error Logs header when early failure
    refute_output --partial "=== Error Logs ==="
}

@test "error_logs_with_stages_uses_existing_logic" {
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo "Build"; }
    extract_stage_logs() { echo "error line from stage"; }
    find_failed_downstream_build() { echo ""; }

    run _display_error_logs "testjob" "42" "full console output with ERROR in it"
    assert_success
    assert_output --partial "=== Error Logs ==="
    refute_output --partial "=== Console Output ==="
}
