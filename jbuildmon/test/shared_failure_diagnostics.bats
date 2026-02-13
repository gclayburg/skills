#!/usr/bin/env bats

# Unit tests for _display_failure_diagnostics shared function
# Spec reference: refactor-shared-failure-diagnostics-spec.md

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
# Test Cases: Monitoring mode shows Failed Jobs tree
# Spec: refactor-shared-failure-diagnostics-spec.md, Acceptance Criteria 1-3
# =============================================================================

@test "monitoring mode shows Failed Jobs tree with downstream" {
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    get_console_output() {
        if [[ "$1" == "downstream-job" ]]; then
            echo "downstream error output"
        else
            echo "Triggering downstream build: downstream-job #10"
        fi
    }
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() {
        local console="$1"
        if [[ "$console" == *"Triggering downstream"* ]]; then
            echo "downstream-job 10"
        else
            echo ""
        fi
    }
    find_failed_downstream_build() { echo "downstream-job 10"; }
    check_build_failed() { return 0; }
    fetch_test_results() { echo ""; }
    extract_error_lines() { echo "ERROR: downstream failure"; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Failed Jobs ==="
    assert_output --partial "downstream-job"
    assert_output --partial "Finished: FAILURE"
}

@test "monitoring mode shows Failed Jobs without downstream" {
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    get_console_output() {
        echo "Started by user admin
ERROR: compilation failed
Finished: FAILURE"
    }
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() { echo ""; }
    extract_error_lines() { echo "ERROR: compilation failed"; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "=== Failed Jobs ==="
    assert_output --partial "testjob"
    assert_output --partial "FAILED"
    assert_output --partial "Finished: FAILURE"
}

# =============================================================================
# Test Cases: Snapshot and monitoring produce same diagnostics
# Spec: refactor-shared-failure-diagnostics-spec.md, Testing section
# =============================================================================

@test "snapshot and monitoring produce same diagnostics sections" {
    # Set up common mocks
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() { echo ""; }
    extract_error_lines() { echo "ERROR: build failed"; }

    local console_output="ERROR: build failed"

    # Get monitoring output
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    get_console_output() { echo "$console_output"; }

    run _handle_build_completion "testjob" "42"
    local monitoring_output="$output"

    # Get snapshot output
    local build_json='{"result":"FAILURE","duration":60000,"timestamp":1706400000000,"url":"http://jenkins/job/test/1/"}'

    run display_failure_output "testjob" "42" "$build_json" "manual" "testuser" "abc1234" "Test commit" "in_history" "$console_output"
    local snapshot_output="$output"

    # Both should contain Failed Jobs tree
    echo "$monitoring_output" | grep -q "=== Failed Jobs ===" || fail "Monitoring output missing Failed Jobs"
    echo "$snapshot_output" | grep -q "=== Failed Jobs ===" || fail "Snapshot output missing Failed Jobs"

    # Both should contain Error Logs
    echo "$monitoring_output" | grep -q "=== Error Logs ===" || fail "Monitoring output missing Error Logs"
    echo "$snapshot_output" | grep -q "=== Error Logs ===" || fail "Snapshot output missing Error Logs"
}

# =============================================================================
# Test Cases: Early failure skips Failed Jobs tree
# Spec: refactor-shared-failure-diagnostics-spec.md, Acceptance Criteria 7
# =============================================================================

@test "early failure skips Failed Jobs tree" {
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    get_console_output() {
        echo "Started by user admin
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed
Finished: FAILURE"
    }
    get_all_stages() { echo "[]"; }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    # Should show Console Output (early failure)
    assert_output --partial "=== Console Output ==="
    # Should NOT show Failed Jobs tree
    refute_output --partial "=== Failed Jobs ==="
    # Should NOT show Error Logs
    refute_output --partial "=== Error Logs ==="
}

# =============================================================================
# Test Cases: Single code path verification
# Spec: refactor-shared-failure-diagnostics-spec.md, Acceptance Criteria 6
# =============================================================================

@test "display_failure_output calls _display_failure_diagnostics" {
    # Verify display_failure_output does NOT directly call the sub-functions
    local source_file="${PROJECT_DIR}/lib/jenkins-common.sh"

    # Extract just the display_failure_output function body
    local func_body
    func_body=$(sed -n '/^display_failure_output()/,/^}/p' "$source_file")

    # Should call _display_failure_diagnostics
    echo "$func_body" | grep -q "_display_failure_diagnostics" || fail "display_failure_output should call _display_failure_diagnostics"

    # Should NOT directly call these functions
    echo "$func_body" | grep -v "^#" | grep -q "_display_failed_jobs_tree" && fail "display_failure_output should not directly call _display_failed_jobs_tree" || true
    echo "$func_body" | grep -v "^#" | grep -q "fetch_test_results" && fail "display_failure_output should not directly call fetch_test_results" || true
    echo "$func_body" | grep -v "^#" | grep -q "display_test_results" && fail "display_failure_output should not directly call display_test_results" || true
    echo "$func_body" | grep -v "^#" | grep -q "_display_error_log_section" && fail "display_failure_output should not directly call _display_error_log_section" || true
}

@test "_handle_build_completion calls _display_failure_diagnostics" {
    # Verify _handle_build_completion does NOT directly call the sub-functions
    local source_file="${PROJECT_DIR}/buildgit"

    # Extract just the _handle_build_completion function body
    local func_body
    func_body=$(sed -n '/^_handle_build_completion()/,/^}/p' "$source_file")

    # Should call _display_failure_diagnostics
    echo "$func_body" | grep -q "_display_failure_diagnostics" || fail "_handle_build_completion should call _display_failure_diagnostics"

    # Should NOT directly call these functions
    echo "$func_body" | grep -v "^#" | grep -q "_display_early_failure_console" && fail "_handle_build_completion should not directly call _display_early_failure_console" || true
    echo "$func_body" | grep -v "^#" | grep -q "fetch_test_results" && fail "_handle_build_completion should not directly call fetch_test_results" || true
    echo "$func_body" | grep -v "^#" | grep -q "display_test_results" && fail "_handle_build_completion should not directly call display_test_results" || true
    echo "$func_body" | grep -v "^#" | grep -q "_display_error_log_section" && fail "_handle_build_completion should not directly call _display_error_log_section" || true
}

# =============================================================================
# Test Cases: JSON failure object matches human-readable detection
# Spec: refactor-shared-failure-diagnostics-spec.md, Acceptance Criteria 5
# =============================================================================

@test "JSON failure object matches human-readable for downstream failure" {
    get_all_stages() {
        echo '[{"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo "Build"; }
    detect_all_downstream_builds() {
        local console="$1"
        if [[ "$console" == *"Triggering downstream"* ]]; then
            echo "downstream-job 10"
        else
            echo ""
        fi
    }
    find_failed_downstream_build() {
        local console="$1"
        if [[ "$console" == *"Triggering downstream"* ]]; then
            echo "downstream-job 10"
        else
            echo ""
        fi
    }
    check_build_failed() { return 0; }
    get_console_output() {
        echo "downstream error output"
    }
    extract_error_lines() { echo "ERROR: downstream failure"; }

    local console_output="Triggering downstream: downstream-job #10"

    # Get JSON failure object
    run _build_failure_json "testjob" "42" "$console_output"
    assert_success

    local json_output="$output"

    # Verify JSON includes downstream job in failed_jobs
    local failed_jobs
    failed_jobs=$(echo "$json_output" | jq -r '.failed_jobs[]')
    echo "$failed_jobs" | grep -q "downstream-job" || fail "JSON failed_jobs should include downstream-job"

    # Verify root_cause_job is the downstream job
    local root_cause
    root_cause=$(echo "$json_output" | jq -r '.root_cause_job')
    [[ "$root_cause" == "downstream-job" ]] || fail "Expected root_cause_job to be downstream-job, got: $root_cause"

    # Verify human-readable output also shows the downstream job
    fetch_test_results() { echo ""; }
    run _display_failure_diagnostics "testjob" "42" "$console_output"
    assert_output --partial "=== Failed Jobs ==="
    assert_output --partial "downstream-job"
}

# =============================================================================
# Test Cases: Preserved behaviors
# Spec: refactor-shared-failure-diagnostics-spec.md, Acceptance Criteria 8-9
# =============================================================================

@test "test failure suppression preserved in monitoring mode" {
    CONSOLE_MODE=""
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    get_console_output() { echo "some console output"; }
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }

    run _handle_build_completion "testjob" "42"
    assert_output --partial "=== Test Results ==="
    assert_output --partial "=== Failed Jobs ==="
    refute_output --partial "=== Error Logs ==="
    assert_output --partial "Finished: UNSTABLE"
}

@test "console option preserved in monitoring mode" {
    CONSOLE_MODE="auto"
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    get_console_output() { echo "some console output with ERROR: failure here"; }
    get_all_stages() {
        echo '[{"name":"Test","status":"FAILED","startTimeMillis":0,"durationMillis":5000}]'
    }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    display_test_results() {
        echo "=== Test Results ==="
    }

    run _handle_build_completion "testjob" "42"
    assert_output --partial "=== Error Logs ==="
    assert_output --partial "=== Failed Jobs ==="
    assert_output --partial "Finished: UNSTABLE"
}
