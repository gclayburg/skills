#!/usr/bin/env bats

# Comprehensive unit tests for extract_stage_logs function
# Spec reference: bug1-jenkins-log-truncated-spec.md
# Plan reference: bug1-jenkins-log-truncated-plan.md#chunk-2

load test_helper

# Load the jenkins-common.sh library containing extract_stage_logs
setup() {
    # Call parent setup from test_helper
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # Source jenkins-common.sh to get extract_stage_logs function
    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# -----------------------------------------------------------------------------
# Test Case: Simple stage with no nesting
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Technical Requirements
# -----------------------------------------------------------------------------
@test "extract_stage_logs_simple_stage" {
    local console_output='[Pipeline] Start of Pipeline
[Pipeline] { (Build)
Building project...
Compilation successful
[Pipeline] }
[Pipeline] End of Pipeline'

    run extract_stage_logs "$console_output" "Build"
    assert_success
    assert_output --partial "Building project..."
    assert_output --partial "Compilation successful"
    # Should NOT include content outside the stage
    refute_output --partial "Start of Pipeline"
    refute_output --partial "End of Pipeline"
}

# -----------------------------------------------------------------------------
# Test Case: Nested dir block (from bug report)
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Technical Requirements
# This is the primary bug scenario - dir block's closing } was ending extraction early
# -----------------------------------------------------------------------------
@test "extract_stage_logs_nested_dir_block" {
    local console_output='[Pipeline] { (Unit Tests)
[Pipeline] dir
Running in /path/to/workspace
[Pipeline] {
[Pipeline] sh
+ ./test/bats/bin/bats test/smoke.bats
ok 1 smoke_test_passes
+ true
[Pipeline] }
[Pipeline] // dir
Post stage
[Pipeline] junit
Recording test results
[Pipeline] }
[Pipeline] { (Deploy)
Deploying...'

    run extract_stage_logs "$console_output" "Unit Tests"
    assert_success
    # Should include content from inside the nested dir block
    assert_output --partial "Running in /path/to/workspace"
    assert_output --partial "./test/bats/bin/bats test/smoke.bats"
    assert_output --partial "ok 1 smoke_test_passes"
    # Critical: Should include post-stage content after nested block closes
    assert_output --partial "Post stage"
    assert_output --partial "Recording test results"
    # Should NOT include content from the next stage
    refute_output --partial "Deploying..."
}

# -----------------------------------------------------------------------------
# Test Case: Deeply nested blocks (multiple levels)
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Edge Cases
# -----------------------------------------------------------------------------
@test "extract_stage_logs_deeply_nested" {
    local console_output='[Pipeline] { (Deploy)
[Pipeline] withEnv
Setting environment
[Pipeline] {
[Pipeline] dir
[Pipeline] {
[Pipeline] withCredentials
[Pipeline] {
[Pipeline] sh
+ deploy command executed
[Pipeline] }
[Pipeline] }
[Pipeline] }
Deploy complete
[Pipeline] }
[Pipeline] End'

    run extract_stage_logs "$console_output" "Deploy"
    assert_success
    # Should include all nested content
    assert_output --partial "Setting environment"
    assert_output --partial "deploy command executed"
    # Should include content after all nested blocks close but before stage ends
    assert_output --partial "Deploy complete"
    # Should NOT include content after stage ends
    refute_output --partial "[Pipeline] End"
}

# -----------------------------------------------------------------------------
# Test Case: Post-stage actions (junit, etc.) are included
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Technical Requirements
# -----------------------------------------------------------------------------
@test "extract_stage_logs_with_post_stage" {
    local console_output='[Pipeline] { (Test)
[Pipeline] sh
+ npm test
Tests passed
[Pipeline] }
[Pipeline] { (Verify)
[Pipeline] dir
[Pipeline] {
Running tests...
[Pipeline] }
[Pipeline] junit
Recording test results
[Pipeline] archiveArtifacts
Archiving artifacts
[Pipeline] }
[Pipeline] End'

    run extract_stage_logs "$console_output" "Verify"
    assert_success
    # Should include the nested block content
    assert_output --partial "Running tests..."
    # Should include post-stage actions
    assert_output --partial "Recording test results"
    assert_output --partial "Archiving artifacts"
}

# -----------------------------------------------------------------------------
# Test Case: Non-existent stage returns empty
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Edge Cases
# -----------------------------------------------------------------------------
@test "extract_stage_logs_nonexistent_stage" {
    local console_output='[Pipeline] { (Build)
Building...
[Pipeline] }
[Pipeline] { (Test)
Testing...
[Pipeline] }'

    run extract_stage_logs "$console_output" "NonExistent"
    assert_success
    # Output should be empty for non-existent stage
    assert_output ""
}

# -----------------------------------------------------------------------------
# Test Case: Missing end marker - falls back gracefully
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Edge Cases
# When stage end marker is missing, should return what was captured
# -----------------------------------------------------------------------------
@test "extract_stage_logs_no_end_marker" {
    local console_output='[Pipeline] { (Build)
Building started...
Compilation in progress...
This output was cut off'

    run extract_stage_logs "$console_output" "Build"
    assert_success
    # Should capture all lines after stage start even without proper end marker
    assert_output --partial "Building started..."
    assert_output --partial "Compilation in progress..."
    assert_output --partial "This output was cut off"
}

