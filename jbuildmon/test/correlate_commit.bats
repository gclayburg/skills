#!/usr/bin/env bats

# Unit tests for correlate_commit function
# Spec reference: bug2026-01-31-checkbuild-silent-exit-spec.md
# Plan reference: bug2026-01-31-checkbuild-silent-exit-plan.md#chunk-b

load test_helper

# Load the jenkins-common.sh library containing correlate_commit
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
# Test Case: Function returns 0 when SHA is "unknown"
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 2
# -----------------------------------------------------------------------------
@test "correlate_commit_returns_0_for_unknown_sha" {
    run correlate_commit "unknown"
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 when SHA is empty string
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 2
# -----------------------------------------------------------------------------
@test "correlate_commit_returns_0_for_empty_sha" {
    run correlate_commit ""
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 when SHA doesn't match hex pattern
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 2
# -----------------------------------------------------------------------------
@test "correlate_commit_returns_0_for_invalid_sha_format" {
    # Test with non-hex characters
    run correlate_commit "not-a-valid-sha"
    assert_success

    # Test with too short SHA
    run correlate_commit "abc12"
    assert_success

    # Test with special characters
    run correlate_commit "abc123!"
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: Function outputs "unknown" for invalid SHA format
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 2
# -----------------------------------------------------------------------------
@test "correlate_commit_outputs_unknown_for_invalid_sha" {
    run correlate_commit "not-a-valid-sha"
    assert_success
    assert_output "unknown"
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 when not in a git repository
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 3
# -----------------------------------------------------------------------------
@test "correlate_commit_returns_0_for_git_failure" {
    # Run from a non-git directory
    cd "${TEST_TEMP_DIR}"

    # Use a valid-looking SHA format to pass format validation
    # but run from a non-git directory to trigger git failure
    run correlate_commit "abc1234567890123456789012345678901234567"
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: Function outputs "unknown" when git fails
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 3
# -----------------------------------------------------------------------------
@test "correlate_commit_outputs_unknown_for_git_failure" {
    # Run from a non-git directory
    cd "${TEST_TEMP_DIR}"

    # Use a valid-looking SHA format to pass format validation
    run correlate_commit "abc1234567890123456789012345678901234567"
    assert_success
    assert_output "unknown"
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 for valid SHA scenarios (existing behavior)
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution
# -----------------------------------------------------------------------------
@test "correlate_commit_returns_0_for_valid_scenarios" {
    # Get the current HEAD SHA from the project repo
    cd "${PROJECT_DIR}"
    local head_sha
    head_sha=$(git rev-parse HEAD)

    # Test with current HEAD - should return "your_commit"
    run correlate_commit "$head_sha"
    assert_success
    assert_output "your_commit"

    # Test with a parent commit if it exists - should return "in_history"
    local parent_sha
    parent_sha=$(git rev-parse HEAD~1 2>/dev/null) || true
    if [[ -n "$parent_sha" ]]; then
        run correlate_commit "$parent_sha"
        assert_success
        assert_output "in_history"
    fi
}
