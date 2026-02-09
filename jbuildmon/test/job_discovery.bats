#!/usr/bin/env bats

# Unit tests for discover_job_name function
# Migrated from tests/test-job-discovery.sh

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# -----------------------------------------------------------------------------
# AGENTS.md-based discovery
# -----------------------------------------------------------------------------

@test "discover_job_name: AGENTS.md with JOB_NAME=testjob" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    echo "JOB_NAME=testjob" > AGENTS.md
    git remote add origin "git@github.com:org/other-repo.git"

    run discover_job_name
    assert_success
    assert_output "testjob"
}

@test "discover_job_name: AGENTS.md with spaces around =" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    echo "JOB_NAME = testjob" > AGENTS.md
    git remote add origin "git@github.com:org/other-repo.git"

    run discover_job_name
    assert_success
    assert_output "testjob"
}

@test "discover_job_name: AGENTS.md with markdown list item" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    cat > AGENTS.md <<'EOF'
# Build Configuration

- JOB_NAME=testjob
- OTHER_VAR=value
EOF
    git remote add origin "git@github.com:org/other-repo.git"

    run discover_job_name
    assert_success
    assert_output "testjob"
}

@test "discover_job_name: AGENTS.md with embedded JOB_NAME in text" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    cat > AGENTS.md <<'EOF'
# Jenkins Configuration

The Jenkins job is JOB_NAME=testjob for this project.
EOF
    git remote add origin "git@github.com:org/other-repo.git"

    run discover_job_name
    assert_success
    assert_output "testjob"
}

@test "discover_job_name: AGENTS.md takes priority over git origin" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    echo "JOB_NAME=agents-job" > AGENTS.md
    git remote add origin "git@github.com:org/origin-job.git"

    run discover_job_name
    assert_success
    assert_output "agents-job"
}

# -----------------------------------------------------------------------------
# Git origin-based discovery
# -----------------------------------------------------------------------------

@test "discover_job_name: git origin GitHub SSH format" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    git remote add origin "git@github.com:org/my-project.git"

    run discover_job_name
    assert_success
    assert_output "my-project"
}

@test "discover_job_name: git origin HTTPS format" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    git remote add origin "https://github.com/org/my-project.git"

    run discover_job_name
    assert_success
    assert_output "my-project"
}

@test "discover_job_name: git origin SSH with port" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    git remote add origin "ssh://git@server:2233/home/git/ralph1.git"

    run discover_job_name
    assert_success
    assert_output "ralph1"
}

@test "discover_job_name: git origin simple SSH format" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    git remote add origin "git@server:path/to/repo.git"

    run discover_job_name
    assert_success
    assert_output "repo"
}

@test "discover_job_name: git origin without .git suffix" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    git remote add origin "https://github.com/org/my-project"

    run discover_job_name
    assert_success
    assert_output "my-project"
}

# -----------------------------------------------------------------------------
# Failure case
# -----------------------------------------------------------------------------

@test "discover_job_name: no AGENTS.md and no origin returns error" {
    local repo_dir
    repo_dir=$(create_mock_git_repo)
    cd "${repo_dir}"

    run discover_job_name
    assert_failure
}
