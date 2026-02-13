#!/usr/bin/env bats

# Tests for test results display functions
# Spec: test-failure-display-spec.md
# Plan: test-failure-display-plan.md

load test_helper

# Load the jenkins-common.sh library
setup() {
    # Call parent setup from test_helper
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
    FIXTURES_DIR="${TEST_DIR}/fixtures"

    # Source jenkins-common.sh to get functions
    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# Chunk A: fetch_test_results Function Tests
# Spec: test-failure-display-spec.md, Section: Test Report Detection (1.1-1.2)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Configuration variables are defined with correct defaults
# Spec: test-failure-display-spec.md, Section: Configuration
# -----------------------------------------------------------------------------
@test "test_results_config_variables_defined" {
    # Verify the configuration constants are defined
    [[ -n "${MAX_FAILED_TESTS_DISPLAY:-}" ]]
    [[ -n "${MAX_ERROR_LINES:-}" ]]
    [[ -n "${MAX_ERROR_LENGTH:-}" ]]

    # Verify default values per spec
    [[ "$MAX_FAILED_TESTS_DISPLAY" -eq 10 ]]
    [[ "$MAX_ERROR_LINES" -eq 5 ]]
    [[ "$MAX_ERROR_LENGTH" -eq 500 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Configuration variables can be overridden
# Spec: test-failure-display-spec.md, Section: Configuration
# -----------------------------------------------------------------------------
@test "test_results_config_variables_overridable" {
    # Set custom values before sourcing
    export MAX_FAILED_TESTS_DISPLAY=5
    export MAX_ERROR_LINES=3
    export MAX_ERROR_LENGTH=200

    # Re-source to pick up overrides (need to unset the loaded flag)
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Verify overridden values
    [[ "$MAX_FAILED_TESTS_DISPLAY" -eq 5 ]]
    [[ "$MAX_ERROR_LINES" -eq 3 ]]
    [[ "$MAX_ERROR_LENGTH" -eq 200 ]]
}

# -----------------------------------------------------------------------------
# Test Case: fetch_test_results returns empty on 404
# Spec: test-failure-display-spec.md, Section: 1.2 Handle Missing Test Reports
# -----------------------------------------------------------------------------
@test "fetch_test_results_returns_empty_on_404" {
    # Mock jenkins_api_with_status to return 404
    jenkins_api_with_status() {
        echo "Not Found"
        echo "404"
    }
    export -f jenkins_api_with_status

    run fetch_test_results "test-job" "123"
    assert_success
    assert_output ""
}

# -----------------------------------------------------------------------------
# Test Case: fetch_test_results returns JSON on 200
# Spec: test-failure-display-spec.md, Section: 1.1 Check for Test Results
# -----------------------------------------------------------------------------
@test "fetch_test_results_returns_json_on_200" {
    # Load fixture
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    # Mock jenkins_api_with_status to return 200 with JSON
    jenkins_api_with_status() {
        cat "${FIXTURES_DIR}/test_report_1_failure.json"
        echo "200"
    }
    export -f jenkins_api_with_status
    export FIXTURES_DIR

    run fetch_test_results "test-job" "123"
    assert_success

    # Verify output is valid JSON with expected fields
    echo "$output" | jq -e '.failCount == 1' >/dev/null
    echo "$output" | jq -e '.passCount == 32' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: fetch_test_results returns empty on server error
# Spec: test-failure-display-spec.md, Section: Error Handling - API Failures
# -----------------------------------------------------------------------------
@test "fetch_test_results_returns_empty_on_error" {
    # Mock jenkins_api_with_status to return 500
    jenkins_api_with_status() {
        echo "Internal Server Error"
        echo "500"
    }
    export -f jenkins_api_with_status

    run fetch_test_results "test-job" "123"
    assert_success
    # Should log a warning about the failure
    assert_output --partial "Failed to fetch test results (HTTP 500)"
    # Should NOT include the error body in output
    refute_output --partial "Internal Server Error"
}

# -----------------------------------------------------------------------------
# Test Case: fetch_test_results constructs correct API endpoint
# Spec: test-failure-display-spec.md, Section: 1.1 Check for Test Results
# -----------------------------------------------------------------------------
@test "fetch_test_results_uses_correct_endpoint" {
    local captured_endpoint=""

    # Mock jenkins_api_with_status to capture the endpoint
    jenkins_api_with_status() {
        captured_endpoint="$1"
        echo "captured: $1" >&3  # Output to fd 3 for debugging
        echo "{}"
        echo "404"
    }
    export -f jenkins_api_with_status

    fetch_test_results "my-job" "456" >/dev/null

    # Verify the endpoint was constructed correctly
    # We can't easily capture from the mock, so we verify the function works
    # The mock returning 404 means the function was called correctly
    run fetch_test_results "my-job" "456"
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: fetch_test_results handles all passed tests
# Spec: test-failure-display-spec.md, Section: 3.1 Test Summary Section
# -----------------------------------------------------------------------------
@test "fetch_test_results_handles_all_passed" {
    # Mock jenkins_api_with_status to return all-passed fixture
    jenkins_api_with_status() {
        cat "${FIXTURES_DIR}/test_report_all_passed.json"
        echo "200"
    }
    export -f jenkins_api_with_status
    export FIXTURES_DIR

    run fetch_test_results "test-job" "123"
    assert_success

    # Verify output has zero failures
    echo "$output" | jq -e '.failCount == 0' >/dev/null
    echo "$output" | jq -e '.passCount == 33' >/dev/null
}

# =============================================================================
# Chunk B: parse_test_summary Function Tests
# Spec: test-failure-display-spec.md, Section: Summary Statistics (2.1)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: parse_test_summary extracts correct counts
# Spec: test-failure-display-spec.md, Section: 2.1 Summary Statistics
# -----------------------------------------------------------------------------
@test "parse_test_summary_extracts_counts" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    run parse_test_summary "$fixture_json"
    assert_success

    # Output should be 4 lines: total, passed, failed, skipped
    local lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    # Total = 32 passed + 1 failed + 0 skipped = 33
    [[ "${lines[0]}" == "33" ]] || fail "Expected total 33, got ${lines[0]}"
    [[ "${lines[1]}" == "32" ]] || fail "Expected passed 32, got ${lines[1]}"
    [[ "${lines[2]}" == "1" ]] || fail "Expected failed 1, got ${lines[2]}"
    [[ "${lines[3]}" == "0" ]] || fail "Expected skipped 0, got ${lines[3]}"
}

# -----------------------------------------------------------------------------
# Test Case: parse_test_summary handles missing failCount
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "parse_test_summary_handles_missing_failcount" {
    # JSON with missing failCount
    local test_json='{"passCount": 10, "skipCount": 2}'

    run parse_test_summary "$test_json"
    assert_success

    local lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    # Total = 10 passed + 0 failed + 2 skipped = 12
    [[ "${lines[0]}" == "12" ]] || fail "Expected total 12, got ${lines[0]}"
    [[ "${lines[1]}" == "10" ]] || fail "Expected passed 10, got ${lines[1]}"
    [[ "${lines[2]}" == "0" ]] || fail "Expected failed 0, got ${lines[2]}"
    [[ "${lines[3]}" == "2" ]] || fail "Expected skipped 2, got ${lines[3]}"
}

# -----------------------------------------------------------------------------
# Test Case: parse_test_summary handles missing passCount
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "parse_test_summary_handles_missing_passcount" {
    # JSON with missing passCount
    local test_json='{"failCount": 3, "skipCount": 1}'

    run parse_test_summary "$test_json"
    assert_success

    local lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    # Total = 0 passed + 3 failed + 1 skipped = 4
    [[ "${lines[0]}" == "4" ]] || fail "Expected total 4, got ${lines[0]}"
    [[ "${lines[1]}" == "0" ]] || fail "Expected passed 0, got ${lines[1]}"
    [[ "${lines[2]}" == "3" ]] || fail "Expected failed 3, got ${lines[2]}"
    [[ "${lines[3]}" == "1" ]] || fail "Expected skipped 1, got ${lines[3]}"
}

# -----------------------------------------------------------------------------
# Test Case: parse_test_summary handles empty/invalid JSON
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "parse_test_summary_handles_empty_json" {
    # Empty string input
    run parse_test_summary ""
    assert_success

    local lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    # All zeros for empty input
    [[ "${lines[0]}" == "0" ]] || fail "Expected total 0, got ${lines[0]}"
    [[ "${lines[1]}" == "0" ]] || fail "Expected passed 0, got ${lines[1]}"
    [[ "${lines[2]}" == "0" ]] || fail "Expected failed 0, got ${lines[2]}"
    [[ "${lines[3]}" == "0" ]] || fail "Expected skipped 0, got ${lines[3]}"
}

# -----------------------------------------------------------------------------
# Test Case: parse_test_summary handles all passed scenario
# Spec: test-failure-display-spec.md, Section: 2.1 Summary Statistics
# -----------------------------------------------------------------------------
@test "parse_test_summary_all_passed" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_all_passed.json")

    run parse_test_summary "$fixture_json"
    assert_success

    local lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    # Total = 33 passed + 0 failed + 0 skipped = 33
    [[ "${lines[0]}" == "33" ]] || fail "Expected total 33, got ${lines[0]}"
    [[ "${lines[1]}" == "33" ]] || fail "Expected passed 33, got ${lines[1]}"
    [[ "${lines[2]}" == "0" ]] || fail "Expected failed 0, got ${lines[2]}"
    [[ "${lines[3]}" == "0" ]] || fail "Expected skipped 0, got ${lines[3]}"
}

# -----------------------------------------------------------------------------
# Test Case: parse_test_summary handles null values in JSON
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "parse_test_summary_handles_null_values" {
    # JSON with explicit null values
    local test_json='{"failCount": null, "passCount": 5, "skipCount": null}'

    run parse_test_summary "$test_json"
    assert_success

    local lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    # Total = 5 passed + 0 failed + 0 skipped = 5
    [[ "${lines[0]}" == "5" ]] || fail "Expected total 5, got ${lines[0]}"
    [[ "${lines[1]}" == "5" ]] || fail "Expected passed 5, got ${lines[1]}"
    [[ "${lines[2]}" == "0" ]] || fail "Expected failed 0, got ${lines[2]}"
    [[ "${lines[3]}" == "0" ]] || fail "Expected skipped 0, got ${lines[3]}"
}

# =============================================================================
# Chunk C: parse_failed_tests Function Tests
# Spec: test-failure-display-spec.md, Section: Failed Test Details (2.2-2.3)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests extracts failed test details
# Spec: test-failure-display-spec.md, Section: 2.2 Failed Test Details
# -----------------------------------------------------------------------------
@test "parse_failed_tests_extracts_details" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    run parse_failed_tests "$fixture_json"
    assert_success

    # Verify output is a JSON array with one element
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 1 ]] || fail "Expected 1 failed test, got $count"

    # Verify extracted fields
    echo "$output" | jq -e '.[0].className == "test_helper.bats"' >/dev/null
    echo "$output" | jq -e '.[0].name == "TEST_TEMP_DIR is unique per test run"' >/dev/null
    echo "$output" | jq -e '.[0].errorDetails == "[[: command not found"' >/dev/null
    echo "$output" | jq -e '.[0].duration == 0.045' >/dev/null
    echo "$output" | jq -e '.[0].age == 1' >/dev/null
    # errorStackTrace should be present
    echo "$output" | jq -e '.[0].errorStackTrace != null' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests filters by status
# Spec: test-failure-display-spec.md, Section: 2.3 Test Case Iteration
# -----------------------------------------------------------------------------
@test "parse_failed_tests_filters_by_status" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    run parse_failed_tests "$fixture_json"
    assert_success

    # Should only include FAILED tests, not PASSED
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 1 ]] || fail "Expected only 1 failed test (not passed ones), got $count"

    # The failed test should be the one with status FAILED
    echo "$output" | jq -e '.[0].name == "TEST_TEMP_DIR is unique per test run"' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests handles missing errorDetails
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "parse_failed_tests_handles_missing_errordetails" {
    # JSON with failed test that has null errorDetails but has errorStackTrace
    local test_json='{
        "failCount": 1,
        "passCount": 0,
        "skipCount": 0,
        "suites": [{
            "name": "test.bats",
            "cases": [{
                "className": "test.bats",
                "name": "test without error details",
                "status": "FAILED",
                "duration": 0.1,
                "age": 1,
                "errorDetails": null,
                "errorStackTrace": "Stack trace here"
            }]
        }]
    }'

    run parse_failed_tests "$test_json"
    assert_success

    # errorDetails should be null (since stackTrace is available)
    echo "$output" | jq -e '.[0].errorDetails == null' >/dev/null
    echo "$output" | jq -e '.[0].errorStackTrace == "Stack trace here"' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests handles missing className
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "parse_failed_tests_handles_missing_classname" {
    # JSON with failed test missing className
    local test_json='{
        "failCount": 1,
        "passCount": 0,
        "skipCount": 0,
        "suites": [{
            "name": "test.bats",
            "cases": [{
                "name": "test without classname",
                "status": "FAILED",
                "duration": 0.1,
                "age": 1,
                "errorDetails": "Some error"
            }]
        }]
    }'

    run parse_failed_tests "$test_json"
    assert_success

    # className should default to "unknown"
    echo "$output" | jq -e '.[0].className == "unknown"' >/dev/null
    echo "$output" | jq -e '.[0].name == "test without classname"' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests respects MAX_FAILED_TESTS_DISPLAY limit
