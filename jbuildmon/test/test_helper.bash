#!/usr/bin/env bash

# Get the directory containing this helper
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# Load bats helper libraries
load "${TEST_DIR}/test_helper/bats-support/load"
load "${TEST_DIR}/test_helper/bats-assert/load"
load "${TEST_DIR}/test_helper/bats-file/load"

# Prevent BASH_ENV from re-sourcing sandbox environment in subprocesses.
# Without this, test overrides (export/unset of JENKINS_* vars) get clobbered
# when bats spawns buildgit as a child process.
unset BASH_ENV

# Prepend test/bin to PATH so the mock curl script intercepts all network calls.
# This runs at load time (not inside setup()), so it applies regardless of whether
# a test file defines its own setup(). Tests needing specific curl behavior can
# prepend their own mock earlier in PATH (e.g., buildgit_errors.bats).
export PATH="${TEST_DIR}/bin:${PATH}"

# Common setup for all tests
setup() {
    # Create a temporary directory for test artifacts
    TEST_TEMP_DIR="$(mktemp -d)"

    # Store original environment
    ORIG_JENKINS_URL="${JENKINS_URL:-}"
    ORIG_JENKINS_USER_ID="${JENKINS_USER_ID:-}"
    ORIG_JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"
}

# Common teardown for all tests
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

# Helper: Create a mock git repository
create_mock_git_repo() {
    local repo_dir="${1:-${TEST_TEMP_DIR}/repo}"
    mkdir -p "${repo_dir}"
    cd "${repo_dir}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    echo "${repo_dir}"
}

# Helper: Create mock AGENTS.md with JOB_NAME
create_mock_agents_md() {
    local job_name="$1"
    local repo_dir="${2:-${TEST_TEMP_DIR}/repo}"
    cat > "${repo_dir}/AGENTS.md" << EOF
# AGENTS.md
JOB_NAME=${job_name}
EOF
}
