#!/usr/bin/env bats

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
    FIXTURE_DIR="${PROJECT_DIR}/test/fixtures"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
    export NO_COLOR=1
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

create_timing_wrapper() {
    apply_fixture="${1:-parallel}"

    cat > "${TEST_TEMP_DIR}/timing_wrapper.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

VERBOSE_MODE=false
JOB_NAME="ralph1"

source "${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/job_helpers.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh"

show_usage() {
    echo "usage"
}

verify_jenkins_connection() {
    return 0
}

verify_job_exists() {
    return 0
}

_resolve_effective_job_name() {
    echo "\$1"
}

discover_job_name() {
    echo "ralph1"
}

jenkins_api() {
    local endpoint="\$1"

    case "\$endpoint" in
        "/api/json")
            echo '{"_class":"hudson.model.Hudson"}'
            ;;
        "/job/ralph1/api/json")
            echo '{"lastBuild":{"number":42}}'
            ;;
        "/job/ralph1/lastSuccessfulBuild/buildNumber")
            echo "42"
            ;;
        "/job/ralph1/42/api/json")
            cat "${FIXTURE_DIR}/timing_build_info_42.json"
            ;;
        "/job/ralph1/41/api/json")
            cat "${FIXTURE_DIR}/timing_build_info_41.json"
            ;;
        "/job/ralph1/40/api/json")
            cat "${FIXTURE_DIR}/timing_build_info_40.json"
            ;;
        "/job/ralph1/42/wfapi/describe")
            if [[ "\${TIMING_WFAPI_SET:-\${TIMING_FIXTURE_SET:-parallel}}" == "stage_tests" ]]; then
                cat "${FIXTURE_DIR}/timing_stage_tests_wfapi_42.json"
            else
                cat "${FIXTURE_DIR}/timing_wfapi_\${TIMING_WFAPI_SET:-\${TIMING_FIXTURE_SET:-parallel}}_42.json"
            fi
            ;;
        "/job/ralph1/41/wfapi/describe")
            cat "${FIXTURE_DIR}/timing_wfapi_sequential_41.json"
            ;;
        "/job/ralph1/40/wfapi/describe")
            cat "${FIXTURE_DIR}/timing_wfapi_sequential_40.json"
            ;;
        "/blue/rest/organizations/jenkins/pipelines/ralph1/runs/42/nodes/")
            cat "${FIXTURE_DIR}/timing_blue_nodes_\${TIMING_FIXTURE_SET:-parallel}_42.json"
            ;;
        "/blue/rest/organizations/jenkins/pipelines/ralph1/runs/41/nodes/")
            cat "${FIXTURE_DIR}/timing_blue_nodes_sequential_41.json"
            ;;
        "/blue/rest/organizations/jenkins/pipelines/ralph1/runs/40/nodes/")
            cat "${FIXTURE_DIR}/timing_blue_nodes_sequential_40.json"
            ;;
        "/job/ralph1/42/consoleText")
            cat "${FIXTURE_DIR}/timing_console_42.txt"
            ;;
        "/job/ralph1/41/consoleText")
            cat "${FIXTURE_DIR}/timing_console_41.txt"
            ;;
        "/job/ralph1/40/consoleText")
            cat "${FIXTURE_DIR}/timing_console_40.txt"
            ;;
        *)
            echo "unexpected endpoint: \$endpoint" >&2
            return 1
            ;;
    esac
}