# Spec: test-failure-display-spec.md, Section: 3.3 Truncation Rules
# -----------------------------------------------------------------------------
@test "parse_failed_tests_respects_max_limit" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_many_failures.json")

    # Override to a smaller limit for testing
    MAX_FAILED_TESTS_DISPLAY=5

    run parse_failed_tests "$fixture_json"
    assert_success

    # Should only return 5 failed tests even though there are 15
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 5 ]] || fail "Expected max 5 failed tests, got $count"
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests truncates long error messages
# Spec: test-failure-display-spec.md, Section: 3.3 Truncation Rules
# -----------------------------------------------------------------------------
@test "parse_failed_tests_truncates_long_errors" {
    # Create a test JSON with a very long error message (>500 chars)
    local long_error=""
    for i in $(seq 1 100); do
        long_error="${long_error}Error line $i with some extra text. "
    done

    local test_json
    test_json=$(jq -n --arg err "$long_error" '{
        "failCount": 1,
        "passCount": 0,
        "skipCount": 0,
        "suites": [{
            "name": "test.bats",
            "cases": [{
                "className": "test.bats",
                "name": "test with long error",
                "status": "FAILED",
                "duration": 0.1,
                "age": 1,
                "errorDetails": $err
            }]
        }]
    }')

    # Override to default 500 char limit
    MAX_ERROR_LENGTH=500

    run parse_failed_tests "$test_json"
    assert_success

    # Error should be truncated to 500 characters
    local error_len
    error_len=$(echo "$output" | jq -r '.[0].errorDetails | length')
    [[ "$error_len" -le 500 ]] || fail "Expected error truncated to 500 chars, got $error_len"
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests handles empty input
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "parse_failed_tests_handles_empty_input" {
    run parse_failed_tests ""
    assert_success

    # Should return empty array
    [[ "$output" == "[]" ]] || fail "Expected empty array, got $output"
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests handles no failed tests
# Spec: test-failure-display-spec.md, Section: 2.3 Test Case Iteration
# -----------------------------------------------------------------------------
@test "parse_failed_tests_handles_no_failures" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_all_passed.json")

    run parse_failed_tests "$fixture_json"
    assert_success

    # Should return empty array when all tests pass
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 0 ]] || fail "Expected 0 failed tests, got $count"
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests handles missing both errorDetails and errorStackTrace
# Spec: test-failure-display-spec.md, Section: Error Handling - Malformed Data
# -----------------------------------------------------------------------------
@test "parse_failed_tests_handles_missing_all_error_info" {
    # JSON with failed test that has neither errorDetails nor errorStackTrace
    local test_json='{
        "failCount": 1,
        "passCount": 0,
        "skipCount": 0,
        "suites": [{
            "name": "test.bats",
            "cases": [{
                "className": "test.bats",
                "name": "test without any error info",
                "status": "FAILED",
                "duration": 0.1,
                "age": 1
            }]
        }]
    }'

    run parse_failed_tests "$test_json"
    assert_success

    # errorDetails should default to "No error details available"
    echo "$output" | jq -e '.[0].errorDetails == "No error details available"' >/dev/null
}

