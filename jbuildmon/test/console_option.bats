#!/usr/bin/env bats

# Tests for --console global option
# Spec reference: console-on-unstable-spec.md

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

    # Disable colors for testing
    export NO_COLOR=1

    # Source buildgit for testing
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi

    export JENKINS_URL="${ORIG_JENKINS_URL}"
    export JENKINS_USER_ID="${ORIG_JENKINS_USER_ID}"
    export JENKINS_API_TOKEN="${ORIG_JENKINS_API_TOKEN}"
}

# =============================================================================
# Helper: Create args test wrapper (includes --console parsing)
# =============================================================================

create_console_args_wrapper() {
    cat > "${TEST_TEMP_DIR}/buildgit_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR}"

source "${PROJECT_DIR}/lib/jenkins-common.sh"

JOB_NAME=""
VERBOSE_MODE=false
CONSOLE_MODE=""
COMMAND=""
COMMAND_ARGS=()
EOF

    # Extract parse_global_options and show_usage from buildgit
    sed -n '/^parse_global_options()/,/^}/p' "${PROJECT_DIR}/buildgit" >> "${TEST_TEMP_DIR}/buildgit_test.sh"
    sed -n '/^show_usage()/,/^}/p' "${PROJECT_DIR}/buildgit" >> "${TEST_TEMP_DIR}/buildgit_test.sh"

    cat >> "${TEST_TEMP_DIR}/buildgit_test.sh" << 'EOF'

main() {
    parse_global_options "$@"
    if [[ -z "$COMMAND" ]]; then
        show_usage
        exit 1
    fi
    echo "JOB_NAME: ${JOB_NAME}"
    echo "VERBOSE_MODE: ${VERBOSE_MODE}"
    echo "CONSOLE_MODE: ${CONSOLE_MODE}"
    echo "COMMAND: ${COMMAND}"
    echo "COMMAND_ARGS: ${COMMAND_ARGS[*]:-}"
}
main "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/buildgit_test.sh"
}

# =============================================================================
# Test Cases: Option Parsing
# =============================================================================

@test "parse_console_short_flag_auto" {
    export PROJECT_DIR
    create_console_args_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -c auto status

    assert_success
    assert_output --partial "CONSOLE_MODE: auto"
    assert_output --partial "COMMAND: status"
}

@test "parse_console_long_flag_auto" {
    export PROJECT_DIR
    create_console_args_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" --console auto status

    assert_success
    assert_output --partial "CONSOLE_MODE: auto"
    assert_output --partial "COMMAND: status"
}

@test "parse_console_with_number" {
    export PROJECT_DIR
    create_console_args_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -c 50 status

    assert_success
    assert_output --partial "CONSOLE_MODE: 50"
    assert_output --partial "COMMAND: status"
}

@test "parse_console_with_job_and_verbose" {
    export PROJECT_DIR
    create_console_args_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -j myjob -c auto --verbose status

    assert_success
    assert_output --partial "JOB_NAME: myjob"
    assert_output --partial "CONSOLE_MODE: auto"
    assert_output --partial "VERBOSE_MODE: true"
    assert_output --partial "COMMAND: status"
}

@test "parse_console_missing_value" {
    export PROJECT_DIR
    create_console_args_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -c

    assert_failure
    assert_output --partial "requires a mode"
}

@test "parse_console_invalid_mode" {
    export PROJECT_DIR
    create_console_args_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" -c invalid status

    assert_failure
    assert_output --partial "Invalid console mode"
}

@test "parse_console_default_empty" {
    export PROJECT_DIR
    create_console_args_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_test.sh" status

    assert_success
    assert_output --partial "CONSOLE_MODE: "
}

@test "help_shows_console_option" {
    run "${PROJECT_DIR}/buildgit" --help

    assert_success
    assert_output --partial "-c, --console <mode>"
    assert_output --partial "Show console log output"
}

# =============================================================================
# Test Cases: display_failure_output - Error Logs Suppression
# Spec: console-on-unstable-spec.md, Section 2 and Decision Table
# =============================================================================

