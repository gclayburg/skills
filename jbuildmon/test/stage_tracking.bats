#!/usr/bin/env bats

# Unit tests for track_stage_changes function
# Spec reference: full-stage-print-spec.md, Section: Stage Tracking
# Plan reference: full-stage-print-plan.md, Chunk D

load test_helper

# Load the jenkins-common.sh library containing track_stage_changes
setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
    FIXTURES_DIR="${TEST_DIR}/fixtures"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Set up Jenkins environment for tests (won't be used with mocking)
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

# -----------------------------------------------------------------------------
# Test Case: First call returns current state, no prints
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_first_call" {
    # Mock get_all_stages to return initial state with one stage in progress
    get_all_stages() {
        echo '[
            {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0}
        ]'
    }

    # First call with empty previous state
    local output stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "[]" "false" 2>&1 >/dev/null)
    output=$(track_stage_changes "test-job" "42" "[]" "false" 2>/dev/null)

    # Verify we get current state back
    [[ $(echo "$output" | jq 'length') -eq 1 ]]
    [[ $(echo "$output" | jq -r '.[0].name') == "Build" ]]
    [[ $(echo "$output" | jq -r '.[0].status') == "IN_PROGRESS" ]]

    # Verify no stage completion lines printed (first call with non-verbose)
    [[ -z "$stderr_output" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Detects IN_PROGRESS to SUCCESS transition, prints completion
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_stage_completes" {
    # Previous state: Build was IN_PROGRESS
    local previous_state='[
        {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0}
    ]'

    # Mock get_all_stages to return Build as SUCCESS
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000}
        ]'
    }

    # Capture both stdout and stderr
    local output stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>&1 >/dev/null)
    output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>/dev/null)

    # Verify stage completion line was printed to stderr
    [[ "$stderr_output" == *"Stage: Build (15s)"* ]]

    # Verify current state returned
    [[ $(echo "$output" | jq -r '.[0].status') == "SUCCESS" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Detects IN_PROGRESS to FAILED transition, prints with marker
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_stage_fails" {
    # Previous state: Build was IN_PROGRESS
    local previous_state='[
        {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0}
    ]'

    # Mock get_all_stages to return Build as FAILED
    get_all_stages() {
        echo '[
            {"name":"Build","status":"FAILED","startTimeMillis":1706889879000,"durationMillis":120000}
        ]'
    }

    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>&1 >/dev/null)

    # Verify FAILED stage line was printed with marker
    [[ "$stderr_output" == *"Stage: Build (2m 0s)"* ]]
    [[ "$stderr_output" == *"FAILED"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Detects IN_PROGRESS to UNSTABLE transition
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_stage_unstable" {
    # Previous state: Tests was IN_PROGRESS
    local previous_state='[
        {"name":"Tests","status":"IN_PROGRESS","startTimeMillis":1706889899000,"durationMillis":0}
    ]'

    # Mock get_all_stages to return Tests as UNSTABLE
    get_all_stages() {
        echo '[
            {"name":"Tests","status":"UNSTABLE","startTimeMillis":1706889899000,"durationMillis":65000}
        ]'
    }

    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>&1 >/dev/null)

    # Verify UNSTABLE stage line was printed
    [[ "$stderr_output" == *"Stage: Tests (1m 5s)"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Shows currently running stage with previous state
# Spec: full-stage-print-spec.md, Section: In-Progress Stages
# -----------------------------------------------------------------------------
@test "track_stage_changes_shows_running" {
    # Previous state: Build completed, Tests is new
    local previous_state='[
        {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000}
    ]'

    # Mock get_all_stages to return Build complete, Tests in progress
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Tests","status":"IN_PROGRESS","startTimeMillis":1706889899000,"durationMillis":0}
        ]'
    }

    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>&1 >/dev/null)

    # Verify running stage is shown
    [[ "$stderr_output" == *"Stage: Tests (running)"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Handles multiple stages changing in one poll
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_multiple_transitions" {
    # Previous state: Two stages in progress
    local previous_state='[
        {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0},
        {"name":"Lint","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0}
    ]'

    # Mock get_all_stages to return both completed
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Lint","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":5000},
            {"name":"Tests","status":"IN_PROGRESS","startTimeMillis":1706889899000,"durationMillis":0}
        ]'
    }

    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>&1 >/dev/null)

    # Verify both completed stages were printed
    [[ "$stderr_output" == *"Stage: Build (15s)"* ]]
    [[ "$stderr_output" == *"Stage: Lint (5s)"* ]]
    # And the running stage
    [[ "$stderr_output" == *"Stage: Tests (running)"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Verbose mode shows running stage on first call
# Spec: full-stage-print-spec.md, Section: Verbose mode
# -----------------------------------------------------------------------------
@test "track_stage_changes_verbose_mode" {
    # Mock get_all_stages with a stage in progress
    get_all_stages() {
        echo '[
            {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0}
        ]'
    }

    # First call with verbose mode enabled
    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "[]" "true" 2>&1 >/dev/null)

    # Verify running stage is shown even on first call in verbose mode
    [[ "$stderr_output" == *"Stage: Build (running)"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Non-verbose mode does not show running stage on first call
# Spec: full-stage-print-spec.md, Section: Non-verbose mode
# -----------------------------------------------------------------------------
@test "track_stage_changes_non_verbose" {
    # Mock get_all_stages with a stage in progress
    get_all_stages() {
        echo '[
            {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0}
        ]'
    }

    # First call with non-verbose mode (default)
    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "[]" "false" 2>&1 >/dev/null)

    # Verify running stage is NOT shown on first call in non-verbose mode
    [[ -z "$stderr_output" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Handles empty current stages gracefully
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_empty_current" {
    # Previous state with some data
    local previous_state='[
        {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000}
    ]'

    # Mock get_all_stages to return empty
    get_all_stages() {
        echo '[]'
    }

    local output
    output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>/dev/null)

    # Verify previous state is returned unchanged
    [[ $(echo "$output" | jq 'length') -eq 1 ]]
    [[ $(echo "$output" | jq -r '.[0].name') == "Build" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Handles null/empty previous state
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_null_previous" {
    # Mock get_all_stages
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000}
        ]'
    }

    # Call with null previous state
    local output
    output=$(track_stage_changes "test-job" "42" "null" "false" 2>/dev/null)

    # Verify we get current state back
    [[ $(echo "$output" | jq 'length') -eq 1 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Does not print stages that were already completed
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_no_reprint_completed" {
    # Previous state: Build already SUCCESS
    local previous_state='[
        {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000}
    ]'

    # Mock get_all_stages to return same completed state
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":1706889879000,"durationMillis":15000},
            {"name":"Tests","status":"IN_PROGRESS","startTimeMillis":1706889899000,"durationMillis":0}
        ]'
    }

    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>&1 >/dev/null)

    # Verify Build is NOT reprinted (only Tests running is shown)
    [[ "$stderr_output" != *"Stage: Build (15s)"* ]]
    [[ "$stderr_output" == *"Stage: Tests (running)"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: ABORTED stage transition is printed
# Spec: full-stage-print-spec.md, Section: Stage Tracking
# -----------------------------------------------------------------------------
@test "track_stage_changes_stage_aborted" {
    # Previous state: Build was IN_PROGRESS
    local previous_state='[
        {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1706889879000,"durationMillis":0}
    ]'

    # Mock get_all_stages to return Build as ABORTED
    get_all_stages() {
        echo '[
            {"name":"Build","status":"ABORTED","startTimeMillis":1706889879000,"durationMillis":30000}
        ]'
    }

    local stderr_output
    stderr_output=$(track_stage_changes "test-job" "42" "$previous_state" "false" 2>&1 >/dev/null)

    # Verify ABORTED stage line was printed
    [[ "$stderr_output" == *"Stage: Build (aborted)"* ]]
}