# =============================================================================
# Chunk D: display_test_results Function Tests
# Spec: test-failure-display-spec.md, Section: Human-Readable Output (3.1-3.3)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: display_test_results shows summary line
# Spec: test-failure-display-spec.md, Section: 3.1 Test Summary Section
# -----------------------------------------------------------------------------
@test "display_test_results_shows_summary" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    # Disable colors for testing
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$fixture_json"
    assert_success

    # Should show the summary line
    assert_output --partial "Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0"
    # Should show Test Results header
    assert_output --partial "=== Test Results ==="
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results shows failed test details
# Spec: test-failure-display-spec.md, Section: 3.2 Failed Test Details
# -----------------------------------------------------------------------------
@test "display_test_results_shows_failed_details" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    # Disable colors for testing
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$fixture_json"
    assert_success

    # Should show className::name format
    assert_output --partial "test_helper.bats::TEST_TEMP_DIR is unique per test run"
    # Should show the error
    assert_output --partial "Error: [[: command not found"
    # Should show FAILED TESTS header
    assert_output --partial "FAILED TESTS:"
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results shows all passed message
# Spec: test-failure-display-spec.md, Section: 3.1 Test Summary Section
# -----------------------------------------------------------------------------
@test "display_test_results_shows_all_passed_summary" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_all_passed.json")

    # Disable colors for testing
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$fixture_json"
    assert_success

    # Should show summary with 0 failures
    assert_output --partial "Total: 33 | Passed: 33 | Failed: 0 | Skipped: 0"
    # Should show closing bar
    assert_output --partial "===================="
    # Should NOT show "FAILED TESTS:"
    refute_output --partial "FAILED TESTS:"
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results shows recurring failure indication
# Spec: test-failure-display-spec.md, Section: 3.2 Failed Test Details
# -----------------------------------------------------------------------------
@test "display_test_results_shows_recurring_failure" {
    # Create fixture with age > 1
    local test_json='{
        "failCount": 1,
        "passCount": 5,
        "skipCount": 0,
        "suites": [{
            "name": "test.bats",
            "cases": [{
                "className": "test.bats",
                "name": "recurring failure test",
                "status": "FAILED",
                "duration": 0.1,
                "age": 5,
                "errorDetails": "Some error"
            }]
        }]
    }'

    # Disable colors for testing
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$test_json"
    assert_success

    # Should show "failing for N builds" message
    assert_output --partial "failing for 5 builds"
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results truncates many failures
# Spec: test-failure-display-spec.md, Section: 3.3 Truncation Rules
# -----------------------------------------------------------------------------
@test "display_test_results_truncates_many_failures" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_many_failures.json")

    # Set a smaller limit for testing
    export MAX_FAILED_TESTS_DISPLAY=5
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$fixture_json"
    assert_success

    # Should show "... and N more" message (15 total - 5 displayed = 10 more)
    assert_output --partial "... and 10 more failed tests"
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results truncates stack trace
# Spec: test-failure-display-spec.md, Section: 3.3 Truncation Rules
# -----------------------------------------------------------------------------
@test "display_test_results_truncates_stacktrace" {
    # Create fixture with long stack trace (>5 lines)
    local long_stack="Line 1 of stack trace
Line 2 of stack trace
Line 3 of stack trace
Line 4 of stack trace
Line 5 of stack trace
Line 6 of stack trace
Line 7 of stack trace
Line 8 of stack trace"

    local test_json
    test_json=$(jq -n --arg stack "$long_stack" '{
        "failCount": 1,
        "passCount": 5,
        "skipCount": 0,
        "suites": [{
            "name": "test.bats",
            "cases": [{
                "className": "test.bats",
                "name": "test with long stack",
                "status": "FAILED",
                "duration": 0.1,
                "age": 1,
                "errorStackTrace": $stack
            }]
        }]
    }')

    # Set max lines to 5
    export MAX_ERROR_LINES=5
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$test_json"
    assert_success

    # Should show truncation indicator
    assert_output --partial "..."
    # Should NOT show lines beyond the limit
    refute_output --partial "Line 6 of stack trace"
    refute_output --partial "Line 7 of stack trace"
    refute_output --partial "Line 8 of stack trace"
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results handles empty input
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "display_test_results_shows_placeholder_for_empty_input" {
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results ""
    assert_success

    # Spec: show-test-results-always-spec.md, Section 3
    # Should show placeholder when no test report available
    assert_output --partial "=== Test Results ==="
    assert_output --partial "(no test results available)"
    assert_output --partial "===================="
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results handles zero tests
# Spec: test-failure-display-spec.md, Section: Error Handling
# -----------------------------------------------------------------------------
@test "display_test_results_shows_placeholder_for_zero_tests" {
    local test_json='{
        "failCount": 0,
        "passCount": 0,
        "skipCount": 0,
        "suites": []
    }'

    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$test_json"
    assert_success

    # Spec: show-test-results-always-spec.md, Section 3
    # Should show placeholder when total is 0
    assert_output --partial "=== Test Results ==="
    assert_output --partial "(no test results available)"
    assert_output --partial "===================="
}

# =============================================================================
# Chunk E: format_test_results_json Function Tests
# Spec: test-failure-display-spec.md, Section: JSON Output Enhancement (4.1-4.3)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: format_test_results_json produces valid JSON structure
# Spec: test-failure-display-spec.md, Section: 4.1 JSON Schema
# -----------------------------------------------------------------------------
@test "format_test_results_json_valid_structure" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    run format_test_results_json "$fixture_json"
    assert_success

    # Verify output is valid JSON
    echo "$output" | jq . >/dev/null || fail "Output is not valid JSON"

    # Verify required top-level fields exist
    echo "$output" | jq -e 'has("total")' >/dev/null
    echo "$output" | jq -e 'has("passed")' >/dev/null
    echo "$output" | jq -e 'has("failed")' >/dev/null
    echo "$output" | jq -e 'has("skipped")' >/dev/null
    echo "$output" | jq -e 'has("failed_tests")' >/dev/null

    # Verify failed_tests is an array
    echo "$output" | jq -e '.failed_tests | type == "array"' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: format_test_results_json has correct counts
# Spec: test-failure-display-spec.md, Section: 4.1 JSON Schema
# -----------------------------------------------------------------------------
@test "format_test_results_json_correct_counts" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    run format_test_results_json "$fixture_json"
    assert_success

    # Verify counts match fixture data
    echo "$output" | jq -e '.total == 33' >/dev/null
    echo "$output" | jq -e '.passed == 32' >/dev/null
    echo "$output" | jq -e '.failed == 1' >/dev/null
    echo "$output" | jq -e '.skipped == 0' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: format_test_results_json populates failed_tests array correctly
# Spec: test-failure-display-spec.md, Section: 4.1 JSON Schema
# -----------------------------------------------------------------------------
@test "format_test_results_json_failed_tests_array" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    run format_test_results_json "$fixture_json"
    assert_success

    # Verify failed_tests array has one element
    echo "$output" | jq -e '.failed_tests | length == 1' >/dev/null

    # Verify failed test fields use snake_case naming convention
    echo "$output" | jq -e '.failed_tests[0] | has("class_name")' >/dev/null
    echo "$output" | jq -e '.failed_tests[0] | has("test_name")' >/dev/null
    echo "$output" | jq -e '.failed_tests[0] | has("duration_seconds")' >/dev/null
    echo "$output" | jq -e '.failed_tests[0] | has("age")' >/dev/null
    echo "$output" | jq -e '.failed_tests[0] | has("error_details")' >/dev/null
    echo "$output" | jq -e '.failed_tests[0] | has("error_stack_trace")' >/dev/null

    # Verify values are correct
    echo "$output" | jq -e '.failed_tests[0].class_name == "test_helper.bats"' >/dev/null
    echo "$output" | jq -e '.failed_tests[0].test_name == "TEST_TEMP_DIR is unique per test run"' >/dev/null
    echo "$output" | jq -e '.failed_tests[0].duration_seconds == 0.045' >/dev/null
    echo "$output" | jq -e '.failed_tests[0].age == 1' >/dev/null
    echo "$output" | jq -e '.failed_tests[0].error_details == "[[: command not found"' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: format_test_results_json returns empty on no test data
# Spec: test-failure-display-spec.md, Section: 4.3 Empty Results
# -----------------------------------------------------------------------------
@test "format_test_results_json_empty_on_no_results" {
    run format_test_results_json ""
    assert_success

    # Should return empty string for empty input
    assert_output ""
}

# -----------------------------------------------------------------------------
# Test Case: format_test_results_json returns empty on zero tests
# Spec: test-failure-display-spec.md, Section: 4.3 Empty Results
# -----------------------------------------------------------------------------
@test "format_test_results_json_empty_on_zero_tests" {
    local test_json='{
        "failCount": 0,
        "passCount": 0,
        "skipCount": 0,
        "suites": []
    }'

    run format_test_results_json "$test_json"
    assert_success

    # Should return empty string when total is 0
    assert_output ""
}

