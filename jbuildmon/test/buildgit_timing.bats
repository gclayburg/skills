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
            cat "${FIXTURE_DIR}/timing_wfapi_\${TIMING_FIXTURE_SET:-parallel}_42.json"
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
    assert_output --partial "Build #40 - total 3m 20s"
    assert_output --partial "Build #41 - total 4m 10s"
    assert_output --partial "Build #42 - total 5m 30s"
}

@test "timing_no_test_report" {
    create_timing_wrapper

    run bash -c "TIMING_TEST_REPORT_MODE=missing \"${TEST_TEMP_DIR}/timing_wrapper.sh\" 42 --tests 3>&- 2>&1"

    assert_success
    refute_output --partial "Test suite timing (top 10 slowest):"
}
