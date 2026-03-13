#!/usr/bin/env bats

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    FIXTURES_DIR="${TEST_DIR}/fixtures"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
    export NO_COLOR=1

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
}

_mock_stage_corr_test_api() {
    jenkins_api_with_status() {
        case "$1" in
            "/job/test-job/42/testReport/api/json?tree=suites[name,duration,enclosingBlockNames,cases[status]]")
                cat "${FIXTURES_DIR}/stage_test_corr_test_report_42.json"
                printf '\n200\n'
                ;;
            "/job/test-job/43/testReport/api/json?tree=suites[name,duration,enclosingBlockNames,cases[status]]")
                printf '\n404\n'
                ;;
            *)
                echo "unexpected endpoint: $1" >&2
                return 1
                ;;
        esac
    }
}

@test "fetch_stage_test_suites_returns_map_keyed_by_stage_name" {
    _mock_stage_corr_test_api

    run fetch_stage_test_suites "test-job" "42"

    assert_success
    echo "$output" | jq -e 'keys == ["Unit Tests A", "Unit Tests B"]' >/dev/null
}

@test "fetch_stage_test_suites_correct_suite_fields" {
    _mock_stage_corr_test_api

    run fetch_stage_test_suites "test-job" "42"

    assert_success
    echo "$output" | jq -e '
        .["Unit Tests A"][0] == {
            "name": "buildgit_status_follow",
            "tests": 3,
            "durationMs": 122300,
            "failures": 2
        }
    ' >/dev/null
}

@test "fetch_stage_test_suites_stage_with_no_tests_omitted" {
    _mock_stage_corr_test_api

    run fetch_stage_test_suites "test-job" "42"

    assert_success
    echo "$output" | jq -e 'has("Lint") | not' >/dev/null
}

@test "fetch_stage_test_suites_empty_build_returns_empty_map" {
    _mock_stage_corr_test_api

    run fetch_stage_test_suites "test-job" "43"

    assert_success
    assert_output "{}"
}