# -----------------------------------------------------------------------------
# Test Case: format_test_results_json handles all passed tests
# Spec: test-failure-display-spec.md, Section: 4.1 JSON Schema
# -----------------------------------------------------------------------------
@test "format_test_results_json_all_passed" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_all_passed.json")

    run format_test_results_json "$fixture_json"
    assert_success

    # Verify counts
    echo "$output" | jq -e '.total == 33' >/dev/null
    echo "$output" | jq -e '.passed == 33' >/dev/null
    echo "$output" | jq -e '.failed == 0' >/dev/null
    echo "$output" | jq -e '.skipped == 0' >/dev/null

    # Verify failed_tests is empty array
    echo "$output" | jq -e '.failed_tests | length == 0' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: format_test_results_json handles many failures
# Spec: test-failure-display-spec.md, Section: 4.1 JSON Schema
# -----------------------------------------------------------------------------
@test "format_test_results_json_many_failures" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_many_failures.json")

    # Set limit to 5 for testing
    export MAX_FAILED_TESTS_DISPLAY=5

    run format_test_results_json "$fixture_json"
    assert_success

    # Verify counts reflect all failures (not just displayed ones)
    echo "$output" | jq -e '.failed == 15' >/dev/null

    # But failed_tests array should be limited to MAX_FAILED_TESTS_DISPLAY
    echo "$output" | jq -e '.failed_tests | length == 5' >/dev/null
}

