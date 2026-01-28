#!/usr/bin/env bats

# Tests for test_helper.bash
# Spec: install-bats-core-spec.md, Section: Test Helper Configuration

load 'test_helper'

@test "test_helper creates TEST_TEMP_DIR in setup" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    # Verify that setup() creates a temporary directory
    assert [ -n "${TEST_TEMP_DIR}" ]
    assert_dir_exists "${TEST_TEMP_DIR}"
}

@test "test_helper preserves environment variables" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    # Verify original environment variables are captured
    # Set test values and verify they are preserved through setup
    export JENKINS_URL="http://test.jenkins.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    # Re-run setup to capture current values
    setup

    # Verify ORIG variables captured the values
    assert [ "${ORIG_JENKINS_URL}" = "http://test.jenkins.com" ]
    assert [ "${ORIG_JENKINS_USER_ID}" = "testuser" ]
    assert [ "${ORIG_JENKINS_API_TOKEN}" = "testtoken" ]
}

@test "create_mock_git_repo creates a valid git repository" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    local repo_path
    repo_path="$(create_mock_git_repo)"

    assert_dir_exists "${repo_path}"
    assert_dir_exists "${repo_path}/.git"
    assert_file_exists "${repo_path}/README.md"

    # Verify it has at least one commit
    cd "${repo_path}"
    run git log --oneline -1
    assert_success
    assert_output --partial "Initial commit"
}

@test "create_mock_git_repo accepts custom directory" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    local custom_dir="${TEST_TEMP_DIR}/custom_repo"
    local repo_path
    repo_path="$(create_mock_git_repo "${custom_dir}")"

    assert [ "${repo_path}" = "${custom_dir}" ]
    assert_dir_exists "${custom_dir}/.git"
}

@test "create_mock_agents_md creates AGENTS.md with JOB_NAME" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    local repo_path
    repo_path="$(create_mock_git_repo)"

    create_mock_agents_md "test-job-name" "${repo_path}"

    assert_file_exists "${repo_path}/AGENTS.md"
    run cat "${repo_path}/AGENTS.md"
    assert_success
    assert_output --partial "JOB_NAME=test-job-name"
}

@test "TEST_TEMP_DIR is unique per test run" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    # Verify the temp dir path contains temp directory pattern
    assert [[ "${TEST_TEMP_DIR}" == /tmp/* ]] || [[ "${TEST_TEMP_DIR}" == /var/folders/* ]]
}

@test "PROJECT_DIR points to jbuildmon directory" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    assert [ -n "${PROJECT_DIR}" ]
    assert_dir_exists "${PROJECT_DIR}"
    # PROJECT_DIR should be the parent of the test directory
    assert [ "$(basename "${PROJECT_DIR}")" = "jbuildmon" ]
}

@test "TEST_DIR points to test directory" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    assert [ -n "${TEST_DIR}" ]
    assert_dir_exists "${TEST_DIR}"
    assert [ "$(basename "${TEST_DIR}")" = "test" ]
}
