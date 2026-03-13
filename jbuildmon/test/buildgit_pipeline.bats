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

create_pipeline_wrapper() {
    cat > "${TEST_TEMP_DIR}/pipeline_wrapper.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

VERBOSE_MODE=false
JOB_NAME="ralph1"

source "${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/job_helpers.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh"

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

_build_stage_agent_map() {
    case "\${PIPELINE_AGENT_MODE:-default}" in
        unknown)
            echo '{"Checkout":"fastnode-1","Unit Tests":"fastnode-1","Integration Tests":"slownode-1","Package":"mystery-7","Build":"fastnode-1"}'
            ;;
        *)
            echo '{"Checkout":"fastnode-1","Unit Tests":"fastnode-1","Integration Tests":"slownode-1","Package":"fastnode-2","Build":"fastnode-1"}'
            ;;
    esac
}

jenkins_api() {
    local endpoint="\$1"

    case "\$endpoint" in
        "/job/ralph1/api/json")
            echo '{"lastBuild":{"number":42}}'
            ;;
        "/job/ralph1/42/wfapi/describe")
            if [[ "\${PIPELINE_FIXTURE_SET:-parallel}" == "pipeline" || "\${PIPELINE_FIXTURE_SET:-parallel}" == "parallel_stages" ]]; then
                cat "${FIXTURE_DIR}/pipeline_wfapi_42.json"
            else
                cat "${FIXTURE_DIR}/timing_wfapi_\${PIPELINE_FIXTURE_SET:-parallel}_42.json"
            fi
            ;;
        "/blue/rest/organizations/jenkins/pipelines/ralph1/runs/42/nodes/")
            if [[ "\${PIPELINE_BLUE_MODE:-ok}" == "missing" ]]; then
                echo "[]"
            elif [[ "\${PIPELINE_FIXTURE_SET:-parallel}" == "pipeline" ]]; then
                cat "${FIXTURE_DIR}/pipeline_blue_nodes_42.json"
            elif [[ "\${PIPELINE_FIXTURE_SET:-parallel}" == "parallel_stages" ]]; then
                cat "${FIXTURE_DIR}/pipeline_blue_nodes_parallel_stages_42.json"
            else
                cat "${FIXTURE_DIR}/timing_blue_nodes_\${PIPELINE_FIXTURE_SET:-parallel}_42.json"
            fi
            ;;
        "/computer/api/json?tree=computer[displayName,assignedLabels[name]]")
            cat "${FIXTURE_DIR}/agents_computers.json"
            ;;
        "/job/ralph1/42/consoleText")
            if [[ "\${PIPELINE_FIXTURE_SET:-parallel}" == "pipeline" ]]; then
                cat "${FIXTURE_DIR}/pipeline_console_42.txt"
            else
                cat "${FIXTURE_DIR}/timing_console_42.txt"
            fi
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
        "/job/ralph1/42/testReport/api/json?tree=suites[name,duration,enclosingBlockNames,cases[status]]")
            if [[ "\${PIPELINE_FIXTURE_SET:-parallel}" == "pipeline" || "\${PIPELINE_FIXTURE_SET:-parallel}" == "parallel_stages" ]]; then
                cat "${FIXTURE_DIR}/pipeline_test_report_42.json"
                printf '\n200\n'
            else
                printf '\n404\n'
            fi
            ;;
        *)
            echo "unexpected endpoint: \$endpoint" >&2
            return 1
            ;;
    esac
}

cmd_pipeline "\$@"
EOF

    chmod +x "${TEST_TEMP_DIR}/pipeline_wrapper.sh"
}

@test "pipeline_sequential_only" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=sequential \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    refute_output --partial "parallel fork"
    assert_output --partial "Checkout [fastnode] -- sequential"
    assert_output --partial "Build [fastnode] -- sequential"
}

@test "pipeline_parallel_branch" {
    create_pipeline_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Tests -- parallel fork (2 branches)"
    assert_output --partial "Unit Tests [fastnode] -- sequential"
    assert_output --partial "Integration Tests [slownode] -- sequential"
}

@test "pipeline_agent_label" {
    create_pipeline_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Unit Tests [fastnode] -- sequential"
}

