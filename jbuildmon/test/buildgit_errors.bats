#!/usr/bin/env bats

# Tests for buildgit error handling and edge cases
# Spec reference: buildgit-spec.md, Error Handling section
# Plan reference: buildgit-plan.md, Chunk 8

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

# Helper to create a test git repository
create_test_repo() {
    TEST_REPO="${TEST_TEMP_DIR}/repo"
    mkdir -p "${TEST_REPO}"
    cd "${TEST_REPO}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
}

# Helper to set up mock Jenkins environment that simulates unavailable Jenkins.
# Uses a mock curl binary placed in PATH to avoid real network connections.
# The mock curl returns an empty body with HTTP code 000 (connection refused),
# which is what real curl returns when it cannot reach the server.
setup_invalid_jenkins() {
    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    # Install mock curl that simulates connection failure
    mkdir -p "${TEST_TEMP_DIR}/bin"
    cat > "${TEST_TEMP_DIR}/bin/curl" << 'EOF'
#!/usr/bin/env bash
# Mock curl: simulates connection failure (no HTTP response received).
# jenkins_api_with_status uses -w "\n%{http_code}"; real curl outputs empty
# body + newline + "000" when the connection is refused.
printf '\n000'
exit 7
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/curl"
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
}

# Helper to clear Jenkins environment (missing config)
clear_jenkins_env() {
    unset JENKINS_URL
    unset JENKINS_USER_ID
    unset JENKINS_API_TOKEN
}

