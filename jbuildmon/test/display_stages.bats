#!/usr/bin/env bats

# Unit tests for display functions with stage output
# Spec reference: full-stage-print-spec.md, Section: Display Functions
# Plan reference: full-stage-print-plan.md, Chunk F

load test_helper

# Load the jenkins-common.sh library
setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
    FIXTURES_DIR="${TEST_DIR}/fixtures"

    # Set NO_COLOR to avoid ANSI codes in output comparison
    export NO_COLOR=1

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock _timestamp for predictable output
    _timestamp() {
        echo "12:34:56"
    }
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# Helper: Mock get_all_stages to return fixture data
mock_get_all_stages_from_file() {
    local fixture_file="$1"
    # Extract stages array from the fixture file
    cat "$fixture_file" | jq '.stages // []'
}

# -----------------------------------------------------------------------------
# Test Case: _display_all_stages helper function
# Spec: full-stage-print-spec.md, Section: Display Functions
# -----------------------------------------------------------------------------
@test "_display_all_stages shows all stages in order" {
    # Mock get_all_stages to return test data
    get_all_stages() {
        echo '[
            {"name":"Initialize Submodules","status":"SUCCESS","startTimeMillis":1706889863000,"durationMillis":10000},
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Unit Tests","status":"SUCCESS","startTimeMillis":1706889899000,"durationMillis":122000}
        ]'
    }

    run _display_all_stages "test-job" "42"
    assert_success
    assert_line --index 0 "[12:34:56] ℹ   Stage: Initialize Submodules (10s)"
    assert_line --index 1 "[12:34:56] ℹ   Stage: Build (15s)"
    assert_line --index 2 "[12:34:56] ℹ   Stage: Unit Tests (2m 2s)"
}

@test "_display_all_stages shows running stage with (running)" {
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Unit Tests","status":"IN_PROGRESS","startTimeMillis":1706889899000,"durationMillis":0}
        ]'
    }

    run _display_all_stages "test-job" "42"
    assert_success
    assert_line --index 0 "[12:34:56] ℹ   Stage: Build (15s)"
    assert_line --index 1 "[12:34:56] ℹ   Stage: Unit Tests (running)"
}

@test "_display_all_stages shows not-executed stages" {
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Test","status":"FAILED","startTimeMillis":1706889899000,"durationMillis":120000},
            {"name":"Deploy","status":"NOT_EXECUTED","startTimeMillis":0,"durationMillis":0}
        ]'
    }

    run _display_all_stages "test-job" "42"
    assert_success
    assert_line --index 0 "[12:34:56] ℹ   Stage: Build (15s)"
    assert_line --index 1 --partial "Stage: Test (2m 0s)"
    assert_line --index 1 --partial "FAILED"
    assert_line --index 2 "[12:34:56] ℹ   Stage: Deploy (not executed)"
}

@test "_display_all_stages handles empty stages" {
    get_all_stages() {
        echo '[]'
    }

    run _display_all_stages "test-job" "42"
    assert_success
    assert_output ""
}

@test "_display_all_stages handles various statuses" {
    get_all_stages() {
        cat "${FIXTURES_DIR}/wfapi_describe_various_statuses.json" | jq '.stages // []'
    }

    run _display_all_stages "test-job" "10"
    assert_success
    # Should have 6 stages
    assert_line --index 0 "[12:34:56] ℹ   Stage: Checkout (5s)"
    assert_line --index 1 "[12:34:56] ℹ   Stage: Build (30s)"
    assert_line --index 2 --partial "Test (2m 0s)"
    assert_line --index 2 --partial "FAILED"
    assert_line --index 3 "[12:34:56] ℹ   Stage: Deploy (not executed)"
    assert_line --index 4 "[12:34:56] ℹ   Stage: Cleanup (aborted)"
    assert_line --index 5 "[12:34:56] ℹ   Stage: Notify (<1s)"
}

