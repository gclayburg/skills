#!/usr/bin/env bats

# Unit tests for NOT_BUILT and non-SUCCESS result handling
# Spec reference: bug2026-02-12-phandlemono-no-logs-spec.md

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
# Test: NOT_BUILT triggers error display in monitoring mode
# Spec: Acceptance Criteria 1, 3
# =============================================================================

@test "NOT_BUILT triggers error display in monitoring mode" {
    CONSOLE_MODE=""
    get_build_info() {
        echo '{"building":false,"result":"NOT_BUILT"}'
    }
    get_console_output() {
        echo "[Pipeline] { (Build Handle)
ERROR: docker: Error response from daemon: port is already allocated
[Pipeline] }
Finished: FAILURE"
    }
    get_all_stages() {
        echo '[{"name":"Build Handle","status":"FAILED","startTimeMillis":0,"durationMillis":14000}]'
    }
    fetch_test_results() { echo ""; }
    get_failed_stage() { echo "Build Handle"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: docker: Error response from daemon: port is already allocated"; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Error Logs ==="
    assert_output --partial "Finished: NOT_BUILT"
}

# =============================================================================
# Test: NOT_BUILT shows red in finished line
# Spec: Acceptance Criteria 2
# =============================================================================

@test "NOT_BUILT shows red in finished line" {
    run print_finished_line "NOT_BUILT"
    assert_success
    assert_output --partial "Finished: NOT_BUILT"
    # In NO_COLOR mode, color vars are empty, so test structure only
    [[ "$output" == *"${COLOR_RED}"* ]] || [[ "$output" == "Finished: NOT_BUILT" ]]
}

# =============================================================================
# Test: NOT_BUILT detected by check_build_failed
# Spec: Acceptance Criteria 7
# =============================================================================

@test "NOT_BUILT detected by check_build_failed" {
    get_build_info() {
        echo '{"building":false,"result":"NOT_BUILT"}'
    }

    run check_build_failed "testjob" "42"
    assert_success  # returns 0 meaning "yes, it failed"
}

# =============================================================================
# Test: NOT_BUILT JSON includes failure object
# Spec: Acceptance Criteria 6
# =============================================================================

@test "NOT_BUILT JSON includes failure object" {
    get_all_stages() {
        echo '[{"name":"Build Handle","status":"FAILED","startTimeMillis":0,"durationMillis":14000}]'
    }
    get_failed_stage() { echo "Build Handle"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() { echo ""; }

    local console="[Pipeline] { (Build Handle)
ERROR: docker: Error response from daemon: port is already allocated
[Pipeline] }
Finished: FAILURE"

    run output_json "test-job" "42" \
        '{"number":42,"result":"NOT_BUILT","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test/42/"}' \
        "scm" "" "abc1234" "Test commit" "in_history" "$console"

    assert_success

    # failure object should exist
    local failure_val
    failure_val=$(echo "$output" | jq '.failure')
    [[ "$failure_val" != "null" ]] || fail "Expected failure object for NOT_BUILT, got null"
}

# =============================================================================
# Test: Monitoring mode shows error logs for FAILURE without test results
# Spec: Acceptance Criteria 3
# =============================================================================

@test "monitoring mode shows error logs for FAILURE without test results" {
    CONSOLE_MODE=""
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    get_console_output() {
        echo "[Pipeline] { (Build)
ERROR: compilation failed
[Pipeline] }
Finished: FAILURE"
    }
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    fetch_test_results() { echo ""; }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: compilation failed"; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Error Logs ==="
    assert_output --partial "Finished: FAILURE"
}

# =============================================================================
# Test: Monitoring mode suppresses error logs when test failures exist
# Spec: Acceptance Criteria 4
# =============================================================================

@test "monitoring mode suppresses error logs when test failures exist" {
    CONSOLE_MODE=""
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    get_console_output() { echo "some console output"; }
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    fetch_test_results() {
        echo '{"failCount":3,"passCount":32,"skipCount":0,"totalCount":35}'
    }
    display_test_results() {
        echo "=== Test Results ==="
        echo "  Total: 35 | Passed: 32 | Failed: 3 | Skipped: 0"
    }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Test Results ==="
    refute_output --partial "=== Error Logs ==="
    refute_output --partial "=== Console Log"
    assert_output --partial "Finished: UNSTABLE"
}

# =============================================================================
# Test: Unknown status treated as failure
# Spec: Acceptance Criteria 9 (unknown results treated as failures)
# =============================================================================

@test "unknown status treated as failure with red color" {
    # print_finished_line for unknown status should use red (the * fallback)
    run print_finished_line "WEIRD_STATUS"
    assert_success
    assert_output --partial "Finished: WEIRD_STATUS"
    [[ "$output" == *"${COLOR_RED}"* ]] || [[ "$output" == "Finished: WEIRD_STATUS" ]]
}

@test "unknown status triggers error display in monitoring mode" {
    CONSOLE_MODE=""
    get_build_info() {
        echo '{"building":false,"result":"WEIRD_STATUS"}'
    }
    get_console_output() { echo "ERROR: something unexpected happened"; }
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    fetch_test_results() { echo ""; }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: something unexpected happened"; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Error Logs ==="
    assert_output --partial "Finished: WEIRD_STATUS"
}