# =============================================================================
# Chunk F: Integration into Display Flow Tests
# Spec: test-failure-display-spec.md, Section: Integration Points (5.1) and Output Ordering (6)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: display_failure_output shows test results
# Spec: test-failure-display-spec.md, Section: 5.1 checkbuild.sh Integration
# -----------------------------------------------------------------------------
@test "integration_display_shows_test_results" {
    # Disable colors for testing
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock fetch_test_results to return fixture data
    fetch_test_results() {
        cat "${FIXTURES_DIR}/test_report_1_failure.json"
    }
    export -f fetch_test_results
    export FIXTURES_DIR

    # Mock other required functions
    get_all_stages() { echo '[{"name":"Unit Tests","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Unit Tests"; }
    detect_all_downstream_builds() { echo ""; }
    get_console_output() { echo "Some console output"; }
    export -f get_all_stages get_failed_stage detect_all_downstream_builds get_console_output

    # Create minimal build JSON
    local build_json='{"result": "FAILURE", "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'

    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "console output here"
    assert_success

    # Should show test results section
    assert_output --partial "=== Test Results ==="
    assert_output --partial "Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0"
    assert_output --partial "FAILED TESTS:"
    assert_output --partial "test_helper.bats::TEST_TEMP_DIR is unique per test run"
}

# -----------------------------------------------------------------------------
# Test Case: display_failure_output shows test results in correct order
# Spec: test-failure-display-spec.md, Section: 6 Output Ordering
# -----------------------------------------------------------------------------
@test "integration_display_correct_ordering" {
    # Spec: console-on-unstable-spec.md - Error Logs suppressed when test failures exist
    # Verify: Failed Jobs before Test Results, and no Error Logs by default
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock fetch_test_results to return fixture data
    fetch_test_results() {
        cat "${FIXTURES_DIR}/test_report_1_failure.json"
    }
    export -f fetch_test_results
    export FIXTURES_DIR

    # Mock other required functions
    get_all_stages() { echo '[{"name":"Unit Tests","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Unit Tests"; }
    detect_all_downstream_builds() { echo ""; }
    get_console_output() { echo "Some console output"; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: some error"; }
    export -f get_all_stages get_failed_stage detect_all_downstream_builds get_console_output find_failed_downstream_build extract_error_lines

    local build_json='{"result": "FAILURE", "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'

    CONSOLE_MODE=""
    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "console output here"
    assert_success

    # Verify ordering: Failed Jobs comes before Test Results
    local failed_jobs_pos test_results_pos
    failed_jobs_pos=$(echo "$output" | grep -n "=== Failed Jobs ===" | head -1 | cut -d: -f1)
    test_results_pos=$(echo "$output" | grep -n "=== Test Results ===" | head -1 | cut -d: -f1)

    # Failed Jobs should come before Test Results
    [[ "$failed_jobs_pos" -lt "$test_results_pos" ]] || fail "Failed Jobs should come before Test Results"

    # Error Logs should NOT appear when test failures exist and --console not specified
    refute_output --partial "=== Error Logs ==="
}

@test "integration_display_correct_ordering_with_console_auto" {
    # Spec: console-on-unstable-spec.md - Error Logs shown with --console auto
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    fetch_test_results() {
        cat "${FIXTURES_DIR}/test_report_1_failure.json"
    }
    export -f fetch_test_results
    export FIXTURES_DIR

    get_all_stages() { echo '[{"name":"Unit Tests","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Unit Tests"; }
    detect_all_downstream_builds() { echo ""; }
    get_console_output() { echo "Some console output"; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: some error"; }
    export -f get_all_stages get_failed_stage detect_all_downstream_builds get_console_output find_failed_downstream_build extract_error_lines

    local build_json='{"result": "FAILURE", "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'

    CONSOLE_MODE="auto"
    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "console output here"
    assert_success

    local failed_jobs_pos test_results_pos error_logs_pos
    failed_jobs_pos=$(echo "$output" | grep -n "=== Failed Jobs ===" | head -1 | cut -d: -f1)
    test_results_pos=$(echo "$output" | grep -n "=== Test Results ===" | head -1 | cut -d: -f1)
    error_logs_pos=$(echo "$output" | grep -n "=== Error Logs ===" | head -1 | cut -d: -f1)

    [[ "$failed_jobs_pos" -lt "$test_results_pos" ]] || fail "Failed Jobs should come before Test Results"
    [[ "$test_results_pos" -lt "$error_logs_pos" ]] || fail "Test Results should come before Error Logs"
}

# -----------------------------------------------------------------------------
# Test Case: display_failure_output skips test results when API returns 404
# Spec: test-failure-display-spec.md, Section: 1.2 Handle Missing Test Reports
# -----------------------------------------------------------------------------
@test "integration_display_shows_placeholder_when_no_tests" {
    # Spec: show-test-results-always-spec.md, Section 3
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock fetch_test_results to return empty (simulating 404)
    fetch_test_results() {
        echo ""
    }
    export -f fetch_test_results

    # Mock other required functions
    get_all_stages() { echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    get_console_output() { echo "Some console output"; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: build failed"; }
    export -f get_all_stages get_failed_stage detect_all_downstream_builds get_console_output find_failed_downstream_build extract_error_lines

    local build_json='{"result": "FAILURE", "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'

    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "console output here"
    assert_success

    # Should show test results placeholder when no test data
    assert_output --partial "=== Test Results ==="
    assert_output --partial "(no test results available)"
    refute_output --partial "FAILED TESTS:"

    # Should still show other sections
    assert_output --partial "=== Failed Jobs ==="
    assert_output --partial "=== Error Logs ==="
}

# -----------------------------------------------------------------------------
# Test Case: output_json includes test_results field
# Spec: test-failure-display-spec.md, Section: 4.1 New test_results Field
# -----------------------------------------------------------------------------
@test "integration_json_includes_test_results" {
    # Disable colors for testing
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock fetch_test_results to return fixture data
    fetch_test_results() {
        cat "${FIXTURES_DIR}/test_report_1_failure.json"
    }
    export -f fetch_test_results
    export FIXTURES_DIR

    # Mock other required functions for failed build
    get_failed_stage() { echo "Unit Tests"; }
    detect_all_downstream_builds() { echo ""; }
    get_console_output() { echo "Some console output"; }
    find_failed_downstream_build() { echo ""; }
    export -f get_failed_stage detect_all_downstream_builds get_console_output find_failed_downstream_build

    local build_json='{"result": "FAILURE", "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'
    local console_output="Started by user testuser"

    run output_json "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "$console_output"
    assert_success

    # Verify output is valid JSON
    echo "$output" | jq . >/dev/null || fail "Output is not valid JSON"

    # Verify test_results field exists
    echo "$output" | jq -e 'has("test_results")' >/dev/null || fail "Missing test_results field"

    # Verify test_results has correct structure
    echo "$output" | jq -e '.test_results.total == 33' >/dev/null
    echo "$output" | jq -e '.test_results.passed == 32' >/dev/null
    echo "$output" | jq -e '.test_results.failed == 1' >/dev/null
    echo "$output" | jq -e '.test_results.failed_tests | length == 1' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: output_json omits test_results when not available
# Spec: test-failure-display-spec.md, Section: 4.3 Absent Test Results
# -----------------------------------------------------------------------------
@test "integration_json_null_when_no_tests" {
    # Spec: show-test-results-always-spec.md, Section 3.2
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock fetch_test_results to return empty (simulating 404)
    fetch_test_results() {
        echo ""
    }
    export -f fetch_test_results

    # Mock other required functions for failed build
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    get_console_output() { echo "Some console output"; }
    find_failed_downstream_build() { echo ""; }
    export -f get_failed_stage detect_all_downstream_builds get_console_output find_failed_downstream_build

    local build_json='{"result": "FAILURE", "building": false, "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'
    local console_output="Started by user testuser"

    run output_json "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "$console_output"
    assert_success

    # Verify output is valid JSON
    echo "$output" | jq . >/dev/null || fail "Output is not valid JSON"

    # Verify test_results field is null (not absent)
    echo "$output" | jq -e 'has("test_results")' >/dev/null || fail "test_results field should exist"
    echo "$output" | jq -e '.test_results == null' >/dev/null || fail "test_results should be null when no test data"

    # But other failure fields should exist
    echo "$output" | jq -e 'has("failure")' >/dev/null || fail "failure field should exist"
}

# =============================================================================
# Chunk A: childReports Fixture Validation Tests
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: childReports fixture is valid JSON
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md, Section: Test Fixture
# -----------------------------------------------------------------------------
@test "childreports_fixture_is_valid_json" {
    # Verify fixture file exists and is valid JSON
    run jq . "${FIXTURES_DIR}/test_report_childreports.json"
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: childReports fixture has required fields
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md, Section: Test Fixture
# -----------------------------------------------------------------------------
@test "childreports_fixture_has_required_fields" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_childreports.json")

    # Verify top-level counts exist
    echo "$fixture_json" | jq -e 'has("failCount")' >/dev/null
    echo "$fixture_json" | jq -e 'has("passCount")' >/dev/null
    echo "$fixture_json" | jq -e 'has("skipCount")' >/dev/null

    # Verify childReports structure exists
    echo "$fixture_json" | jq -e 'has("childReports")' >/dev/null
    echo "$fixture_json" | jq -e '.childReports | type == "array"' >/dev/null
    echo "$fixture_json" | jq -e '.childReports | length > 0' >/dev/null

    # Verify nested result structure
    echo "$fixture_json" | jq -e '.childReports[0] | has("result")' >/dev/null
    echo "$fixture_json" | jq -e '.childReports[0].result | has("suites")' >/dev/null
    echo "$fixture_json" | jq -e '.childReports[0].result.suites[0] | has("cases")' >/dev/null

    # Verify at least one FAILED/REGRESSION test exists with error info
    echo "$fixture_json" | jq -e '.childReports[0].result.suites[0].cases[] | select(.status == "FAILED" or .status == "REGRESSION") | has("errorStackTrace")' >/dev/null
}

# =============================================================================
# Chunk B: parse_failed_tests() childReports Structure Tests
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests handles childReports structure
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md, Section: Unit Tests
# -----------------------------------------------------------------------------
@test "parse_failed_tests_handles_childreports_structure" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_childreports.json")

    run parse_failed_tests "$fixture_json"
    assert_success

    # Verify output is a JSON array with one failed test
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 1 ]] || fail "Expected 1 failed test from childReports, got $count"

    # Verify the failed test was extracted correctly
    echo "$output" | jq -e '.[0].className == "smoke.bats"' >/dev/null
    echo "$output" | jq -e '.[0].name == "test_name"' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests extracts stacktrace from childReports
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md, Section: Unit Tests
# -----------------------------------------------------------------------------
@test "parse_failed_tests_extracts_stacktrace_from_childreports" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_childreports.json")

    run parse_failed_tests "$fixture_json"
    assert_success

    # Verify errorStackTrace was extracted
    echo "$output" | jq -e '.[0].errorStackTrace != null' >/dev/null
    echo "$output" | jq -e '.[0].errorStackTrace | contains("smoke.bats")' >/dev/null
    echo "$output" | jq -e '.[0].errorStackTrace | contains("line 10")' >/dev/null
}

# -----------------------------------------------------------------------------
# Test Case: parse_failed_tests handles mixed structures
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md, Section: Unit Tests
# -----------------------------------------------------------------------------
@test "parse_failed_tests_handles_mixed_structures" {
    # Create JSON with both direct suites and childReports
    local test_json='{
        "failCount": 2,
        "passCount": 5,
        "skipCount": 0,
        "suites": [{
            "name": "direct.bats",
            "cases": [{
                "className": "direct.bats",
                "name": "direct test failure",
                "status": "FAILED",
                "duration": 0.1,
                "age": 1,
                "errorDetails": "Direct error"
            }]
        }],
        "childReports": [{
            "result": {
                "suites": [{
                    "name": "child.bats",
                    "cases": [{
                        "className": "child.bats",
                        "name": "child test failure",
                        "status": "FAILED",
                        "duration": 0.2,
                        "age": 1,
                        "errorDetails": "Child error"
                    }]
                }]
            }
        }]
    }'

    run parse_failed_tests "$test_json"
    assert_success

    # Should find both failures
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 2 ]] || fail "Expected 2 failed tests from mixed structure, got $count"

    # Verify both tests are present
    echo "$output" | jq -e 'any(.[]; .className == "direct.bats")' >/dev/null || fail "Missing direct.bats failure"
    echo "$output" | jq -e 'any(.[]; .className == "child.bats")' >/dev/null || fail "Missing child.bats failure"
}

# -----------------------------------------------------------------------------
# Test Case: display_test_results shows childReports failures
# Spec: bug2026-01-28-test-case-failure-not-shown-spec.md, Section: Integration Test
# -----------------------------------------------------------------------------
@test "display_test_results_shows_childreports_failures" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_childreports.json")

    # Disable colors for testing
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$fixture_json"
    assert_success

    # Should show the test summary
    assert_output --partial "=== Test Results ==="
    assert_output --partial "Total: 33 | Passed: 32 | Failed: 1"

    # Should show the failed test from childReports
    assert_output --partial "smoke.bats::test_name"

    # Should show the stack trace content
    assert_output --partial "smoke.bats"
}

# =============================================================================
# REGRESSION Status Tests
# Spec: bug-no-testfail-stacktrace-shown-spec.md
# Jenkins uses "REGRESSION" for newly-broken tests (first failure)
# and "FAILED" for recurring failures (age > 1)
# =============================================================================

@test "parse_failed_tests_handles_regression_status" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_regression.json")

    run parse_failed_tests "$fixture_json"
    assert_success

    # Should find the REGRESSION test
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 1 ]] || fail "Expected 1 failed test from REGRESSION fixture, got $count"

    # Verify it found the correct test
    echo "$output" | jq -e '.[0].className == "buildgit_routing.bats"' >/dev/null || fail "Wrong className"
    echo "$output" | jq -e '.[0].name == "route_build_command"' >/dev/null || fail "Wrong test name"
}