# -----------------------------------------------------------------------------
# Test Case: display_success_output includes all stage lines
# Spec: full-stage-print-spec.md, Section: Successful Build
# -----------------------------------------------------------------------------
@test "display_success_shows_all_stages" {
    get_all_stages() {
        echo '[
            {"name":"Initialize Submodules","status":"SUCCESS","startTimeMillis":1706889863000,"durationMillis":10000},
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Unit Tests","status":"SUCCESS","startTimeMillis":1706889899000,"durationMillis":122000},
            {"name":"Deploy","status":"SUCCESS","startTimeMillis":1706890021000,"durationMillis":500}
        ]'
    }

    # Mock correlate_commit to avoid git operations
    correlate_commit() { echo "your_commit"; }

    local build_json='{"number":42,"result":"SUCCESS","building":false,"duration":147500,"timestamp":1706889863000,"url":"http://jenkins/job/test/42/"}'

    run display_success_output "test-job" "42" "$build_json" "automated" "buildtriggerdude" "abc1234" "Test commit" "your_commit"
    assert_success
    # Output should contain stage lines
    assert_output --partial "Stage: Initialize Submodules (10s)"
    assert_output --partial "Stage: Build (15s)"
    assert_output --partial "Stage: Unit Tests (2m 2s)"
    assert_output --partial "Stage: Deploy (<1s)"
    # Should also contain the success banner
    assert_output --partial "BUILD SUCCESSFUL"
}

# -----------------------------------------------------------------------------
# Test Case: display_failure_output shows completed stages
# Spec: full-stage-print-spec.md, Section: Failed Build
# -----------------------------------------------------------------------------
@test "display_failure_shows_completed_stages" {
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Test","status":"FAILED","startTimeMillis":1706889899000,"durationMillis":120000}
        ]'
    }

    # Mock other functions to avoid actual API calls
    correlate_commit() { echo "your_commit"; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() { echo ""; }
    extract_error_lines() { echo "Some error"; }

    local build_json='{"number":42,"result":"FAILURE","building":false,"duration":135000,"timestamp":1706889863000,"url":"http://jenkins/job/test/42/"}'

    run display_failure_output "test-job" "42" "$build_json" "automated" "buildtriggerdude" "abc1234" "Test commit" "your_commit" ""
    assert_success
    assert_output --partial "Stage: Build (15s)"
    assert_output --partial "Stage: Test (2m 0s)"
    assert_output --partial "FAILED"
    assert_output --partial "BUILD FAILED"
}

@test "display_failure_shows_not_executed" {
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Test","status":"FAILED","startTimeMillis":1706889899000,"durationMillis":120000},
            {"name":"Deploy","status":"NOT_EXECUTED","startTimeMillis":0,"durationMillis":0}
        ]'
    }

    correlate_commit() { echo "your_commit"; }
    get_failed_stage() { echo "Test"; }
    detect_all_downstream_builds() { echo ""; }
    find_failed_downstream_build() { echo ""; }
    fetch_test_results() { echo ""; }
    extract_error_lines() { echo "Some error"; }

    local build_json='{"number":42,"result":"FAILURE","building":false,"duration":135000,"timestamp":1706889863000,"url":"http://jenkins/job/test/42/"}'

    run display_failure_output "test-job" "42" "$build_json" "automated" "buildtriggerdude" "abc1234" "Test commit" "your_commit" ""
    assert_success
    assert_output --partial "Stage: Deploy (not executed)"
}

# -----------------------------------------------------------------------------
# Test Case: display_building_output shows header without stages
# Spec: unify-follow-log-spec.md, Section 2 - stages are streamed separately
# (Updated: stages removed from header per unified output spec)
# -----------------------------------------------------------------------------
@test "display_building_shows_running" {
    get_all_stages() {
        echo '[
            {"name":"Initialize Submodules","status":"SUCCESS","startTimeMillis":1706889863000,"durationMillis":10000},
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Unit Tests","status":"IN_PROGRESS","startTimeMillis":1706889899000,"durationMillis":0}
        ]'
    }

    correlate_commit() { echo "your_commit"; }

    local build_json='{"number":42,"result":null,"building":true,"duration":0,"timestamp":1706889863000,"url":"http://jenkins/job/test/42/"}'

    run display_building_output "test-job" "42" "$build_json" "automated" "buildtriggerdude" "abc1234" "Test commit" "your_commit" "Unit Tests"
    assert_success
    # Stages are no longer displayed in the header (they are streamed separately)
    # Spec: unify-follow-log-spec.md, Section 2 (Build Header)
    refute_output --partial "Stage: Initialize Submodules"
    refute_output --partial "Stage: Build"
    refute_output --partial "Stage: Unit Tests"
    assert_output --partial "BUILD IN PROGRESS"
}

