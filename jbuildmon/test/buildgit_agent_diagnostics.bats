#!/usr/bin/env bats

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
    export NO_COLOR=1

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

_verbose_failure_fixture() {
    cat <<'JSON'
{
  "failCount": 1,
  "passCount": 5,
  "skipCount": 0,
  "suites": [
    {
      "name": "buildgit_status_follow.bats",
      "cases": [
        {
          "className": "buildgit_status_follow.bats",
          "name": "follow_completed_build_shows_console_url",
          "status": "FAILED",
          "duration": 0.545,
          "age": 1,
          "errorDetails": "assert_success failed with a deliberately long error body that should only stay intact in verbose mode",
          "errorStackTrace": "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7",
          "stdout": "[22:54:28] waiting\n[22:54:29] still waiting\nfull captured output line 3\nfull captured output line 4"
        }
      ]
    }
  ]
}
JSON
}

create_agent_diagnostics_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/buildgit_wrapper.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

_validate_jenkins_setup() {
    _VALIDATED_JOB_NAME="test-job"
    return 0
}

get_last_build_number() {
    echo "60"
}

get_build_info() {
    if [[ "${BUILDGIT_TEST_SCENARIO:-}" == "build_missing" ]]; then
        echo ""
        return 0
    fi
    echo '{"number":60,"result":"FAILURE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-job/60/"}'
}

get_console_output_raw() {
    printf 'started\nfailed fast\n'
}

get_all_stages() {
    cat <<'JSON'
[
  {"id":"1","name":"Build","status":"SUCCESS","startTimeMillis":1,"durationMillis":1000},
  {"id":"2","name":"Unit Tests A","status":"SUCCESS","startTimeMillis":2,"durationMillis":2000},
  {"id":"3","name":"Unit Tests B","status":"FAILED","startTimeMillis":3,"durationMillis":3000},
  {"id":"4","name":"Deploy","status":"NOT_EXECUTED","startTimeMillis":4,"durationMillis":0}
]
JSON
}

get_stage_console_output() {
    case "${BUILDGIT_TEST_SCENARIO:-}" in
        stage_console)
            printf 'not ok 1 - failing test\n# stage detail\n'
            return 0
            ;;
        stage_missing)
            _STAGE_CONSOLE_AVAILABLE_STAGES=$'Build\nUnit Tests A\nUnit Tests B\nDeploy'
            return 3
            ;;
        *)
            return 1
            ;;
    esac
}

cmd_status "$@"
WRAPPER

    chmod +x "${TEST_TEMP_DIR}/buildgit_wrapper.sh"
}

@test "status_verbose_shows_full_stack_trace" {
    VERBOSE_MODE=true

    run display_test_results "$(_verbose_failure_fixture)"

    assert_success
    assert_output --partial "line 7"
    assert_output --partial "Stdout:"
    assert_output --partial "full captured output line 4"
}

@test "status_verbose_json_includes_stdout" {
    VERBOSE_MODE=true

    run format_test_results_json "$(_verbose_failure_fixture)"

    assert_success
    echo "$output" | jq -e '.failed_tests[0].stdout | contains("full captured output line 4")' >/dev/null
}

@test "status_verbose_json_stdout_untruncated" {
    VERBOSE_MODE=true

    run format_test_results_json "$(_verbose_failure_fixture)"

    assert_success
    echo "$output" | jq -e '.failed_tests[0].error_stack_trace | contains("line 7")' >/dev/null
    echo "$output" | jq -e '.failed_tests[0].stdout | contains("line 4")' >/dev/null
}

@test "status_nonverbose_truncates_as_before" {
    VERBOSE_MODE=false

    run format_test_results_json "$(_verbose_failure_fixture)"

    assert_success
    echo "$output" | jq -e '.failed_tests[0] | has("stdout") | not' >/dev/null
    echo "$output" | jq -e '.failed_tests[0].error_stack_trace | contains("line 6") | not' >/dev/null
    echo "$output" | jq -e '.failed_tests[0].error_stack_trace | endswith("\n...")' >/dev/null
}

@test "status_console_text_outputs_raw" {
    export TEST_TEMP_DIR
    create_agent_diagnostics_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --console-text

    assert_success
    [[ "$output" == $'started\nfailed fast' ]] || fail "Expected raw console output, got: $output"
}

@test "status_console_text_specific_stage" {
    export TEST_TEMP_DIR
    export BUILDGIT_TEST_SCENARIO="stage_console"
    create_agent_diagnostics_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --console-text "Unit Tests B"

    assert_success
    [[ "$output" == $'not ok 1 - failing test\n# stage detail' ]] || fail "Unexpected stage output: $output"
}

@test "status_console_text_unknown_stage_lists_available" {
    export TEST_TEMP_DIR
    export BUILDGIT_TEST_SCENARIO="stage_missing"
    create_agent_diagnostics_wrapper

    run --separate-stderr bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --console-text "No Such Stage"

    [ "$status" -eq 1 ]
    assert_output ""
    [[ "$stderr" == *"Stage 'No Such Stage' not found"* ]] || fail "Missing stage-not-found error: $stderr"
    [[ "$stderr" == *"Available stages:"* ]] || fail "Missing available-stages header: $stderr"
    [[ "$stderr" == *"Unit Tests B"* ]] || fail "Missing stage list: $stderr"
}

@test "status_console_text_exit_code_not_found" {
    export TEST_TEMP_DIR
    export BUILDGIT_TEST_SCENARIO="build_missing"
    create_agent_diagnostics_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --console-text

    [ "$status" -eq 1 ]
}

@test "status_list_stages_plain" {
    export TEST_TEMP_DIR
    create_agent_diagnostics_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --list-stages

    assert_success
    [[ "$output" == $'Build\nUnit Tests A\nUnit Tests B\nDeploy' ]] || fail "Unexpected list-stages output: $output"
}

@test "status_list_stages_json" {
    export TEST_TEMP_DIR
    create_agent_diagnostics_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --list-stages --json

    assert_success
    echo "$output" | jq -e 'type == "array" and length == 4 and .[2].name == "Unit Tests B"' >/dev/null
}

@test "status_list_stages_includes_parallel" {
    export TEST_TEMP_DIR
    create_agent_diagnostics_wrapper

    run bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --list-stages

    assert_success
    assert_output --partial "Unit Tests A"
    assert_output --partial "Unit Tests B"
}