@test "pipeline_json_structure" {
    create_pipeline_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e 'has("stages") and has("graph") and (.graph | has("edges"))' >/dev/null
}

@test "pipeline_json_parallel_type" {
    create_pipeline_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.. | objects | select(.name? == "Tests") | .type == "parallel" and (.branches | length == 2)' >/dev/null
}

@test "pipeline_json_sequential_type" {
    create_pipeline_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.. | objects | select(.name? == "Checkout") | .type == "sequential"' >/dev/null
}

@test "pipeline_unknown_agent_label" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_AGENT_MODE=unknown \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Package [mystery-7] -- sequential"
}

@test "pipeline_human_matches_json" {
    create_pipeline_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"
    assert_success
    local human_count
    human_count=$(printf '%s\n' "$output" | sed -n 's/.*parallel fork (\([0-9][0-9]*\) branches).*/\1/p' | head -1)

    run bash -c "\"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"
    assert_success
    local json_count
    json_count=$(printf '%s\n' "$output" | jq -r '.. | objects | select(.name? == "Tests") | (.branches | length)')

    [[ "$human_count" == "$json_count" ]]
}

@test "pipeline_human_shows_test_summary_for_stages_with_tests" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=pipeline \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "Unit Tests [fastnode] -- sequential"
    assert_output --partial "2 suites, 5 tests, 2m 6s cumulative"
    assert_output --partial "Integration Tests [slownode] -- sequential"
    assert_output --partial "3 suites, 9 tests, 2m 48s cumulative"
}

@test "pipeline_human_omits_test_summary_for_stages_without_tests" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=pipeline \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    refute_output --partial "0 suites"
    [[ "$(printf '%s\n' "$output" | grep -c 'suites, .* tests, .* cumulative')" -eq 2 ]]
}

@test "pipeline_json_includes_testSuites_field" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=pipeline \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.. | objects | select(.name? == "Unit Tests") | has("testSuites")' >/dev/null
}

@test "pipeline_json_testSuites_fields_correct" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=pipeline \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '
        .. | objects
        | select(.name? == "Integration Tests")
        | .testSuites[0] == {
            "name": "buildgit_timing",
            "tests": 4,
            "durationMs": 79200,
            "failures": 0
        }
    ' >/dev/null
}

@test "pipeline_json_testSuites_omitted_when_no_tests" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=pipeline \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '
        .. | objects
        | select(.name? == "Checkout" or .name? == "Package")
        | has("testSuites") | not
    ' >/dev/null
}

@test "pipeline_json_testSuites_has_failures_count" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=pipeline \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '
        .. | objects
        | select(.name? == "Unit Tests")
        | .testSuites[0].failures == 2
    ' >/dev/null
}

@test "pipeline_human_cumulative_duration_correct" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=pipeline \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "2 suites, 5 tests, 2m 6s cumulative"
    assert_output --partial "3 suites, 9 tests, 2m 48s cumulative"
}

@test "pipeline_enrich_no_test_data_returns_unchanged" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=parallel PIPELINE_BLUE_MODE=missing \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '
        .. | objects
        | select(.name? == "Checkout" or .name? == "Unit Tests" or .name? == "Integration Tests" or .name? == "Package")
        | has("testSuites") | not
    ' >/dev/null
}

@test "pipeline_json_testSuites_on_parallel_type_nodes" {
    create_pipeline_wrapper

    # parallel_stages fixture: Unit Tests and Integration Tests are type PARALLEL (real Jenkins behavior)
    run bash -c "PIPELINE_FIXTURE_SET=parallel_stages \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '
        .. | objects
        | select(.name? == "Unit Tests" and .type? == "parallel")
        | has("testSuites")
    ' >/dev/null
    echo "$output" | jq -e '
        .. | objects
        | select(.name? == "Integration Tests" and .type? == "parallel")
        | has("testSuites")
    ' >/dev/null
}

@test "pipeline_human_parallel_type_test_node_shows_suite_info" {
    create_pipeline_wrapper

    run bash -c "PIPELINE_FIXTURE_SET=parallel_stages \"${TEST_TEMP_DIR}/pipeline_wrapper.sh\" 42 3>&- 2>&1"

    assert_success
    assert_output --partial "suites"
    refute_output --partial "parallel fork (0 branches)"
}