# -----------------------------------------------------------------------------
# Test Case: Multiple stages - extracts only requested stage
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Technical Requirements
# -----------------------------------------------------------------------------
@test "extract_stage_logs_multiple_stages" {
    local console_output='[Pipeline] { (Checkout)
Cloning repository...
[Pipeline] }
[Pipeline] { (Build)
Building project...
[Pipeline] }
[Pipeline] { (Test)
Running tests...
[Pipeline] }
[Pipeline] { (Deploy)
Deploying...
[Pipeline] }'

    run extract_stage_logs "$console_output" "Build"
    assert_success
    assert_output --partial "Building project..."
    # Should NOT include other stages
    refute_output --partial "Cloning repository..."
    refute_output --partial "Running tests..."
    refute_output --partial "Deploying..."
}

# -----------------------------------------------------------------------------
# Test Case: Stage with special characters in name
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Edge Cases
# -----------------------------------------------------------------------------
@test "extract_stage_logs_special_stage_name" {
    local console_output='[Pipeline] { (Unit Tests - Phase 1)
Running unit tests phase 1...
[Pipeline] }'

    run extract_stage_logs "$console_output" "Unit Tests - Phase 1"
    assert_success
    assert_output --partial "Running unit tests phase 1..."
}

# -----------------------------------------------------------------------------
# Test Case: Empty stage (only markers, no content)
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Edge Cases
# -----------------------------------------------------------------------------
@test "extract_stage_logs_empty_stage" {
    local console_output='[Pipeline] { (Empty)
[Pipeline] }'

    run extract_stage_logs "$console_output" "Empty"
    assert_success
    # Output should be empty (no content between markers)
    assert_output ""
}

# -----------------------------------------------------------------------------
# Test Case: Stage with only nested blocks (no other content)
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Technical Requirements
# -----------------------------------------------------------------------------
@test "extract_stage_logs_only_nested_blocks" {
    local console_output='[Pipeline] { (Setup)
[Pipeline] {
Inner content only
[Pipeline] }
[Pipeline] }'

    run extract_stage_logs "$console_output" "Setup"
    assert_success
    # Should include the nested block markers and content
    assert_output --partial "Inner content only"
}

# -----------------------------------------------------------------------------
# Test Case: Real-world nested structure from bug report
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Bug Description
# This replicates the exact structure that caused the original bug
# -----------------------------------------------------------------------------
@test "extract_stage_logs_real_world_bug_case" {
    local console_output='[Pipeline] { (Unit Tests)
[Pipeline] dir
Running in /var/lib/jenkins/workspace/my-job
[Pipeline] {
[Pipeline] sh
+ ./test/bats/bin/bats --tap test/smoke.bats
ok 1 smoke_test_passes
ok 2 smoke_test_assert_success
ok 3 smoke_test_assert_failure
+ true
[Pipeline] }
[Pipeline] // dir
Post stage
[Pipeline] junit
Recording test results
[Pipeline] }
[Pipeline] { (Integration Tests)
Starting integration tests...'

    run extract_stage_logs "$console_output" "Unit Tests"
    assert_success

    # Verify all content is captured including after nested block closes
    assert_output --partial "Running in /var/lib/jenkins/workspace/my-job"
    assert_output --partial "./test/bats/bin/bats --tap test/smoke.bats"
    assert_output --partial "ok 1 smoke_test_passes"
    assert_output --partial "ok 2 smoke_test_assert_success"
    assert_output --partial "ok 3 smoke_test_assert_failure"
    assert_output --partial "// dir"

    # CRITICAL: These must be included - this is what the bug was preventing
    assert_output --partial "Post stage"
    assert_output --partial "Recording test results"

    # Must NOT include content from next stage
    refute_output --partial "Starting integration tests..."
}

# =============================================================================
# Fallback Behavior Tests
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
# Plan: bug1-jenkins-log-truncated-plan.md#chunk-3
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Verify STAGE_LOG_MIN_LINES constant is set
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
# -----------------------------------------------------------------------------
@test "fallback_constants_defined" {
    # Verify the constants are defined in jenkins-common.sh
    [[ -n "${STAGE_LOG_MIN_LINES:-}" ]]
    [[ -n "${STAGE_LOG_FALLBACK_LINES:-}" ]]
    # Verify default values per spec
    [[ "$STAGE_LOG_MIN_LINES" -eq 5 ]]
    [[ "$STAGE_LOG_FALLBACK_LINES" -eq 50 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Stage extraction with exactly minimum lines is NOT fallback
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
# -----------------------------------------------------------------------------
@test "extract_stage_logs_exactly_minimum_lines" {
    local console_output='[Pipeline] { (Test)
Line 1
Line 2
Line 3
Line 4
Line 5
[Pipeline] }'

    run extract_stage_logs "$console_output" "Test"
    assert_success
    # Should have exactly 5 lines of content
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [[ "$line_count" -ge 5 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Stage extraction with fewer than minimum lines
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
# This should trigger fallback when used in _display_error_logs
# -----------------------------------------------------------------------------
@test "extract_stage_logs_fewer_than_minimum_lines" {
    local console_output='[Pipeline] { (Test)
Line 1
Line 2
[Pipeline] }'

    run extract_stage_logs "$console_output" "Test"
    assert_success
    # Should have fewer than 5 lines
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [[ "$line_count" -lt 5 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Empty extraction triggers fallback path
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
# -----------------------------------------------------------------------------
@test "extract_stage_logs_empty_triggers_fallback_path" {
    local console_output='[Pipeline] { (Build)
Building...
[Pipeline] }'

    # When stage doesn't exist, extraction returns empty
    run extract_stage_logs "$console_output" "NonExistent"
    assert_success
    assert_output ""
    # Empty output should trigger fallback in _display_error_logs
}
