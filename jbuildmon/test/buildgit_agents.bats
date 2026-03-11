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

create_agents_wrapper() {
    cat > "${TEST_TEMP_DIR}/agents_wrapper.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

VERBOSE_MODE=false

source "${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh"

verify_jenkins_connection() {
    return 0
}

jenkins_api() {
    local endpoint="\$1"

    case "\$endpoint" in
        "/computer/api/json?tree=computer[displayName,assignedLabels[name],numExecutors,idle,offline,temporarilyOffline,executors[currentExecutable[url]]]")
            cat "${FIXTURE_DIR}/\${AGENTS_COMPUTERS_FIXTURE:-agents_computers.json}"
            ;;
        "/label/fastnode/api/json")
            cat "${FIXTURE_DIR}/agents_label_fastnode.json"
            ;;
        "/label/linux/api/json")
            cat "${FIXTURE_DIR}/agents_label_linux.json"
            ;;
        "/label/slownode/api/json")
            cat "${FIXTURE_DIR}/agents_label_slownode.json"
            ;;
        "/label/solo/api/json")
            cat "${FIXTURE_DIR}/agents_label_solo.json"
            ;;
        *)
            echo "unexpected endpoint: \$endpoint" >&2
            return 1
            ;;
    esac
}

cmd_agents "\$@"
EOF

    chmod +x "${TEST_TEMP_DIR}/agents_wrapper.sh"
}

@test "agents_human_readable_basic" {
    create_agents_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/agents_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output --partial "Label: fastnode"
    assert_output --partial "  Nodes: 2"
    assert_output --partial "  Executors: 3 total, 1 busy, 2 idle"
    assert_output --partial "Label: slownode"
    assert_output --partial "slownode-1"
}

@test "agents_json_output" {
    create_agents_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/agents_wrapper.sh\" --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.labels | length == 3' >/dev/null
    echo "$output" | jq -e '.totalExecutors == 6 and .totalBusy == 2 and .totalIdle == 4' >/dev/null
    echo "$output" | jq -e '.labels[0] | has("totalExecutors") and has("busyExecutors") and has("idleExecutors")' >/dev/null
}

@test "agents_label_filter" {
    create_agents_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/agents_wrapper.sh\" --label fastnode 3>&- 2>&1"

    assert_success
    assert_output --partial "Label: fastnode"
    refute_output --partial "Label: linux"
    refute_output --partial "Label: slownode"
}

@test "agents_verbose_shows_job_urls" {
    create_agents_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/agents_wrapper.sh\" -v 3>&- 2>&1"

    assert_success
    assert_output --partial "Job: http://jenkins.example.com/job/ralph1/101/"
    assert_output --partial "Job: http://jenkins.example.com/job/ralph1/103/"
}

@test "agents_offline_node_shown" {
    create_agents_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/agents_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output --partial "fastnode-2"
    assert_output --partial "offline"
}

@test "agents_empty_cluster" {
    create_agents_wrapper

    run bash -c "AGENTS_COMPUTERS_FIXTURE=agents_computers_empty.json \"${TEST_TEMP_DIR}/agents_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output "No nodes found"
}

@test "agents_single_executor" {
    create_agents_wrapper

    run bash -c "AGENTS_COMPUTERS_FIXTURE=agents_computers_single.json \"${TEST_TEMP_DIR}/agents_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output --partial "1 executor"
    refute_output --partial "1 executors"
}