# -----------------------------------------------------------------------------
# Test Case: Stages displayed in execution order
# Spec: full-stage-print-spec.md, Section: Example Output
# -----------------------------------------------------------------------------
@test "display_stages_correct_order" {
    get_all_stages() {
        echo '[
            {"name":"Stage1","status":"SUCCESS","startTimeMillis":1000000,"durationMillis":5000},
            {"name":"Stage2","status":"SUCCESS","startTimeMillis":2000000,"durationMillis":10000},
            {"name":"Stage3","status":"SUCCESS","startTimeMillis":3000000,"durationMillis":15000}
        ]'
    }

    run _display_all_stages "test-job" "42"
    assert_success
    # Verify order by line indices
    assert_line --index 0 --partial "Stage1"
    assert_line --index 1 --partial "Stage2"
    assert_line --index 2 --partial "Stage3"
}

# -----------------------------------------------------------------------------
# Test Case: Stages have correct color coding (verify with NO_COLOR)
# Spec: full-stage-print-spec.md, Section: Color coding
# -----------------------------------------------------------------------------
@test "display_stages_no_ansi_when_no_color" {
    export NO_COLOR=1
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:34:56"; }

    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Test","status":"FAILED","startTimeMillis":1706889899000,"durationMillis":120000}
        ]'
    }

    run _display_all_stages "test-job" "42"
    assert_success
    # Output should not contain ANSI escape codes
    [[ "$output" != *$'\033'* ]]
}

# -----------------------------------------------------------------------------
# Test Case: One-shot status displays all stages
# Spec: full-stage-print-spec.md, Section: buildgit status
# -----------------------------------------------------------------------------
@test "display_success_output_includes_stages_section" {
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000}
        ]'
    }

    correlate_commit() { echo "your_commit"; }

    local build_json='{"number":42,"result":"SUCCESS","building":false,"duration":15000,"timestamp":1706889863000,"url":"http://jenkins/job/test/42/"}'

    run display_success_output "test-job" "42" "$build_json" "automated" "buildtriggerdude" "abc1234" "Test commit" "your_commit"
    assert_success
    # Verify stage output appears in the display
    assert_output --partial "Stage: Build (15s)"
}

# -----------------------------------------------------------------------------
# Test Case: Mixed stage statuses display correctly
# Spec: full-stage-print-spec.md, Section: API Data Source (status types)
# -----------------------------------------------------------------------------
@test "_display_all_stages_mixed_statuses" {
    get_all_stages() {
        echo '[
            {"name":"S1","status":"SUCCESS","startTimeMillis":1000,"durationMillis":5000},
            {"name":"S2","status":"FAILED","startTimeMillis":2000,"durationMillis":10000},
            {"name":"S3","status":"UNSTABLE","startTimeMillis":3000,"durationMillis":15000},
            {"name":"S4","status":"IN_PROGRESS","startTimeMillis":4000,"durationMillis":0},
            {"name":"S5","status":"NOT_EXECUTED","startTimeMillis":0,"durationMillis":0},
            {"name":"S6","status":"ABORTED","startTimeMillis":5000,"durationMillis":1000}
        ]'
    }

    run _display_all_stages "test-job" "42"
    assert_success
    assert_line --index 0 "[12:34:56] ℹ   Stage: S1 (5s)"
    assert_line --index 1 --partial "S2 (10s)"
    assert_line --index 1 --partial "FAILED"
    assert_line --index 2 "[12:34:56] ℹ   Stage: S3 (15s)"
    assert_line --index 3 "[12:34:56] ℹ   Stage: S4 (running)"
    assert_line --index 4 "[12:34:56] ℹ   Stage: S5 (not executed)"
    assert_line --index 5 "[12:34:56] ℹ   Stage: S6 (aborted)"
}
