#!/usr/bin/env bats

# Unit tests for get_all_stages function
# Spec reference: full-stage-print-spec.md, Section: API Data Source
# Plan reference: full-stage-print-plan.md, Chunk B

load test_helper

# Load the jenkins-common.sh library containing get_all_stages
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
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# -----------------------------------------------------------------------------
# Test Case: Returns stages array with all fields
# Spec: full-stage-print-spec.md, Section: API Data Source
# -----------------------------------------------------------------------------
@test "get_all_stages_success" {
    # Mock jenkins_api to return fixture data
    jenkins_api() {
        cat "${FIXTURES_DIR}/wfapi_describe_response.json"
    }

    local output
    output=$(get_all_stages "test-job" "42")
    local status=$?

    # Verify success
    [[ $status -eq 0 ]]

    # Verify we got a JSON array with 4 stages
    [[ $(echo "$output" | jq 'length') -eq 4 ]]

    # Verify first stage has all required fields
    [[ $(echo "$output" | jq -r '.[0].name') == "Initialize Submodules" ]]
    [[ $(echo "$output" | jq -r '.[0].status') == "SUCCESS" ]]
    [[ $(echo "$output" | jq -r '.[0].startTimeMillis') == "1706889863000" ]]
    [[ $(echo "$output" | jq -r '.[0].durationMillis') == "10000" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Returns empty array when no stages
# Spec: full-stage-print-spec.md, Section: API Data Source
# -----------------------------------------------------------------------------
@test "get_all_stages_empty" {
    # Mock jenkins_api to return empty stages response
    jenkins_api() {
        cat "${FIXTURES_DIR}/wfapi_describe_empty.json"
    }

    local output
    output=$(get_all_stages "test-job" "1")

    [[ "$output" == "[]" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Returns empty array on API error
# Spec: full-stage-print-spec.md, Section: API Data Source
# -----------------------------------------------------------------------------
@test "get_all_stages_api_failure" {
    # Mock jenkins_api to return nothing (simulating API failure)
    jenkins_api() {
        return 1
    }

    local output
    output=$(get_all_stages "test-job" "99")

    [[ "$output" == "[]" ]]
}

@test "get_all_stages_api_returns_empty" {
    # Mock jenkins_api to return empty string
    jenkins_api() {
        echo ""
    }

    local output
    output=$(get_all_stages "test-job" "99")

    [[ "$output" == "[]" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Handles stages with missing optional fields
# Spec: full-stage-print-spec.md, Section: API Data Source
# -----------------------------------------------------------------------------
@test "get_all_stages_missing_fields" {
    # Mock jenkins_api to return response with missing fields
    jenkins_api() {
        cat "${FIXTURES_DIR}/wfapi_describe_missing_fields.json"
    }

    local output
    output=$(get_all_stages "test-job" "5")

    # Verify we got a JSON array with 3 stages
    [[ $(echo "$output" | jq 'length') -eq 3 ]]

    # First stage: only has name, should default other fields
    [[ $(echo "$output" | jq -r '.[0].name') == "Build" ]]
    [[ $(echo "$output" | jq -r '.[0].status') == "NOT_EXECUTED" ]]
    [[ $(echo "$output" | jq -r '.[0].startTimeMillis') == "0" ]]
    [[ $(echo "$output" | jq -r '.[0].durationMillis') == "0" ]]

    # Second stage: missing name, should default to "unknown"
    [[ $(echo "$output" | jq -r '.[1].name') == "unknown" ]]
    [[ $(echo "$output" | jq -r '.[1].status') == "SUCCESS" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Correctly extracts all status types
# Spec: full-stage-print-spec.md, Section: API Data Source
# -----------------------------------------------------------------------------
@test "get_all_stages_various_statuses" {
    # Mock jenkins_api to return response with various statuses
    jenkins_api() {
        cat "${FIXTURES_DIR}/wfapi_describe_various_statuses.json"
    }

    local output
    output=$(get_all_stages "test-job" "10")

    # Verify we got a JSON array with 6 stages
    [[ $(echo "$output" | jq 'length') -eq 6 ]]

    # Check each status type is correctly extracted
    [[ $(echo "$output" | jq -r '.[0].status') == "SUCCESS" ]]
    [[ $(echo "$output" | jq -r '.[1].status') == "SUCCESS" ]]
    [[ $(echo "$output" | jq -r '.[2].status') == "FAILED" ]]
    [[ $(echo "$output" | jq -r '.[3].status') == "NOT_EXECUTED" ]]
    [[ $(echo "$output" | jq -r '.[4].status') == "ABORTED" ]]
    [[ $(echo "$output" | jq -r '.[5].status') == "UNSTABLE" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Handles invalid JSON response gracefully
# Spec: full-stage-print-spec.md, Section: API Data Source
# -----------------------------------------------------------------------------
@test "get_all_stages_invalid_json" {
    # Mock jenkins_api to return invalid JSON
    jenkins_api() {
        echo "Not valid JSON"
    }

    local output
    output=$(get_all_stages "test-job" "99")

    [[ "$output" == "[]" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Handles response without stages field
# Spec: full-stage-print-spec.md, Section: API Data Source
# -----------------------------------------------------------------------------
@test "get_all_stages_no_stages_field" {
    # Mock jenkins_api to return JSON without stages field
    jenkins_api() {
        echo '{"name": "#1", "status": "SUCCESS"}'
    }

    local output
    output=$(get_all_stages "test-job" "1")

    [[ "$output" == "[]" ]]
}
