#!/usr/bin/env bash
#
# test-job-discovery.sh - Tests for Chunk 6: Job Name Discovery
#
# Tests the discover_job_name function and its helpers

set -euo pipefail

# Get script directory and source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/jenkins-common.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test utilities
test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "${COLOR_RED}✗${COLOR_RESET} $1"
    echo "  Expected: $2"
    echo "  Got:      $3"
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Initialize a test git repo
setup_test_repo() {
    local repo_dir="$1"
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "test" > README.md
    git add README.md
    git commit -q -m "initial"
}

# =============================================================================
# Test: AGENTS.md with JOB_NAME=testjob
# =============================================================================
test_agents_md_basic() {
    run_test
    local repo="${TEST_DIR}/repo1"
    setup_test_repo "$repo"

    echo "JOB_NAME=testjob" > AGENTS.md
    git remote add origin "git@github.com:org/other-repo.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "testjob" ]]; then
        test_pass "AGENTS.md with JOB_NAME=testjob"
    else
        test_fail "AGENTS.md with JOB_NAME=testjob" "testjob" "$result"
    fi
}

# =============================================================================
# Test: AGENTS.md with JOB_NAME = testjob (spaces around =)
# =============================================================================
test_agents_md_with_spaces() {
    run_test
    local repo="${TEST_DIR}/repo2"
    setup_test_repo "$repo"

    echo "JOB_NAME = testjob" > AGENTS.md
    git remote add origin "git@github.com:org/other-repo.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "testjob" ]]; then
        test_pass "AGENTS.md with JOB_NAME = testjob (spaces)"
    else
        test_fail "AGENTS.md with JOB_NAME = testjob (spaces)" "testjob" "$result"
    fi
}

# =============================================================================
# Test: AGENTS.md with - JOB_NAME=testjob (markdown list item)
# =============================================================================
test_agents_md_with_dash() {
    run_test
    local repo="${TEST_DIR}/repo3"
    setup_test_repo "$repo"

    cat > AGENTS.md <<'EOF'
# Build Configuration

- JOB_NAME=testjob
- OTHER_VAR=value
EOF
    git remote add origin "git@github.com:org/other-repo.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "testjob" ]]; then
        test_pass "AGENTS.md with - JOB_NAME=testjob (list item)"
    else
        test_fail "AGENTS.md with - JOB_NAME=testjob (list item)" "testjob" "$result"
    fi
}

# =============================================================================
# Test: AGENTS.md with embedded JOB_NAME in text
# =============================================================================
test_agents_md_embedded() {
    run_test
    local repo="${TEST_DIR}/repo4"
    setup_test_repo "$repo"

    cat > AGENTS.md <<'EOF'
# Jenkins Configuration

The Jenkins job is JOB_NAME=testjob for this project.
EOF
    git remote add origin "git@github.com:org/other-repo.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "testjob" ]]; then
        test_pass "AGENTS.md with embedded JOB_NAME in text"
    else
        test_fail "AGENTS.md with embedded JOB_NAME in text" "testjob" "$result"
    fi
}

# =============================================================================
# Test: Git origin github SSH format
# =============================================================================
test_git_origin_github_ssh() {
    ru n_test
    local repo="${TEST_DIR}/repo5"
    setup_test_repo "$repo"

    git remote add origin "git@github.com:org/my-project.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "my-project" ]]; then
        test_pass "Git origin git@github.com:org/my-project.git"
    else
        test_fail "Git origin git@github.com:org/my-project.git" "my-project" "$result"
    fi
}

# =============================================================================
# Test: Git origin HTTPS format
# =============================================================================
test_git_origin_https() {
    run_test
    local repo="${TEST_DIR}/repo6"
    setup_test_repo "$repo"

    git remote add origin "https://github.com/org/my-project.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "my-project" ]]; then
        test_pass "Git origin https://github.com/org/my-project.git"
    else
        test_fail "Git origin https://github.com/org/my-project.git" "my-project" "$result"
    fi
}

# =============================================================================
# Test: Git origin SSH with port
# =============================================================================
test_git_origin_ssh_with_port() {
    run_test
    local repo="${TEST_DIR}/repo7"
    setup_test_repo "$repo"

    git remote add origin "ssh://git@server:2233/home/git/ralph1.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "ralph1" ]]; then
        test_pass "Git origin ssh://git@server:2233/home/git/ralph1.git"
    else
        test_fail "Git origin ssh://git@server:2233/home/git/ralph1.git" "ralph1" "$result"
    fi
}

# =============================================================================
# Test: Git origin simple SSH format
# =============================================================================
test_git_origin_simple_ssh() {
    run_test
    local repo="${TEST_DIR}/repo8"
    setup_test_repo "$repo"

    git remote add origin "git@server:path/to/repo.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "repo" ]]; then
        test_pass "Git origin git@server:path/to/repo.git"
    else
        test_fail "Git origin git@server:path/to/repo.git" "repo" "$result"
    fi
}

# =============================================================================
# Test: No AGENTS.md and no origin (should fail)
# =============================================================================
test_no_agents_no_origin() {
    run_test
    local repo="${TEST_DIR}/repo9"
    setup_test_repo "$repo"

    # Don't add origin remote

    local result
    if ! result=$(discover_job_name 2>/dev/null); then
        test_pass "No AGENTS.md and no origin returns error"
    else
        test_fail "No AGENTS.md and no origin returns error" "error/empty" "$result"
    fi
}

# =============================================================================
# Test: AGENTS.md takes priority over git origin
# =============================================================================
test_agents_md_priority() {
    run_test
    local repo="${TEST_DIR}/repo10"
    setup_test_repo "$repo"

    echo "JOB_NAME=agents-job" > AGENTS.md
    git remote add origin "git@github.com:org/origin-job.git"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "agents-job" ]]; then
        test_pass "AGENTS.md takes priority over git origin"
    else
        test_fail "AGENTS.md takes priority over git origin" "agents-job" "$result"
    fi
}

# =============================================================================
# Test: Git origin without .git suffix
# =============================================================================
test_git_origin_no_git_suffix() {
    run_test
    local repo="${TEST_DIR}/repo11"
    setup_test_repo "$repo"

    git remote add origin "https://github.com/org/my-project"

    local result
    result=$(discover_job_name)

    if [[ "$result" == "my-project" ]]; then
        test_pass "Git origin without .git suffix"
    else
        test_fail "Git origin without .git suffix" "my-project" "$result"
    fi
}

# =============================================================================
# Run all tests
# =============================================================================
echo ""
echo "${COLOR_BOLD}Running Job Name Discovery Tests${COLOR_RESET}"
echo "================================="
echo ""

test_agents_md_basic
test_agents_md_with_spaces
test_agents_md_with_dash
test_agents_md_embedded
test_git_origin_github_ssh
test_git_origin_https
test_git_origin_ssh_with_port
test_git_origin_simple_ssh
test_no_agents_no_origin
test_agents_md_priority
test_git_origin_no_git_suffix

echo ""
echo "================================="
echo "Tests: ${TESTS_RUN}  Passed: ${TESTS_PASSED}  Failed: ${TESTS_FAILED}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
