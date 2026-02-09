#!/usr/bin/env bats

# Tests for buildgit command routing and git passthrough
# Spec reference: buildgit-spec.md, Commands and Unknown Commands
# Plan reference: buildgit-plan.md, Chunk 3

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

    # Create a test git repository
    TEST_REPO="${TEST_TEMP_DIR}/repo"
    mkdir -p "${TEST_REPO}"
    cd "${TEST_REPO}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    echo "Second line" >> README.md
    git add README.md
    git commit --quiet -m "Second commit"
}

teardown() {
    # Clean up temporary directory
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi

    # Restore original environment
    export JENKINS_URL="${ORIG_JENKINS_URL}"
    export JENKINS_USER_ID="${ORIG_JENKINS_USER_ID}"
    export JENKINS_API_TOKEN="${ORIG_JENKINS_API_TOKEN}"
}

# =============================================================================
# Test Cases: Command Routing to Handlers
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: status command routes to status handler
# Spec: Commands
# -----------------------------------------------------------------------------
@test "route_status_command" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" status

    # Status command is implemented - it shows git status then tries Jenkins
    # Without valid Jenkins config, it will fail after git status
    # But we can verify it routes correctly by seeing git status output
    assert_output --partial "On branch"
}

# -----------------------------------------------------------------------------
# Test Case: push command routes to push handler
# Spec: Commands
# -----------------------------------------------------------------------------
@test "route_push_command" {
    cd "${TEST_REPO}"

    # Use --no-follow to skip Jenkins monitoring (which would fail without Jenkins)
    run "${PROJECT_DIR}/buildgit" push --no-follow

    # Push handler runs git push, which fails without a remote
    # This verifies the command routes correctly to cmd_push
    assert_failure
    assert_output --partial "No configured push destination"
}

# -----------------------------------------------------------------------------
# Test Case: build command routes to build handler
# Spec: Commands
# -----------------------------------------------------------------------------
@test "route_build_command" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" build

    # Build handler is now implemented and requires a job name
    # It fails because no AGENTS.md or --job flag is provided
    assert_failure
    # Should show error about job name requirement
    assert_output --partial "could not determine job name"
}

# =============================================================================
# Test Cases: Git Passthrough
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: log command passes through to git log
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_log" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" log --oneline -1

    assert_success
    # Should show the most recent commit message
    assert_output --partial "Second commit"
}

# -----------------------------------------------------------------------------
# Test Case: diff command passes through to git diff
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_diff" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" diff HEAD~1

    assert_success
    # Should show the diff of the last commit
    assert_output --partial "Second line"
}

# -----------------------------------------------------------------------------
# Test Case: branch command passes through to git
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_branch" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" branch --list

    assert_success
    # Should show master or main branch
    assert_output --regexp "(master|main)"
}

# -----------------------------------------------------------------------------
# Test Case: checkout -b passes through to git checkout
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_checkout" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" checkout -b feature-test

    assert_success
    # Verify branch was created
    run git branch --list
    assert_output --partial "feature-test"
}

# -----------------------------------------------------------------------------
# Test Case: Arguments are preserved in passthrough
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_preserves_args" {
    cd "${TEST_REPO}"

    # Use log with multiple arguments
    run "${PROJECT_DIR}/buildgit" log --oneline --no-walk HEAD~1

    assert_success
    # Should show the first commit (not the second)
    assert_output --partial "Initial commit"
}

# -----------------------------------------------------------------------------
# Test Case: Git exit code is returned from passthrough
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_exit_code" {
    cd "${TEST_REPO}"

    # Try to show a non-existent ref
    run "${PROJECT_DIR}/buildgit" show nonexistent-ref

    # Git should fail with non-zero exit code
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: Git error messages pass through
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_error_message" {
    cd "${TEST_REPO}"

    # Try to checkout a non-existent branch
    run "${PROJECT_DIR}/buildgit" checkout nonexistent-branch

    assert_failure
    # Git's error message should be visible
    assert_output --partial "nonexistent-branch"
}

# -----------------------------------------------------------------------------
# Test Case: Passthrough works with global options
# Spec: Unknown Commands + Global Options
# -----------------------------------------------------------------------------
@test "passthrough_with_global_options" {
    cd "${TEST_REPO}"

    # Use global --verbose flag with passthrough command
    run "${PROJECT_DIR}/buildgit" --verbose log --oneline -1

    assert_success
    assert_output --partial "Second commit"
}

# -----------------------------------------------------------------------------
# Test Case: Passthrough works with job flag (even though not used)
# Spec: Unknown Commands + Global Options
# -----------------------------------------------------------------------------
@test "passthrough_with_job_flag" {
    cd "${TEST_REPO}"

    # Job flag should be parsed but passthrough still works
    run "${PROJECT_DIR}/buildgit" -j somejob log --oneline -1

    assert_success
    assert_output --partial "Second commit"
}

# -----------------------------------------------------------------------------
# Test Case: rev-parse passes through for HEAD info
# Spec: Unknown Commands
# -----------------------------------------------------------------------------
@test "passthrough_rev_parse" {
    cd "${TEST_REPO}"

    run "${PROJECT_DIR}/buildgit" rev-parse --short HEAD

    assert_success
    # Should return a short commit hash (7-8 chars)
    assert_output --regexp "^[0-9a-f]{7,8}$"
}