# =============================================================================
# Test Cases: Jenkins Unavailable
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: status shows Jenkins error when Jenkins unavailable
# Spec: Error Handling - Jenkins Unavailable
# -----------------------------------------------------------------------------
@test "error_jenkins_unavailable_status" {
    create_test_repo
    setup_invalid_jenkins

    # Provide job name to skip job discovery and test Jenkins connectivity
    run "${PROJECT_DIR}/buildgit" -j testjob status

    # Should show Jenkins error
    assert_output --partial "cannot connect to Jenkins"
    # Should include actionable suggestion
    assert_output --partial "Suggestion:"
    # Should fail (Jenkins part failed)
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: push completes git push then shows Jenkins error
# Spec: Error Handling - Jenkins Unavailable
# -----------------------------------------------------------------------------
@test "error_jenkins_unavailable_push" {
    create_test_repo

    # Add a remote so push can "succeed" (or fail predictably)
    git remote add origin "${TEST_TEMP_DIR}/remote.git"
    git init --bare "${TEST_TEMP_DIR}/remote.git" 2>/dev/null

    setup_invalid_jenkins

    run "${PROJECT_DIR}/buildgit" push

    # Should show push attempt (may fail due to remote, but that's git's failure)
    # If git push succeeds to the bare repo, should then show Jenkins error
    # Either way, should fail
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: build fails immediately when Jenkins unavailable
# Spec: Error Handling - Jenkins Unavailable
# -----------------------------------------------------------------------------
@test "error_jenkins_unavailable_build" {
    create_test_repo
    setup_invalid_jenkins

    run "${PROJECT_DIR}/buildgit" -j testjob build

    # Should fail immediately
    assert_failure
    # Should show Jenkins connectivity error
    assert_output --partial "cannot connect to Jenkins"
    # Should include actionable suggestion
    assert_output --partial "Suggestion:"
}

# =============================================================================
# Test Cases: Non-Git Directory
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: status in non-git directory shows git error, attempts Jenkins
# Spec: Error Handling - Non-Git Directory
# -----------------------------------------------------------------------------
@test "error_non_git_directory_status" {
    cd "${TEST_TEMP_DIR}"
    # Don't create a git repo - just use temp dir
    setup_invalid_jenkins

    run "${PROJECT_DIR}/buildgit" status

    # Without a git repo, job discovery fails (no remote URL)
    assert_output --partial "could not determine job name"
    # Should fail
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: status with --job flag in non-git directory still attempts Jenkins
# Spec: Error Handling - Non-Git Directory
# -----------------------------------------------------------------------------
@test "error_non_git_directory_with_job" {
    cd "${TEST_TEMP_DIR}"
    # Don't create a git repo
    setup_invalid_jenkins

    run "${PROJECT_DIR}/buildgit" -j testjob status

    # With --job provided, skips job discovery and tries Jenkins connectivity
    assert_output --partial "cannot connect to Jenkins"
    assert_failure
}

# =============================================================================
# Test Cases: Job Detection Failure
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: status shows job detection error
# Spec: Error Handling - Job Detection Failure
# -----------------------------------------------------------------------------
@test "error_job_detection_failure_status" {
    create_test_repo
    # Set up Jenkins env but don't provide a job
    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
    # No AGENTS.md, no --job flag, no origin remote

    run "${PROJECT_DIR}/buildgit" status

    # Should show job detection error
    assert_output --partial "Could not determine Jenkins job name"
    # Should include suggestion
    assert_output --partial "Suggestion:"
    assert_output --partial "-j/--job"
    # Should fail
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: build exits with error when job detection fails
# Spec: Error Handling - Job Detection Failure
# -----------------------------------------------------------------------------
@test "error_job_detection_failure_build" {
    create_test_repo
    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
    # No AGENTS.md, no --job flag

    run "${PROJECT_DIR}/buildgit" build

    # Should fail
    assert_failure
    # Should show clear error about job name requirement
    assert_output --partial "could not determine job name"
    # Should include suggestion
    assert_output --partial "-j/--job"
}

# =============================================================================
# Test Cases: Missing Environment Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: status with missing Jenkins environment shows helpful error
# Spec: Error Handling - environment not configured
# -----------------------------------------------------------------------------
@test "error_missing_jenkins_env_status" {
    create_test_repo
    clear_jenkins_env

    run "${PROJECT_DIR}/buildgit" status

    # Should show environment error
    assert_output --partial "environment not configured"
    # Should include actionable suggestion
    assert_output --partial "JENKINS_URL"
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: push with missing Jenkins environment shows helpful error
# Spec: Error Handling - environment not configured
# -----------------------------------------------------------------------------
@test "error_missing_jenkins_env_push" {
    create_test_repo
    git init --bare "${TEST_TEMP_DIR}/remote.git" 2>/dev/null
    git remote add origin "${TEST_TEMP_DIR}/remote.git"
    # Set upstream tracking
    git push -u origin master 2>/dev/null || git push -u origin main 2>/dev/null || true
    # Make a new commit to push
    echo "new content" >> README.md
    git add README.md
    git commit --quiet -m "New commit"

    clear_jenkins_env

    run "${PROJECT_DIR}/buildgit" push

    # Should show push completed (or push error)
    # Should show environment error for Jenkins
    assert_output --partial "environment not configured"
    # Should include suggestion
    assert_output --partial "Suggestion:"
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: build with missing Jenkins environment fails with helpful error
# Spec: Error Handling - environment not configured
# -----------------------------------------------------------------------------
@test "error_missing_jenkins_env_build" {
    create_test_repo
    clear_jenkins_env

    run "${PROJECT_DIR}/buildgit" -j testjob build

    # Should fail immediately
    assert_failure
    # Should show environment error
    assert_output --partial "environment not configured"
    # Should include suggestion about setting environment variables
    assert_output --partial "JENKINS_URL"
}

# =============================================================================
# Test Cases: Actionable Error Messages
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: error messages include actionable suggestions
# Spec: Error Handling - actionable suggestions
# -----------------------------------------------------------------------------
@test "error_actionable_messages" {
    create_test_repo
    clear_jenkins_env

    # Test status command
    run "${PROJECT_DIR}/buildgit" status
    assert_output --partial "Suggestion:"

    # Test build command
    run "${PROJECT_DIR}/buildgit" -j testjob build
    assert_output --partial "Suggestion:"
}

# -----------------------------------------------------------------------------
# Test Case: job not found error includes suggestion
# Spec: Error Handling - actionable suggestions
# -----------------------------------------------------------------------------
@test "error_job_not_found_suggestion" {
    create_test_repo
    setup_invalid_jenkins

    run "${PROJECT_DIR}/buildgit" -j nonexistent-job build

    # Should fail
    assert_failure
    # Error message should include suggestion about verifying job name
    assert_output --partial "Suggestion:"
}

# =============================================================================
# Test Cases: Exit Codes
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: passthrough command returns git's exit code
# Spec: Exit Codes - Git command fails
# -----------------------------------------------------------------------------
@test "exit_code_git_passthrough_failure" {
    create_test_repo

    run "${PROJECT_DIR}/buildgit" checkout nonexistent-branch

    # Should return git's non-zero exit code
    assert_failure
}

# -----------------------------------------------------------------------------
# Test Case: status returns appropriate exit code on Jenkins failure
# Spec: Exit Codes
# -----------------------------------------------------------------------------
@test "exit_code_jenkins_status_failure" {
    create_test_repo
    setup_invalid_jenkins

    run "${PROJECT_DIR}/buildgit" status

    # Should return non-zero due to Jenkins failure
    assert_failure
}

# =============================================================================
# Test Cases: Graceful Degradation
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: push --no-follow works even with invalid Jenkins config
# Spec: Error Handling - graceful degradation for --no-follow
# -----------------------------------------------------------------------------
@test "graceful_degradation_push_no_follow" {
    create_test_repo
    git init --bare "${TEST_TEMP_DIR}/remote.git" 2>/dev/null
    git remote add origin "${TEST_TEMP_DIR}/remote.git"
    # Set upstream tracking with initial push
    git push -u origin master 2>/dev/null || git push -u origin main 2>/dev/null || true
    # Make a new commit to push
    echo "new content" >> README.md
    git add README.md
    git commit --quiet -m "New commit"

    setup_invalid_jenkins

    run "${PROJECT_DIR}/buildgit" push --no-follow

    # With --no-follow, should succeed (git push only)
    assert_success
    assert_output --partial "monitoring disabled"
}
