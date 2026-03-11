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
    export QUEUE_NOW_MS=1700000000000
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

create_queue_wrapper() {
    cat > "${TEST_TEMP_DIR}/queue_wrapper.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

VERBOSE_MODE=false

source "${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/cmd_queue.sh"

show_usage() {
    echo "usage"
}

verify_jenkins_connection() {
    return 0
}

jenkins_api() {
    local endpoint="\$1"

    case "\$endpoint" in
        "/queue/api/json?tree=items[id,stuck,blocked,buildable,why,inQueueSince,task[name,url]]")
            cat "${FIXTURE_DIR}/\${QUEUE_FIXTURE:-queue_items_single.json}"
            ;;
        *)
            echo "unexpected endpoint: \$endpoint" >&2
            return 1
            ;;
    esac
}

cmd_queue "\$@"
EOF

    chmod +x "${TEST_TEMP_DIR}/queue_wrapper.sh"
}

@test "queue_empty" {
    create_queue_wrapper

    run bash -c "QUEUE_FIXTURE=queue_items_empty.json \"${TEST_TEMP_DIR}/queue_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output "Queue: empty"
}

@test "queue_one_item_human" {
    create_queue_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/queue_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output --partial "Queue: 1 item"
    assert_output --partial "ralph1/main (45s ago)"
    assert_output --partial "Waiting for next available executor"
}

@test "queue_multiple_items" {
    create_queue_wrapper

    run bash -c "QUEUE_FIXTURE=queue_items_multiple.json \"${TEST_TEMP_DIR}/queue_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output --partial "Queue: 2 items"
    assert_output --partial "ralph1/feature-x"
    assert_output --partial "ralph1/release"
}

@test "queue_json_output" {
    create_queue_wrapper

    run bash -c "\"${TEST_TEMP_DIR}/queue_wrapper.sh\" --json 3>&- 2>&1"

    assert_success
    echo "$output" | jq -e '.count == 1' >/dev/null
    echo "$output" | jq -e '.items[0] | has("id") and has("why") and has("queuedDuration") and has("task")' >/dev/null
    echo "$output" | jq -e '.items[0].queuedDuration == 45000' >/dev/null
}

@test "queue_verbose_stuck" {
    create_queue_wrapper

    run bash -c "QUEUE_FIXTURE=queue_items_stuck.json \"${TEST_TEMP_DIR}/queue_wrapper.sh\" -v 3>&- 2>&1"

    assert_success
    assert_output --partial "[STUCK] ralph1/stuck-job"
}

@test "queue_verbose_blocked" {
    create_queue_wrapper

    run bash -c "QUEUE_FIXTURE=queue_items_blocked.json \"${TEST_TEMP_DIR}/queue_wrapper.sh\" -v 3>&- 2>&1"

    assert_success
    assert_output --partial "[BLOCKED] ralph1/blocked-job"
}

@test "queue_quiet_period" {
    create_queue_wrapper

    run bash -c "QUEUE_FIXTURE=queue_items_quiet_period.json \"${TEST_TEMP_DIR}/queue_wrapper.sh\" 3>&- 2>&1"

    assert_success
    assert_output --partial "In the quiet period. Expires in 4 sec"
}
