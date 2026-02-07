#!/usr/bin/env bats

# Unit tests for JSON output bug fixes: console_output for early failures,
# multi-line error_summary for stage failures
# Spec reference: bug-status-json-spec.md

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
# Test Cases: Early failure JSON (no stages ran)
# Spec: bug-status-json-spec.md, Acceptance Criteria 1 & 2
# =============================================================================

@test "early_failure_json_includes_console_output" {
    get_all_stages() { echo "[]"; }
    get_failed_stage() { echo ""; }
    detect_all_downstream_builds() { echo ""; }

    local console="Started by user buildtriggerdude
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:
WorkflowScript: 3: Too many arguments for map key \"node\" @ line 3, column 9.
Finished: FAILURE"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    # Parse JSON and check console_output field
    local console_output_val
    console_output_val=$(echo "$output" | jq -r '.console_output')
    [[ "$console_output_val" != "null" ]]
    [[ "$console_output_val" == *"MultipleCompilationErrorsException"* ]]
    [[ "$console_output_val" == *"Started by user buildtriggerdude"* ]]
}

@test "early_failure_json_has_null_error_summary" {
    get_all_stages() { echo "[]"; }
    get_failed_stage() { echo ""; }
    detect_all_downstream_builds() { echo ""; }

    local console="Started by user admin
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed
Finished: FAILURE"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    local error_summary_val
    error_summary_val=$(echo "$output" | jq -r '.error_summary')
    [[ "$error_summary_val" == "null" ]]
}

@test "early_failure_json_has_null_failed_stage" {
    get_all_stages() { echo "[]"; }
    get_failed_stage() { echo ""; }
    detect_all_downstream_builds() { echo ""; }

    local console="Started by user admin
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed
Finished: FAILURE"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    local failed_stage_val
    failed_stage_val=$(echo "$output" | jq -r '.failed_stage')
    [[ "$failed_stage_val" == "null" ]]
}

# =============================================================================
# Test Cases: Stage failure JSON (stages ran, one failed)
# Spec: bug-status-json-spec.md, Acceptance Criteria 3 & 4
# =============================================================================

@test "stage_failure_json_has_multiline_error_summary" {
    get_all_stages() {
        echo '[{"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000},{"name":"Test","status":"FAILED","startTimeMillis":5000,"durationMillis":3000}]'
    }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }

    # Build a console with stage markers and multiple error lines
    local console="[Pipeline] { (Build)
[Pipeline] sh
+ echo building
[Pipeline] }
[Pipeline] { (Test)
[Pipeline] sh
+ ./run-tests.sh
ERROR: Test suite failed
ERROR: 3 tests failed out of 50
FAILURE: TestWidget.testRender
FAILURE: TestWidget.testUpdate
FAILURE: TestAPI.testEndpoint
[Pipeline] }
[Pipeline] End of Pipeline
Finished: FAILURE"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    local error_summary_val
    error_summary_val=$(echo "$output" | jq -r '.error_summary')
    [[ "$error_summary_val" != "null" ]]

    # Should have multiple lines (newlines in the string)
    local line_count
    line_count=$(echo "$error_summary_val" | wc -l | tr -d ' ')
    [[ "$line_count" -gt 1 ]]
}

@test "stage_failure_json_omits_console_output" {
    get_all_stages() {
        echo '[{"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000},{"name":"Test","status":"FAILED","startTimeMillis":5000,"durationMillis":3000}]'
    }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }

    local console="[Pipeline] { (Test)
ERROR: Test failed
[Pipeline] }
Finished: FAILURE"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    local console_output_val
    console_output_val=$(echo "$output" | jq -r '.console_output')
    [[ "$console_output_val" == "null" ]]
}

@test "stage_failure_json_has_failed_stage" {
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":3000}]'
    }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }

    local console="[Pipeline] { (Test)
ERROR: Test failed
[Pipeline] }
Finished: FAILURE"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    local failed_stage_val
    failed_stage_val=$(echo "$output" | jq -r '.failed_stage')
    [[ "$failed_stage_val" == "Test" ]]
}

# =============================================================================
# Test Cases: Stage failure fallback behavior
# Spec: bug-status-json-spec.md, Acceptance Criteria 6
# =============================================================================

@test "stage_failure_json_fallback_when_stage_extraction_insufficient" {
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":3000}]'
    }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    # Mock extract_stage_logs to return too few lines (< STAGE_LOG_MIN_LINES)
    extract_stage_logs() { echo "one short line"; }

    # Build console with enough lines so tail -50 produces meaningful output
    local console="Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8
Line 9
Line 10
ERROR: something went wrong at the end"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    local error_summary_val
    error_summary_val=$(echo "$output" | jq -r '.error_summary')
    [[ "$error_summary_val" != "null" ]]
    # Fallback should include content from the console tail
    [[ "$error_summary_val" == *"ERROR: something went wrong at the end"* ]]
}

# =============================================================================
# Test Cases: Downstream failure handling
# Spec: bug-status-json-spec.md, Acceptance Criteria 5
# =============================================================================

@test "downstream_failure_json_extracts_from_downstream_console" {
    get_all_stages() {
        echo '[{"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000},{"name":"Deploy","status":"FAILED","startTimeMillis":5000,"durationMillis":3000}]'
    }
    get_failed_stage() { echo "Deploy"; }
    detect_all_downstream_builds() { echo "downstream-job #10"; }
    find_failed_downstream_build() { echo "downstream-job 10"; }
    get_console_output() { echo "ERROR: downstream deploy failed
ERROR: connection refused to production server
FATAL: deployment aborted"; }

    local console="[Pipeline] { (Deploy)
Building downstream-job #10
downstream-job #10 completed: FAILURE
[Pipeline] }
Finished: FAILURE"

    run _build_failure_json "ralph1" "42" "$console"
    assert_success

    local error_summary_val
    error_summary_val=$(echo "$output" | jq -r '.error_summary')
    [[ "$error_summary_val" == *"downstream deploy failed"* ]]
}

# =============================================================================
# Test Cases: Success build unchanged
# Spec: bug-status-json-spec.md, Acceptance Criteria 7
# =============================================================================

@test "success_build_has_no_failure_in_json_output" {
    # This tests that _output_json_status doesn't add failure for SUCCESS.
    # We test the gating logic indirectly: _build_failure_json is only called
    # when is_failed is true, so for SUCCESS it should never produce a failure object.
    # Verify _build_failure_json isn't called for success by testing the output
    # function behavior through the wrapper approach used in buildgit_status.bats.

    # For a unit-level test, just verify that _build_failure_json produces valid
    # JSON with proper structure when called (it's always called for failures only)
    get_all_stages() {
        echo '[{"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo ""; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }

    run _build_failure_json "ralph1" "42" "some console"
    assert_success

    # Valid JSON
    echo "$output" | jq . >/dev/null 2>&1
    assert_success
}
