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
        stage_ambiguous)
            _STAGE_CONSOLE_AMBIGUOUS_STAGES=$'Main Build Linux\nMain Build Mac'
            return 4
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

@test "get_stage_console_output_falls_back_to_descendant_stage_logs_when_parent_log_is_empty" {
    jenkins_job_path() {
        echo "job/test-job"
    }

    get_all_stages() {
        cat <<'JSON'
[
  {"id":"10","name":"Main Build","status":"FAILED","startTimeMillis":1,"durationMillis":1000},
  {"id":"11","name":"Compile","status":"SUCCESS","startTimeMillis":2,"durationMillis":2000},
  {"id":"12","name":"Unit Tests","status":"FAILED","startTimeMillis":3,"durationMillis":3000}
]
JSON
    }

    get_blue_ocean_nodes() {
        cat <<'JSON'
[
  {"id":"10","name":"Main Build","type":"STAGE","firstParent":""},
  {"id":"11","name":"Compile","type":"STAGE","firstParent":"10"},
  {"id":"12","name":"Unit Tests","type":"STAGE","firstParent":"10"}
]
JSON
    }

    jenkins_api_with_status() {
        case "$1" in
            job/test-job/60/execution/node/10/wfapi/log)
                printf '{"text":""}\n200\n'
                ;;
            job/test-job/60/execution/node/11/wfapi/log)
                printf '{"text":"compile failed fast"}\n200\n'
                ;;
            job/test-job/60/execution/node/12/wfapi/log)
                printf '{"text":"not ok 1 - unit test failure"}\n200\n'
                ;;
            *)
                return 1
                ;;
        esac
    }

    run get_stage_console_output "test-job" "60" "main build"

    assert_success
    [[ "$output" == *"===== Main Build -> Compile ====="* ]] || fail "Missing compile section: $output"
    [[ "$output" == *"compile failed fast"* ]] || fail "Missing compile log: $output"
    [[ "$output" == *"===== Main Build -> Unit Tests ====="* ]] || fail "Missing unit tests section: $output"
    [[ "$output" == *"not ok 1 - unit test failure"* ]] || fail "Missing unit test log: $output"
}

@test "get_stage_console_output_falls_back_to_stage_flow_nodes_when_stage_log_is_empty" {
    jenkins_job_path() {
        echo "job/test-job"
    }

    get_all_stages() {
        cat <<'JSON'
[
  {"id":"30","name":"main build","status":"FAILED","startTimeMillis":1,"durationMillis":1000}
]
JSON
    }

    get_blue_ocean_nodes() {
        echo "[]"
    }

    jenkins_api() {
        case "$1" in
            job/test-job/60/execution/node/30/wfapi/describe)
                cat <<'JSON'
{"id":"30","name":"main build","stageFlowNodes":[{"id":"31","name":"run Artifactory maven","stageFlowNodes":[]}]}
JSON
                ;;
            *)
                return 1
                ;;
        esac
    }

    jenkins_api_with_status() {
        case "$1" in
            job/test-job/60/execution/node/30/wfapi/log)
                printf '{"text":""}\n200\n'
                ;;
            job/test-job/60/execution/node/31/wfapi/log)
                printf '%s\n200\n' '{"text":"<span class=\"timestamp\"><b>2026-03-01 12:35:55</b> </span>Jenkins Artifactory Plugin version: 4.0.8\nERROR: Couldn'\''t execute Maven task."}'
                ;;
            *)
                return 1
                ;;
        esac
    }

    run get_stage_console_output "test-job" "60" "main build"

    assert_success
    [[ "$output" == *"===== main build -> run Artifactory maven ====="* ]] || fail "Missing flow-node section header: $output"
    [[ "$output" == *"Jenkins Artifactory Plugin version: 4.0.8"* ]] || fail "Missing cleaned flow-node log text: $output"
    [[ "$output" == *"ERROR: Couldn't execute Maven task."* ]] || fail "Missing flow-node failure log: $output"
    [[ "$output" != *"<span"* ]] || fail "Expected HTML tags to be stripped: $output"
}

@test "get_stage_console_output_reports_ambiguous_partial_stage_names" {
    local stages_json match_output
    stages_json='[
      {"id":"20","name":"Main Build Linux","status":"FAILED","startTimeMillis":1,"durationMillis":1000},
      {"id":"21","name":"Main Build Mac","status":"FAILED","startTimeMillis":2,"durationMillis":1000}
    ]'

    run _find_stage_console_match "$stages_json" "main build"

    [ "$status" -eq 4 ]
}

@test "status_console_text_ambiguous_stage_lists_matches" {
    export TEST_TEMP_DIR
    export BUILDGIT_TEST_SCENARIO="stage_ambiguous"
    create_agent_diagnostics_wrapper

    run --separate-stderr bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" 60 --console-text "main build"

    [ "$status" -eq 1 ]
    assert_output ""
    [[ "$stderr" == *"Stage 'main build' is ambiguous"* ]] || fail "Missing ambiguous-stage error: $stderr"
    [[ "$stderr" == *"Matching stages:"* ]] || fail "Missing matching-stages header: $stderr"
    [[ "$stderr" == *"Main Build Linux"* ]] || fail "Missing matching stage: $stderr"
    [[ "$stderr" == *"Main Build Mac"* ]] || fail "Missing matching stage: $stderr"
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