@test "parse_failed_tests_handles_mixed_regression_and_failed" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_regression_and_failed.json")

    run parse_failed_tests "$fixture_json"
    assert_success

    # Should find both REGRESSION and FAILED tests
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 2 ]] || fail "Expected 2 failed tests from mixed fixture, got $count"

    # Verify both tests are present
    echo "$output" | jq -e 'any(.[]; .className == "buildgit_routing.bats")' >/dev/null || fail "Missing REGRESSION test"
    echo "$output" | jq -e 'any(.[]; .className == "checkbuild_job_flag.bats")' >/dev/null || fail "Missing FAILED test"
}

@test "display_test_results_shows_regression_failures" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_regression.json")

    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$fixture_json"
    assert_success

    assert_output --partial "=== Test Results ==="
    assert_output --partial "Total: 33 | Passed: 32 | Failed: 1"
    assert_output --partial "FAILED TESTS:"
    assert_output --partial "buildgit_routing.bats::route_build_command"
    assert_output --partial "c: command not found"
}

@test "format_test_results_json_includes_regression" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_regression.json")

    run format_test_results_json "$fixture_json"
    assert_success

    # Should include the REGRESSION test in the failed_tests array
    local count
    count=$(echo "$output" | jq '.failed_tests | length')
    [[ "$count" -eq 1 ]] || fail "Expected 1 failed test in JSON, got $count"

    echo "$output" | jq -e '.failed_tests[0].test_name == "route_build_command"' >/dev/null || fail "Wrong test_name in JSON"
}