@test "display_failure_suppresses_error_logs_when_test_failures_exist" {
    # UNSTABLE with test failures, no --console → no Error Logs
    CONSOLE_MODE=""
    fetch_test_results() {
        echo '{"failCount":3,"passCount":32,"skipCount":0,"totalCount":35}'
    }
    display_test_results() {
        echo "=== Test Results ==="
        echo "  Total: 35 | Passed: 32 | Failed: 3 | Skipped: 0"
    }
    get_all_stages() { echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: some noise"; }

    local build_json='{"result":"UNSTABLE","duration":60000,"timestamp":1706400000000,"url":"http://jenkins/job/test/1/"}'

    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "console output"
    assert_success
    assert_output --partial "=== Test Results ==="
    refute_output --partial "=== Error Logs ==="
    refute_output --partial "=== Console Log"
}

@test "display_failure_shows_error_logs_when_no_test_failures" {
    # FAILURE without test failures → show Error Logs (default behavior)
    CONSOLE_MODE=""
    fetch_test_results() { echo ""; }
    get_all_stages() { echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: build failed"; }

    local build_json='{"result":"FAILURE","duration":60000,"timestamp":1706400000000,"url":"http://jenkins/job/test/1/"}'

    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "ERROR: build failed"
    assert_success
    assert_output --partial "=== Error Logs ==="
}

@test "display_failure_shows_error_logs_with_console_auto" {
    # UNSTABLE with test failures + --console auto → show Error Logs
    CONSOLE_MODE="auto"
    fetch_test_results() {
        echo '{"failCount":3,"passCount":32,"skipCount":0,"totalCount":35}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }
    get_all_stages() { echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: some error"; }

    local build_json='{"result":"UNSTABLE","duration":60000,"timestamp":1706400000000,"url":"http://jenkins/job/test/1/"}'

    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "console output"
    assert_success
    assert_output --partial "=== Error Logs ==="
}

@test "display_failure_shows_last_n_lines_with_console_number" {
    # UNSTABLE with test failures + --console 5 → show last 5 lines
    CONSOLE_MODE="5"
    fetch_test_results() {
        echo '{"failCount":3,"passCount":32,"skipCount":0,"totalCount":35}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }
    get_all_stages() { echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: some error"; }

    local console_text
    console_text=$(printf "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10")

    local build_json='{"result":"UNSTABLE","duration":60000,"timestamp":1706400000000,"url":"http://jenkins/job/test/1/"}'

    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "$console_text"
    assert_success
    assert_output --partial "=== Console Log (last 5 lines) ==="
    assert_output --partial "line6"
    assert_output --partial "line10"
    refute_output --partial "=== Error Logs ==="
}

@test "display_failure_suppresses_for_failure_with_test_failures" {
    # FAILURE with test failures (possible: post-build step fails after tests ran), no --console → no Error Logs
    CONSOLE_MODE=""
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }
    get_all_stages() { echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    extract_error_lines() { echo "ERROR: noise"; }

    local build_json='{"result":"FAILURE","duration":60000,"timestamp":1706400000000,"url":"http://jenkins/job/test/1/"}'

    run display_failure_output "test-job" "123" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "console output"
    assert_success
    assert_output --partial "=== Test Results ==="
    refute_output --partial "=== Error Logs ==="
}

# =============================================================================
# Test Cases: _handle_build_completion - Console Log Output
# Spec: console-on-unstable-spec.md, Section 3
# =============================================================================

@test "completion_no_console_by_default_with_test_failures" {
    # _handle_build_completion: no console output by default when test failures exist
    CONSOLE_MODE=""
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    get_console_output() { echo "some console output"; }
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }

    run _handle_build_completion "testjob" "42"
    assert_output --partial "=== Test Results ==="
    assert_output --partial "Finished: UNSTABLE"
    refute_output --partial "=== Error Logs ==="
    refute_output --partial "=== Console Log"
}

@test "completion_shows_error_logs_with_console_auto" {
    CONSOLE_MODE="auto"
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    get_console_output() { echo "some console output with ERROR: failure here"; }
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_output --partial "=== Error Logs ==="
    assert_output --partial "Finished: UNSTABLE"
}

@test "completion_shows_last_n_lines_with_console_number" {
    CONSOLE_MODE="3"
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    get_console_output() {
        printf "line1\nline2\nline3\nline4\nline5"
    }
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }

    run _handle_build_completion "testjob" "42"
    assert_output --partial "=== Console Log (last 3 lines) ==="
    assert_output --partial "line3"
    assert_output --partial "line5"
    assert_output --partial "Finished: UNSTABLE"
}

# =============================================================================
# Test Cases: JSON Output
# Spec: console-on-unstable-spec.md, Section 3 (JSON output)
# =============================================================================

@test "json_omits_error_summary_when_test_failures_no_console" {
    CONSOLE_MODE=""
    verify_jenkins_connection() { return 0; }
    verify_job_exists() { return 0; }
    get_last_build_number() { echo "42"; }
    get_build_info() {
        echo '{"number":42,"result":"UNSTABLE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test/42/"}'
    }
    get_console_output() { echo "Started by user testuser"; echo "ERROR: some noise"; }
    get_all_stages() { echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    format_test_results_json() {
        echo '{"total":33,"passed":32,"failed":1,"skipped":0}'
    }

    run output_json "test-job" "42" \
        '{"number":42,"result":"UNSTABLE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test/42/"}' \
        "manual" "testuser" "abc1234" "Test commit" "in_history" "ERROR: some noise"

    assert_success
    # error_summary should be null
    local error_summary
    error_summary=$(echo "$output" | jq -r '.failure.error_summary')
    [[ "$error_summary" == "null" ]] || fail "Expected error_summary to be null, got: $error_summary"
}

@test "json_populates_console_log_with_number_mode" {
    CONSOLE_MODE="3"
    verify_jenkins_connection() { return 0; }
    verify_job_exists() { return 0; }
    get_last_build_number() { echo "42"; }
    get_build_info() {
        echo '{"number":42,"result":"UNSTABLE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test/42/"}'
    }
    get_all_stages() { echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    format_test_results_json() {
        echo '{"total":33,"passed":32,"failed":1,"skipped":0}'
    }

    local console_text
    console_text=$(printf "line1\nline2\nline3\nline4\nline5")

    run output_json "test-job" "42" \
        '{"number":42,"result":"UNSTABLE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test/42/"}' \
        "manual" "testuser" "abc1234" "Test commit" "in_history" "$console_text"

    assert_success
    # console_log should be populated with last 3 lines
    local console_log
    console_log=$(echo "$output" | jq -r '.failure.console_log')
    [[ "$console_log" == *"line3"* ]] || fail "Expected console_log to contain line3, got: $console_log"
    [[ "$console_log" == *"line5"* ]] || fail "Expected console_log to contain line5, got: $console_log"
    # error_summary should be null
    local error_summary
    error_summary=$(echo "$output" | jq -r '.failure.error_summary')
    [[ "$error_summary" == "null" ]] || fail "Expected error_summary to be null, got: $error_summary"
}

@test "json_keeps_error_summary_with_console_auto" {
    CONSOLE_MODE="auto"
    get_all_stages() { echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    format_test_results_json() {
        echo '{"total":33,"passed":32,"failed":1,"skipped":0}'
    }

    run output_json "test-job" "42" \
        '{"number":42,"result":"UNSTABLE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test/42/"}' \
        "manual" "testuser" "abc1234" "Test commit" "in_history" "ERROR: test failure details"

    assert_success
    # error_summary should be populated (not null)
    local error_summary
    error_summary=$(echo "$output" | jq -r '.failure.error_summary')
    [[ "$error_summary" != "null" ]] || fail "Expected error_summary to be populated with --console auto"
}

@test "json_failure_no_tests_keeps_error_summary" {
    # FAILURE without test results → error_summary populated as before
    CONSOLE_MODE=""
    get_all_stages() { echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'; }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() { echo ""; }

    run output_json "test-job" "42" \
        '{"number":42,"result":"FAILURE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test/42/"}' \
        "manual" "testuser" "abc1234" "Test commit" "in_history" "ERROR: build compilation failed"

    assert_success
    # error_summary should be populated
    local error_summary
    error_summary=$(echo "$output" | jq -r '.failure.error_summary')
    [[ "$error_summary" != "null" ]] || fail "Expected error_summary to be populated for FAILURE without test results"
}
