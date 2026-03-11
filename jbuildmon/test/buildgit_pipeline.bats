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
            cat "${FIXTURE_DIR}/timing_wfapi_\${PIPELINE_FIXTURE_SET:-parallel}_42.json"
            ;;
        "/blue/rest/organizations/jenkins/pipelines/ralph1/runs/42/nodes/")
            if [[ "\${PIPELINE_BLUE_MODE:-ok}" == "missing" ]]; then
                echo "[]"
            else
                cat "${FIXTURE_DIR}/timing_blue_nodes_\${PIPELINE_FIXTURE_SET:-parallel}_42.json"
            fi
            ;;
        "/computer/api/json?tree=computer[displayName,assignedLabels[name]]")
            cat "${FIXTURE_DIR}/agents_computers.json"
            ;;
        "/job/ralph1/42/consoleText")
            cat "${FIXTURE_DIR}/timing_console_42.txt"
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