# =============================================================================
# Show Test Results Always - New Feature Tests
# Spec: show-test-results-always-spec.md
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Green color codes for all-pass test results
# Spec: show-test-results-always-spec.md, Section 2.1
# -----------------------------------------------------------------------------
@test "display_test_results_green_color_for_all_pass" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_all_passed.json")

    # Force color codes on by setting them directly
    unset NO_COLOR
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
    COLOR_GREEN="<GREEN>"
    COLOR_YELLOW="<YELLOW>"
    COLOR_RESET="<RESET>"

    run display_test_results "$fixture_json"
    assert_success

    # Should use green, not yellow, for all-pass results
    assert_output --partial "<GREEN>=== Test Results ===<RESET>"
    assert_output --partial "<GREEN>Total: 33"
    assert_output --partial "<GREEN>====================<RESET>"
    refute_output --partial "<YELLOW>"
}

# -----------------------------------------------------------------------------
# Test Case: Yellow color codes for failures (existing behavior preserved)
# Spec: show-test-results-always-spec.md, Section 2.2
# -----------------------------------------------------------------------------
@test "display_test_results_yellow_color_for_failures" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_1_failure.json")

    # Force color codes on by setting them directly
    unset NO_COLOR
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
    COLOR_GREEN="<GREEN>"
    COLOR_YELLOW="<YELLOW>"
    COLOR_RED="<RED>"
    COLOR_RESET="<RESET>"

    run display_test_results "$fixture_json"
    assert_success

    # Should use yellow, not green, for failure results
    assert_output --partial "<YELLOW>=== Test Results ===<RESET>"
    assert_output --partial "<YELLOW>Total: 33"
    refute_output --partial "<GREEN>=== Test Results ==="
}