jenkins_api_with_status() {
    local endpoint="\$1"

    case "\$endpoint" in
        "/api/json")
            printf '{"_class":"hudson.model.Hudson"}\n200\n'
            ;;
        "/job/ralph1/42/testReport/api/json?tree=duration,suites[name,duration,cases[className,name,duration,status]]")
            if [[ "\${TIMING_TEST_REPORT_MODE:-ok}" == "missing" ]]; then
                printf '\n404\n'
            else
                cat "${FIXTURE_DIR}/timing_test_report_42.json"
                printf '\n200\n'
            fi
            ;;
        "/job/ralph1/41/testReport/api/json?tree=duration,suites[name,duration,cases[className,name,duration,status]]")
            cat "${FIXTURE_DIR}/timing_test_report_41.json"
            printf '\n200\n'
            ;;
        "/job/ralph1/40/testReport/api/json?tree=duration,suites[name,duration,cases[className,name,duration,status]]")
            cat "${FIXTURE_DIR}/timing_test_report_40.json"
            printf '\n200\n'
            ;;
        "/job/ralph1/42/execution/node/10/wfapi/testResults")
            cat "${FIXTURE_DIR}/timing_stage_tests_node_10_tests.json"
            printf '\n200\n'
            ;;
        "/job/ralph1/42/execution/node/11/wfapi/testResults")
            cat "${FIXTURE_DIR}/timing_stage_tests_node_11_tests.json"
            printf '\n200\n'
            ;;
        "/job/ralph1/42/execution/node/1/wfapi/testResults"|"/job/ralph1/42/execution/node/4/wfapi/testResults")
            printf '\n404\n'
            ;;
        *)
            echo "unexpected endpoint: \$endpoint" >&2
            return 1
            ;;
    esac
}

cmd_timing "\$@"
EOF

    chmod +x "${TEST_TEMP_DIR}/timing_wrapper.sh"
}

@test "timing_sequential_stages" {
    create_timing_wrapper

    run bash -c "TIMING_FIXTURE_SET=sequential \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Sequential stages:"
    refute_output --partial "Parallel group:"
}

@test "timing_parallel_group_bottleneck" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Parallel group: Tests (wall 2m 0s, bottleneck: Integration Tests)"
    assert_output --partial "Integration Tests  2m 0s  agent-b  <- slowest"
}

@test "timing_total_duration" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Build #42 - total 5m 30s"
}

@test "timing_tests_flag" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests 3>&- 2>&1"

    assert_success
    assert_output --partial "Test suite timing (top 10 slowest):"

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    refute_output --partial "Test suite timing (top 10 slowest):"
}

@test "timing_tests_sorted" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests 3>&- 2>&1"

    assert_success
    local integration_line unit_line
    integration_line=$(printf '%s\n' "$output" | grep -n "IntegrationSuite" | cut -d: -f1)
    unit_line=$(printf '%s\n' "$output" | grep -n "UnitSuite" | cut -d: -f1)
    [[ -n "$integration_line" ]]
    [[ -n "$unit_line" ]]
    [[ "$integration_line" -lt "$unit_line" ]]
}

@test "timing_json_structure" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e 'has("stages") and has("parallelGroups") and has("testSuites")' >/dev/null
}

@test "timing_json_bottleneck" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.parallelGroups[0].bottleneck == "Integration Tests"' >/dev/null
}

@test "timing_last_successful_default" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output --partial "Build #42 - total 5m 30s"
}

@test "timing_n_builds" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" -n 3 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Build    Total"
    assert_output --partial "#40"
    assert_output --partial "#41"
    assert_output --partial "#42"
    refute_output --partial "Build #40 - total"
}

@test "timing_no_test_report" {
    create_timing_wrapper

    run bash -c "TIMING_TEST_REPORT_MODE=missing \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests 3>&- 2>&1"

    assert_success
    refute_output --partial "Test suite timing (top 10 slowest):"
}

@test "timing_by_stage_groups_suites_under_stage" {
    create_timing_wrapper

    run bash -c "TIMING_WFAPI_SET=stage_tests \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests --by-stage 3>&- 2>&1"

    assert_success
    assert_output --partial "Test suite timing by stage:"
    assert_output --partial "  Unit Tests (wall 1m 0s, agent-a):"
    assert_output --partial "    com.example.unit.LoginSpec"
    assert_output --partial "  Integration Tests (wall 2m 0s, agent-b):"
}

@test "timing_by_stage_shows_stage_wall_time_and_agent" {
    create_timing_wrapper

    run bash -c "TIMING_WFAPI_SET=stage_tests \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests --by-stage 3>&- 2>&1"

    assert_success
    assert_output --partial "Unit Tests (wall 1m 0s, agent-a):"
    assert_output --partial "Integration Tests (wall 2m 0s, agent-b):"
}

