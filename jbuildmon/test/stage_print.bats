#!/usr/bin/env bats

# Unit tests for print_stage_line function
# Spec reference: full-stage-print-spec.md, Section: Stage Display Format
# Plan reference: full-stage-print-plan.md, Chunk C

load test_helper

# Load the jenkins-common.sh library containing print_stage_line
setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

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

# -----------------------------------------------------------------------------
# Test Case: SUCCESS stage shows green with duration
# Spec: full-stage-print-spec.md, Section: Completed Stages
# -----------------------------------------------------------------------------
@test "print_stage_line_success" {
    # Set NO_COLOR to avoid ANSI codes in output comparison
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:34:56"; }

    run print_stage_line "Build" "SUCCESS" 15000
    assert_success
    assert_output "[12:34:56] ℹ   Stage: Build (15s)"
}

@test "print_stage_line_success_sub_second" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:44:42"; }

    run print_stage_line "Deploy" "SUCCESS" 500
    assert_success
    assert_output "[16:44:42] ℹ   Stage: Deploy (<1s)"
}

@test "print_stage_line_success_minutes" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:46:41"; }

    run print_stage_line "Unit Tests" "SUCCESS" 122000
    assert_success
    assert_output "[16:46:41] ℹ   Stage: Unit Tests (2m 2s)"
}

# -----------------------------------------------------------------------------
# Test Case: FAILED stage shows red with duration and marker
# Spec: full-stage-print-spec.md, Section: Completed Stages
# -----------------------------------------------------------------------------
@test "print_stage_line_failed" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:46:41"; }

    run print_stage_line "Unit Tests" "FAILED" 122000
    assert_success
    # Should contain duration and FAILED marker
    assert_output "[16:46:41] ℹ   Stage: Unit Tests (2m 2s)    ← FAILED"
}

@test "print_stage_line_failed_with_marker" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "10:00:00"; }

    run print_stage_line "Deploy" "FAILED" 5000
    assert_success
    [[ "$output" == *"← FAILED"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: UNSTABLE stage shows yellow with duration
# Spec: full-stage-print-spec.md, Section: Completed Stages
# -----------------------------------------------------------------------------
@test "print_stage_line_unstable" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "14:20:00"; }

    run print_stage_line "Integration Tests" "UNSTABLE" 60000
    assert_success
    assert_output "[14:20:00] ℹ   Stage: Integration Tests (1m 0s)"
}

# -----------------------------------------------------------------------------
# Test Case: IN_PROGRESS shows cyan with "(running)"
# Spec: full-stage-print-spec.md, Section: In-Progress Stages
# -----------------------------------------------------------------------------
@test "print_stage_line_in_progress" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:44:39"; }

    run print_stage_line "Unit Tests" "IN_PROGRESS"
    assert_success
    assert_output "[16:44:39] ℹ   Stage: Unit Tests (running)"
}

@test "print_stage_line_in_progress_ignores_duration" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:44:39"; }

    # Even if duration is passed, IN_PROGRESS should show "(running)"
    run print_stage_line "Build" "IN_PROGRESS" 5000
    assert_success
    assert_output "[16:44:39] ℹ   Stage: Build (running)"
}

# -----------------------------------------------------------------------------
# Test Case: NOT_EXECUTED shows dim with "(not executed)"
# Spec: full-stage-print-spec.md, Section: Not-Executed Stages
# -----------------------------------------------------------------------------
@test "print_stage_line_not_executed" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:46:41"; }

    run print_stage_line "Deploy" "NOT_EXECUTED"
    assert_success
    assert_output "[16:46:41] ℹ   Stage: Deploy (not executed)"
}

@test "print_stage_line_not_executed_ignores_duration" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:46:41"; }

    # Even if duration is passed, NOT_EXECUTED should show "(not executed)"
    run print_stage_line "Deploy" "NOT_EXECUTED" 0
    assert_success
    assert_output "[16:46:41] ℹ   Stage: Deploy (not executed)"
}

# -----------------------------------------------------------------------------
# Test Case: ABORTED stage handling
# Spec: full-stage-print-spec.md, Section: API Data Source (status types)
# -----------------------------------------------------------------------------
@test "print_stage_line_aborted" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "17:00:00"; }

    run print_stage_line "Deploy" "ABORTED"
    assert_success
    assert_output "[17:00:00] ℹ   Stage: Deploy (aborted)"
}

# -----------------------------------------------------------------------------
# Test Case: Output format matches specification
# Spec: full-stage-print-spec.md, Section: Stage Display Format
# -----------------------------------------------------------------------------
@test "print_stage_line_format" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:44:23"; }

    run print_stage_line "Initialize Submodules" "SUCCESS" 10000
    assert_success
    # Verify format: [HH:MM:SS] ℹ   Stage: <name> (<duration>)
    assert_output "[16:44:23] ℹ   Stage: Initialize Submodules (10s)"
}

@test "print_stage_line_format_with_spaces_in_name" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:00:00"; }

    run print_stage_line "Run Integration Tests" "SUCCESS" 30000
    assert_success
    assert_output "[12:00:00] ℹ   Stage: Run Integration Tests (30s)"
}

# -----------------------------------------------------------------------------
# Test Case: Works correctly when NO_COLOR is set
# Spec: full-stage-print-spec.md, Section: Color coding
# -----------------------------------------------------------------------------
@test "print_stage_line_no_color" {
    export NO_COLOR=1
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:34:56"; }

    run print_stage_line "Build" "SUCCESS" 15000
    assert_success
    # Output should not contain ANSI escape codes
    [[ "$output" != *$'\033'* ]]
    assert_output "[12:34:56] ℹ   Stage: Build (15s)"
}

@test "print_stage_line_no_color_failed" {
    export NO_COLOR=1
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:34:56"; }

    run print_stage_line "Tests" "FAILED" 10000
    assert_success
    # Output should not contain ANSI escape codes
    [[ "$output" != *$'\033'* ]]
    # Should still contain FAILED marker
    [[ "$output" == *"← FAILED"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Unknown status falls back to showing duration
# Spec: Handle edge cases gracefully
# -----------------------------------------------------------------------------
@test "print_stage_line_unknown_status" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:00:00"; }

    run print_stage_line "Build" "UNKNOWN_STATUS" 5000
    assert_success
    assert_output "[12:00:00] ℹ   Stage: Build (5s)"
}

# -----------------------------------------------------------------------------
# Test Case: Empty stage name is handled
# -----------------------------------------------------------------------------
@test "print_stage_line_empty_name" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:00:00"; }

    run print_stage_line "" "SUCCESS" 5000
    assert_success
    assert_output "[12:00:00] ℹ   Stage:  (5s)"
}

# -----------------------------------------------------------------------------
# Test Case: Verify FAILED marker is appended correctly
# Spec: full-stage-print-spec.md, Section: Failed Build example
# -----------------------------------------------------------------------------
@test "print_stage_line_failed_marker_position" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "16:46:41"; }

    run print_stage_line "Unit Tests" "FAILED" 122000
    assert_success
    # The marker should come after the closing parenthesis
    [[ "$output" == *"(2m 2s)"*"← FAILED"* ]]
}