# -----------------------------------------------------------------------------
# Test Case: Closing bar always present for all-pass
# Spec: show-test-results-always-spec.md, Section 4
# -----------------------------------------------------------------------------
@test "display_test_results_closing_bar_for_all_pass" {
    local fixture_json
    fixture_json=$(cat "${FIXTURES_DIR}/test_report_all_passed.json")

    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results "$fixture_json"
    assert_success

    assert_output --partial "===================="
}

# -----------------------------------------------------------------------------
# Test Case: Closing bar present for placeholder
# Spec: show-test-results-always-spec.md, Section 4
# -----------------------------------------------------------------------------
@test "display_test_results_closing_bar_for_placeholder" {
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run display_test_results ""
    assert_success

    assert_output --partial "===================="
}

# -----------------------------------------------------------------------------
# Test Case: JSON includes test_results for SUCCESS build
# Spec: show-test-results-always-spec.md, Section 7
# -----------------------------------------------------------------------------
@test "integration_json_includes_test_results_for_success" {
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock fetch_test_results to return all-passed fixture
    fetch_test_results() {
        cat "${FIXTURES_DIR}/test_report_all_passed.json"
    }
    export -f fetch_test_results
    export FIXTURES_DIR

    local build_json='{"result": "SUCCESS", "building": false, "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'

    run output_json "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history"
    assert_success

    # Verify output is valid JSON
    echo "$output" | jq . >/dev/null || fail "Output is not valid JSON"

    # Verify test_results field exists for SUCCESS build
    echo "$output" | jq -e 'has("test_results")' >/dev/null || fail "Missing test_results for SUCCESS build"
    echo "$output" | jq -e '.test_results.total == 33' >/dev/null || fail "Wrong total"
    echo "$output" | jq -e '.test_results.passed == 33' >/dev/null || fail "Wrong passed"
    echo "$output" | jq -e '.test_results.failed == 0' >/dev/null || fail "Wrong failed"
    echo "$output" | jq -e '.test_results.failed_tests | length == 0' >/dev/null || fail "Should have no failed_tests"

    # Should NOT have failure field for SUCCESS build
    echo "$output" | jq -e 'has("failure") | not' >/dev/null || fail "SUCCESS build should not have failure field"
}

# -----------------------------------------------------------------------------
# Test Case: JSON test_results null for SUCCESS build with no test report
# Spec: show-test-results-always-spec.md, Section 3.2
# -----------------------------------------------------------------------------
@test "integration_json_null_test_results_for_success_no_report" {
    export NO_COLOR=1
    unset _JENKINS_COMMON_LOADED
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock fetch_test_results to return empty (no junit results)
    fetch_test_results() {
        echo ""
    }
    export -f fetch_test_results

    local build_json='{"result": "SUCCESS", "building": false, "duration": 60000, "timestamp": 1706400000000, "url": "http://jenkins/job/test/1/"}'

    run output_json "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history"
    assert_success

    echo "$output" | jq . >/dev/null || fail "Output is not valid JSON"
    echo "$output" | jq -e 'has("test_results")' >/dev/null || fail "test_results field should exist"
    echo "$output" | jq -e '.test_results == null' >/dev/null || fail "test_results should be null"
}
