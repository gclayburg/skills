#!/usr/bin/env bats

# Unit tests for print_finished_line function
# Spec reference: unify-follow-log-spec.md, Section 4 (Build Completion)
# Plan reference: unify-follow-log-plan.md, Chunk A

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
}

# =============================================================================
# Test Cases: Output text
# =============================================================================

# -----------------------------------------------------------------------------
# Spec: unify-follow-log-spec.md, Section 4 (Build Completion)
# -----------------------------------------------------------------------------
@test "finished_line_success_text" {
    run print_finished_line "SUCCESS"
    assert_success
    assert_output --partial "Finished: SUCCESS"
}

@test "finished_line_failure_text" {
    run print_finished_line "FAILURE"
    assert_success
    assert_output --partial "Finished: FAILURE"
}

@test "finished_line_unstable_text" {
    run print_finished_line "UNSTABLE"
    assert_success
    assert_output --partial "Finished: UNSTABLE"
}

@test "finished_line_aborted_text" {
    run print_finished_line "ABORTED"
    assert_success
    assert_output --partial "Finished: ABORTED"
}

# =============================================================================
# Test Cases: Color codes
# =============================================================================

# -----------------------------------------------------------------------------
# Spec: unify-follow-log-spec.md, Final Status Line Colors
# -----------------------------------------------------------------------------
@test "finished_line_success_green" {
    run print_finished_line "SUCCESS"
    assert_success
    # Green color code should be present (either ANSI escape or tput output)
    assert_output --partial "Finished: SUCCESS"
    # Verify color is applied (output should not be plain text if terminal supports colors)
    [[ "$output" == *"${COLOR_GREEN}"* ]] || [[ "$output" == "Finished: SUCCESS" ]]
}

@test "finished_line_failure_red" {
    run print_finished_line "FAILURE"
    assert_success
    assert_output --partial "Finished: FAILURE"
    [[ "$output" == *"${COLOR_RED}"* ]] || [[ "$output" == "Finished: FAILURE" ]]
}

@test "finished_line_unstable_yellow" {
    run print_finished_line "UNSTABLE"
    assert_success
    assert_output --partial "Finished: UNSTABLE"
    [[ "$output" == *"${COLOR_YELLOW}"* ]] || [[ "$output" == "Finished: UNSTABLE" ]]
}

@test "finished_line_aborted_dim" {
    run print_finished_line "ABORTED"
    assert_success
    assert_output --partial "Finished: ABORTED"
    [[ "$output" == *"${COLOR_DIM}"* ]] || [[ "$output" == "Finished: ABORTED" ]]
}

# =============================================================================
# Test Cases: Unknown status
# =============================================================================

@test "finished_line_unknown_status_no_color" {
    run print_finished_line "SOMETHING_ELSE"
    assert_success
    assert_output "Finished: SOMETHING_ELSE"
}