@test "timing_by_stage_suite_line_has_duration_and_count" {
    create_timing_wrapper

    run bash -c "TIMING_WFAPI_SET=stage_tests \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests --by-stage 3>&- 2>&1"

    assert_success
    assert_output --partial "com.example.integration.ApiTimingIT  3m 29s  (50 tests)"
}

@test "timing_by_stage_without_tests_flag_ignored" {
    create_timing_wrapper

    run bash -c "TIMING_WFAPI_SET=stage_tests \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --by-stage 3>&- 2>&1"

    assert_success
    assert_output --partial "Parallel group: Tests (wall 2m 0s, bottleneck: Integration Tests)"
    refute_output --partial "Test suite timing by stage:"
}

@test "timing_by_stage_json_has_testsByStage_field" {
    create_timing_wrapper

    run bash -c "TIMING_WFAPI_SET=stage_tests \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests --by-stage --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.testsByStage["Unit Tests"][0].name == "com.example.unit.LoginSpec"' >/dev/null
    echo "$output" | jq -e '.testsByStage["Integration Tests"][0].tests == 50' >/dev/null
}

@test "timing_by_stage_stage_with_no_tests_omitted" {
    create_timing_wrapper

    run bash -c "TIMING_WFAPI_SET=stage_tests \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests --by-stage --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '(.testsByStage | has("Package")) | not' >/dev/null
    refute_output --partial "Package (wall"
}

@test "timing_by_stage_framework_agnostic" {
    create_timing_wrapper

    run bash -c "TIMING_WFAPI_SET=stage_tests \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests --by-stage 3>&- 2>&1"

    assert_success
    assert_output --partial "pytest/test_api.py::test_round_trip"
    refute_output --partial ".bats"
}

@test "timing_compare_shows_both_build_numbers" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" --compare 40 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Timing comparison: Build #40 vs #42"
}

@test "timing_compare_shows_delta_column" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" --compare 40 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Delta"
    assert_output --partial "+2m 10s"
}

@test "timing_compare_zero_delta_shown_as_0s" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" --compare 41 41 3>&- 2>&1"

    assert_success
    assert_output --partial "0s"
}

@test "timing_compare_negative_delta_has_minus" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" --compare 42 40 3>&- 2>&1"

    assert_success
    assert_output --partial "-2m 10s"
}

@test "timing_compare_positive_delta_has_plus" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" --compare 40 42 3>&- 2>&1"

    assert_success
    assert_output --partial "+10s"
}

@test "timing_compare_json_has_builds_and_deltas" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" --compare 40 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.builds | length == 2' >/dev/null
    echo "$output" | jq -e '.deltas.total == 130000' >/dev/null
    echo "$output" | jq -e '.deltas.stages["Checkout"] == 10000' >/dev/null
}

@test "timing_n_without_tests_renders_table" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" -n 3 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Build    Total"
    assert_output --partial "Checkout"
    assert_output --partial "Build"
    assert_output --partial "Tests"
    refute_output --partial "Build #42 - total"
}

@test "timing_n_with_tests_prepends_table" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" -n 3 42 --tests 3>&- 2>&1"

    assert_success
    local table_line detail_line
    table_line=$(printf '%s\n' "$output" | grep -n "^Build    Total" | cut -d: -f1)
    detail_line=$(printf '%s\n' "$output" | grep -n "^Build #42 - total 5m 30s" | cut -d: -f1)
    [[ -n "$table_line" ]]
    [[ -n "$detail_line" ]]
    [[ "$table_line" -lt "$detail_line" ]]
    refute_output --partial "Build #40 - total"
    refute_output --partial "Build #41 - total"
}

@test "timing_compare_missing_stage_in_one_build" {
    create_timing_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/timing_wrapper.sh\" --compare 40 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Build                    1m 40s"
    assert_output --partial "Tests"
    assert_output --partial "+2m 0s"
}
