#!/usr/bin/env bats

# Unit tests for format_stage_duration function
# Spec reference: full-stage-print-spec.md, Section: Duration format
# Plan reference: full-stage-print-plan.md, Chunk A

load test_helper

# Load the jenkins-common.sh library containing format_stage_duration
setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# -----------------------------------------------------------------------------
# Test Case: Sub-second duration returns "<1s"
# Spec: full-stage-print-spec.md, Section: Duration format - Sub-second durations
# -----------------------------------------------------------------------------
@test "format_stage_duration_sub_second" {
    run format_stage_duration 500
    assert_success
    assert_output "<1s"
}

@test "format_stage_duration_sub_second_999ms" {
    run format_stage_duration 999
    assert_success
    assert_output "<1s"
}

@test "format_stage_duration_sub_second_1ms" {
    run format_stage_duration 1
    assert_success
    assert_output "<1s"
}

# -----------------------------------------------------------------------------
# Test Case: Duration 0ms returns "<1s"
# Spec: full-stage-print-spec.md, Section: Duration format
# -----------------------------------------------------------------------------
@test "format_stage_duration_zero" {
    run format_stage_duration 0
    assert_success
    assert_output "<1s"
}

# -----------------------------------------------------------------------------
# Test Case: Seconds only (no minutes/hours)
# Spec: full-stage-print-spec.md, Section: Duration format - Seconds only
# -----------------------------------------------------------------------------
@test "format_stage_duration_seconds_only" {
    run format_stage_duration 15000
    assert_success
    assert_output "15s"
}

@test "format_stage_duration_exactly_1_second" {
    run format_stage_duration 1000
    assert_success
    assert_output "1s"
}

@test "format_stage_duration_59_seconds" {
    run format_stage_duration 59000
    assert_success
    assert_output "59s"
}

# -----------------------------------------------------------------------------
# Test Case: Minutes and seconds
# Spec: full-stage-print-spec.md, Section: Duration format - Minutes and seconds
# -----------------------------------------------------------------------------
@test "format_stage_duration_minutes_seconds" {
    run format_stage_duration 124000
    assert_success
    assert_output "2m 4s"
}

@test "format_stage_duration_exactly_1_minute" {
    run format_stage_duration 60000
    assert_success
    assert_output "1m 0s"
}

@test "format_stage_duration_minutes_no_seconds" {
    run format_stage_duration 120000
    assert_success
    assert_output "2m 0s"
}

# -----------------------------------------------------------------------------
# Test Case: Hours, minutes, and seconds
# Spec: full-stage-print-spec.md, Section: Duration format - Hours, minutes, seconds
# -----------------------------------------------------------------------------
@test "format_stage_duration_hours" {
    run format_stage_duration 3930000
    assert_success
    assert_output "1h 5m 30s"
}

@test "format_stage_duration_exactly_1_hour" {
    run format_stage_duration 3600000
    assert_success
    assert_output "1h 0m 0s"
}

@test "format_stage_duration_hours_no_minutes" {
    run format_stage_duration 3630000
    assert_success
    assert_output "1h 0m 30s"
}

# -----------------------------------------------------------------------------
# Test Case: Empty input returns "unknown"
# Spec: full-stage-print-spec.md, Section: Duration format - Edge cases
# -----------------------------------------------------------------------------
@test "format_stage_duration_empty" {
    run format_stage_duration ""
    assert_success
    assert_output "unknown"
}

# -----------------------------------------------------------------------------
# Test Case: Null input returns "unknown"
# Spec: full-stage-print-spec.md, Section: Duration format - Edge cases
# -----------------------------------------------------------------------------
@test "format_stage_duration_null" {
    run format_stage_duration "null"
    assert_success
    assert_output "unknown"
}

# -----------------------------------------------------------------------------
# Test Case: Non-numeric input returns "unknown"
# Spec: full-stage-print-spec.md, Section: Duration format - Edge cases
# -----------------------------------------------------------------------------
@test "format_stage_duration_invalid" {
    run format_stage_duration "abc"
    assert_success
    assert_output "unknown"
}

@test "format_stage_duration_negative" {
    run format_stage_duration "-1000"
    assert_success
    assert_output "unknown"
}

@test "format_stage_duration_float" {
    run format_stage_duration "1000.5"
    assert_success
    assert_output "unknown"
}

# -----------------------------------------------------------------------------
# Test Case: No argument returns "unknown"
# Spec: full-stage-print-spec.md, Section: Duration format - Edge cases
# -----------------------------------------------------------------------------
@test "format_stage_duration_no_argument" {
    run format_stage_duration
    assert_success
    assert_output "unknown"
}
