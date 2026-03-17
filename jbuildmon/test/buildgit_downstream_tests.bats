#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
    FIXTURES_DIR="${TEST_DIR}/fixtures"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _BUILDGIT_TESTING=1
    # shellcheck source=../buildgit
    source "${PROJECT_DIR}/buildgit"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

@test "collect_no_downstream_returns_parent_only" {
    fetch_test_results() {
        cat "${FIXTURES_DIR}/downstream_test_report_handle.json"
    }
    detect_all_downstream_builds() { :; }
    export FIXTURES_DIR

    run collect_downstream_test_results "ralph1/main" "100" "parent-console"
    assert_success
    echo "$output" | jq -e 'length == 1' >/dev/null
    echo "$output" | jq -e '.[0].job == "ralph1/main"' >/dev/null
    echo "$output" | jq -e '.[0].stage == "ralph1/main"' >/dev/null
    echo "$output" | jq -e '.[0].build_number == 100' >/dev/null
    echo "$output" | jq -e '.[0].depth == 0' >/dev/null
    echo "$output" | jq -e '.[0].test_json | fromjson | .passCount == 83' >/dev/null
}

@test "collect_with_downstream_returns_all" {
    fetch_test_results() {
        case "$1#$2" in
            "ralph1/main#100")
                cat "${FIXTURES_DIR}/downstream_test_report_handle.json"
                ;;
            "phandlemono-handle#201")
                cat "${FIXTURES_DIR}/downstream_test_report_handle.json"
                ;;
            "phandlemono-signalboot#202")
                cat "${FIXTURES_DIR}/downstream_test_report_signalboot.json"
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                printf '%s\n' "phandlemono-handle 201" "phandlemono-signalboot 202"
                ;;
        esac
    }
    get_all_stages() {
        echo '[{"name":"Build Handle"},{"name":"Build SignalBoot"}]'
    }
    extract_stage_logs() {
        case "$2" in
            "Build Handle")
                echo "Starting building: phandlemono-handle #201"
                ;;
            "Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #202"
                ;;
        esac
    }
    get_console_output() { :; }
    export FIXTURES_DIR

    run collect_downstream_test_results "ralph1/main" "100" "parent-console"
    assert_success
    echo "$output" | jq -e 'length == 3' >/dev/null
    echo "$output" | jq -e '.[1].stage == "Build Handle"' >/dev/null
    echo "$output" | jq -e '.[2].stage == "Build SignalBoot"' >/dev/null
    echo "$output" | jq -e '.[1].depth == 1 and .[2].depth == 1' >/dev/null
    echo "$output" | jq -e '.[2].test_json | fromjson | .passCount == 15' >/dev/null
}

@test "collect_parent_404_downstream_have_results" {
    fetch_test_results() {
        case "$1#$2" in
            "ralph1/main#100")
                echo ""
                ;;
            "phandlemono-handle#201")
                cat "${FIXTURES_DIR}/downstream_test_report_handle.json"
                ;;
            "phandlemono-signalboot#202")
                cat "${FIXTURES_DIR}/downstream_test_report_signalboot.json"
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                printf '%s\n' "phandlemono-handle 201" "phandlemono-signalboot 202"
                ;;
        esac
    }
    get_all_stages() {
        echo '[{"name":"Build Handle"},{"name":"Build SignalBoot"}]'
    }
    extract_stage_logs() {
        case "$2" in
            "Build Handle")
                echo "Starting building: phandlemono-handle #201"
                ;;
            "Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #202"
                ;;
        esac
    }
    get_console_output() { :; }
    export FIXTURES_DIR

    run collect_downstream_test_results "ralph1/main" "100" "parent-console"
    assert_success
    echo "$output" | jq -e '.[0].test_json == ""' >/dev/null
    echo "$output" | jq -e '.[1].test_json != "" and .[2].test_json != ""' >/dev/null
}

@test "collect_recursive_downstream_tracks_depth" {
    fetch_test_results() {
        case "$1#$2" in
            "ralph1/main#100")
                cat "${FIXTURES_DIR}/downstream_test_report_handle.json"
                ;;
            "phandlemono-signalboot#202")
                cat "${FIXTURES_DIR}/downstream_test_report_signalboot.json"
                ;;
            "nested-smoke#303")
                cat "${FIXTURES_DIR}/downstream_test_report_signalboot_fail.json"
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                echo "phandlemono-signalboot 202"
                ;;
            "signalboot-console")
                echo "nested-smoke 303"
                ;;
        esac
    }
    get_all_stages() {
        case "$1#$2" in
            "ralph1/main#100")
                echo '[{"name":"Build SignalBoot"}]'
                ;;
            "phandlemono-signalboot#202")
                echo '[{"name":"Nested Smoke"}]'
                ;;
            *)
                echo '[]'
                ;;
        esac
    }
    extract_stage_logs() {
        case "$1|$2" in
            "parent-console|Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #202"
                ;;
            "signalboot-console|Nested Smoke")
                echo "Starting building: nested-smoke #303"
                ;;
        esac
    }
    get_console_output() {
        case "$1#$2" in
            "phandlemono-signalboot#202")
                echo "signalboot-console"
                ;;
        esac
    }
    export FIXTURES_DIR

    run collect_downstream_test_results "ralph1/main" "100" "parent-console"
    assert_success
    echo "$output" | jq -e 'length == 3' >/dev/null
    echo "$output" | jq -e '.[2].job == "nested-smoke" and .[2].depth == 2 and .[2].stage == "Nested Smoke"' >/dev/null
}

@test "aggregate_totals_correct_math" {
    local collected_json
    collected_json='[
      {"job":"ralph1/main","stage":"ralph1/main","build_number":100,"depth":0,"test_json":"{\"passCount\":83,\"failCount\":0,\"skipCount\":0}"},
      {"job":"phandlemono-signalboot","stage":"Build SignalBoot","build_number":202,"depth":1,"test_json":"{\"passCount\":14,\"failCount\":1,\"skipCount\":0}"}
    ]'

    run aggregate_test_totals "$collected_json"
    assert_success
    assert_output $'98\n97\n1\n0'
}

@test "aggregate_totals_treats_missing_as_zero" {
    local collected_json
    collected_json='[
      {"job":"ralph1/main","stage":"ralph1/main","build_number":100,"depth":0,"test_json":""},
      {"job":"phandlemono-signalboot","stage":"Build SignalBoot","build_number":202,"depth":1,"test_json":"{\"passCount\":15,\"failCount\":0,\"skipCount\":0}"}
    ]'

    run aggregate_test_totals "$collected_json"
    assert_success
    assert_output $'15\n15\n0\n0'
}

@test "has_downstream_true_for_multi" {
    run has_downstream_builds '[{"job":"a"},{"job":"b"},{"job":"c"}]'
    assert_success
}

@test "has_downstream_false_for_single" {
    run has_downstream_builds '[{"job":"a"}]'
    [ "$status" -eq 1 ]
}

@test "collect_downstream_comm_error_on_parent" {
    fetch_test_results() {
        return 2
    }
    detect_all_downstream_builds() {
        fail "detect_all_downstream_builds should not be called on parent communication failure"
    }

    run collect_downstream_test_results "ralph1/main" "100" "parent-console"
    [ "$status" -eq 2 ]
    assert_output ""
}

@test "collect_downstream_comm_error_on_child" {
    fetch_test_results() {
        case "$1#$2" in
            "ralph1/main#100")
                cat "${FIXTURES_DIR}/downstream_test_report_handle.json"
                ;;
            "phandlemono-handle#201")
                return 2
                ;;
            "phandlemono-signalboot#202")
                cat "${FIXTURES_DIR}/downstream_test_report_signalboot.json"
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                printf '%s\n' "phandlemono-handle 201" "phandlemono-signalboot 202"
                ;;
        esac
    }
    get_all_stages() {
        echo '[{"name":"Build Handle"},{"name":"Build SignalBoot"}]'
    }
    extract_stage_logs() {
        case "$2" in
            "Build Handle")
                echo "Starting building: phandlemono-handle #201"
                ;;
            "Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #202"
                ;;
        esac
    }
    get_console_output() { :; }
    export FIXTURES_DIR

    run collect_downstream_test_results "ralph1/main" "100" "parent-console"
    assert_success
    echo "$output" | jq -e '.[1].job == "phandlemono-handle" and .[1].test_json == ""' >/dev/null
    echo "$output" | jq -e '.[2].job == "phandlemono-signalboot" and (.[2].test_json | fromjson | .passCount == 15)' >/dev/null
}

@test "collect_large_parent_report_avoids_arg_limit" {
    fetch_test_results() {
        jq -cn '
            {
              passCount: 5000,
              failCount: 0,
              skipCount: 0,
              suites: [
                range(0; 5000) |
                {
                  name: ("suite-" + tostring),
                  cases: [
                    {
                      className: "pkg.Test",
                      name: ("test_" + tostring),
                      status: "PASSED"
                    }
                  ]
                }
              ]
            }
        '
    }
    detect_all_downstream_builds() { :; }

    local output_file="${TEST_TEMP_DIR}/large-parent-report.json"
    collect_downstream_test_results "ralph1/main" "100" "parent-console" > "$output_file"
    jq -e 'length == 1' "$output_file" >/dev/null
    jq -e '.[0].test_json | fromjson | .passCount == 5000 and (.suites | length == 5000)' "$output_file" >/dev/null
}

@test "stage_name_mapping" {
    fetch_test_results() {
        case "$1#$2" in
            "ralph1/main#100")
                cat "${FIXTURES_DIR}/downstream_test_report_handle.json"
                ;;
            "phandlemono-signalboot#202")
                cat "${FIXTURES_DIR}/downstream_test_report_signalboot.json"
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                echo "phandlemono-signalboot 202"
                ;;
        esac
    }
    get_all_stages() {
        echo '[{"name":"Build Handle"},{"name":"Build SignalBoot"},{"name":"Publish"}]'
    }
    extract_stage_logs() {
        case "$2" in
            "Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #202"
                ;;
        esac
    }
    get_console_output() { :; }
    export FIXTURES_DIR

    run collect_downstream_test_results "ralph1/main" "100" "parent-console"
    assert_success
    echo "$output" | jq -e '.[1].stage == "Build SignalBoot"' >/dev/null
}

@test "hierarchical_display_all_passing" {
    local collected_json
    collected_json='[
      {"job":"phandlemono-IT","stage":"phandlemono-IT","build_number":75,"depth":0,"test_json":"{\"passCount\":19,\"failCount\":0,\"skipCount\":0}"},
      {"job":"phandlemono-signalboot","stage":"Build SignalBoot","build_number":63,"depth":1,"test_json":"{\"passCount\":15,\"failCount\":0,\"skipCount\":0}"},
      {"job":"phandlemono-handle","stage":"Build Handle","build_number":66,"depth":1,"test_json":"{\"passCount\":64,\"failCount\":0,\"skipCount\":0}"}
    ]'

    COLOR_GREEN="<GREEN>"
    COLOR_YELLOW="<YELLOW>"
    COLOR_RED="<RED>"
    COLOR_RESET="<RESET>"

    run display_hierarchical_test_results "$collected_json"
    assert_success
    assert_output --partial "<GREEN>=== Test Results ===<RESET>"
    assert_output --partial "phandlemono-IT"
    assert_output --partial "  Build SignalBoot"
    assert_output --partial "  Build Handle"
    assert_output --partial "--------------------"
    assert_output --partial "Totals"
    assert_output --partial "Passed: 98 | Failed: 0 | Skipped: 0"
    assert_output --partial "<GREEN>====================<RESET>"
}

@test "hierarchical_display_with_failure" {
    local collected_json
    collected_json='[
      {"job":"phandlemono-IT","stage":"phandlemono-IT","build_number":73,"depth":0,"test_json":""},
      {"job":"phandlemono-signalboot","stage":"Build SignalBoot","build_number":63,"depth":1,"test_json":"{\"passCount\":14,\"failCount\":1,\"skipCount\":0}"},
      {"job":"phandlemono-handle","stage":"Build Handle","build_number":66,"depth":1,"test_json":"{\"passCount\":83,\"failCount\":0,\"skipCount\":0}"}
    ]'

    COLOR_GREEN="<GREEN>"
    COLOR_YELLOW="<YELLOW>"
    COLOR_RED="<RED>"
    COLOR_RESET="<RESET>"

    run display_hierarchical_test_results "$collected_json"
    assert_success
    assert_output --partial "<YELLOW>=== Test Results ===<RESET>"
    assert_output --partial "phandlemono-IT"
    assert_output --partial "Total:  ? | Passed:  ? | Failed: ? | Skipped: ?"
    assert_output --partial "Build SignalBoot"
    assert_output --partial "Passed: 97 | Failed: 1 | Skipped: 0"
    assert_output --partial "<YELLOW>====================<RESET>"
}

@test "hierarchical_display_right_alignment" {
    local collected_json
    collected_json='[
      {"job":"parent","stage":"parent","build_number":1,"depth":0,"test_json":"{\"passCount\":1,\"failCount\":0,\"skipCount\":0}"},
      {"job":"child","stage":"Build Child","build_number":2,"depth":1,"test_json":"{\"passCount\":123,\"failCount\":4,\"skipCount\":5}"}
    ]'

    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_RESET=""

    run display_hierarchical_test_results "$collected_json"
    assert_success

    local data_lines
    data_lines=$(echo "$output" | grep -E '^(parent|  Build Child|Totals)')

    local total_positions passed_positions failed_positions skipped_positions
    total_positions=$(echo "$data_lines" | awk '{print index($0, "Total: ")}' | sort -u | wc -l | tr -d ' ')
    passed_positions=$(echo "$data_lines" | awk '{print index($0, "| Passed: ")}' | sort -u | wc -l | tr -d ' ')
    failed_positions=$(echo "$data_lines" | awk '{print index($0, "| Failed: ")}' | sort -u | wc -l | tr -d ' ')
    skipped_positions=$(echo "$data_lines" | awk '{print index($0, "| Skipped: ")}' | sort -u | wc -l | tr -d ' ')

    [[ "$total_positions" -eq 1 ]] || fail "Total column was not aligned"
    [[ "$passed_positions" -eq 1 ]] || fail "Passed column was not aligned"
    [[ "$failed_positions" -eq 1 ]] || fail "Failed column was not aligned"
    [[ "$skipped_positions" -eq 1 ]] || fail "Skipped column was not aligned"
}

@test "hierarchical_display_no_downstream_fallback" {
    display_test_results() {
        echo "fallback:$1"
    }

    run display_hierarchical_test_results '[{"job":"parent","stage":"parent","build_number":1,"depth":0,"test_json":"{\"passCount\":19,\"failCount\":0,\"skipCount\":0}"}]'
    assert_success
    assert_output 'fallback:{"passCount":19,"failCount":0,"skipCount":0}'
}

@test "hierarchical_display_failed_test_details" {
    local fail_json collected_json
    fail_json=$(jq -c . < "${FIXTURES_DIR}/downstream_test_report_signalboot_fail.json")
    collected_json=$(jq -cn \
        --arg fail_json "$fail_json" \
        '[
          {job:"phandlemono-IT",stage:"phandlemono-IT",build_number:73,depth:0,test_json:""},
          {job:"phandlemono-signalboot",stage:"Build SignalBoot",build_number:63,depth:1,test_json:$fail_json},
          {job:"phandlemono-handle",stage:"Build Handle",build_number:66,depth:1,test_json:"{\"passCount\":83,\"failCount\":0,\"skipCount\":0}"}
        ]')

    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_RESET=""

    run display_hierarchical_test_results "$collected_json"
    assert_success
    assert_output --partial "FAILED TESTS:"
    assert_output --partial "signalboot.tests.IntegrationTests::handles missing config"
}

@test "hierarchical_display_color_per_line" {
    local collected_json
    collected_json='[
      {"job":"phandlemono-IT","stage":"phandlemono-IT","build_number":73,"depth":0,"test_json":""},
      {"job":"phandlemono-signalboot","stage":"Build SignalBoot","build_number":63,"depth":1,"test_json":"{\"passCount\":14,\"failCount\":1,\"skipCount\":0}"},
      {"job":"phandlemono-handle","stage":"Build Handle","build_number":66,"depth":1,"test_json":"{\"passCount\":83,\"failCount\":0,\"skipCount\":0}"}
    ]'

    COLOR_GREEN="<GREEN>"
    COLOR_YELLOW="<YELLOW>"
    COLOR_RED="<RED>"
    COLOR_RESET="<RESET>"

    run display_hierarchical_test_results "$collected_json"
    assert_success
    assert_output --partial "<YELLOW>  Build SignalBoot"
    assert_output --partial "<GREEN>  Build Handle"
    refute_output --partial "<GREEN>phandlemono-IT"
    refute_output --partial "<YELLOW>phandlemono-IT"
}

@test "success_output_shows_hierarchical_results" {
    log_banner() { :; }
    _print_build_header() { :; }
    _display_stages() { :; }
    print_finished_line() { :; }
    log_info() { :; }
    format_duration() { echo "1m"; }
    _parse_build_metadata() { _META_AGENT=""; }
    get_console_output() {
        echo "success-console"
    }
    collect_downstream_test_results() {
        [[ "$3" == "success-console" ]] || fail "display_success_output should fetch console output for downstream detection"
        echo '[{"job":"parent","stage":"parent","build_number":1,"depth":0,"test_json":"{\"passCount\":19,\"failCount\":0,\"skipCount\":0}"},{"job":"child","stage":"Build Child","build_number":2,"depth":1,"test_json":"{\"passCount\":15,\"failCount\":0,\"skipCount\":0}"}]'
    }
    display_hierarchical_test_results() {
        echo "hierarchical:$1"
    }

    run display_success_output "test-job" "42" '{"duration":60000,"timestamp":0,"url":"http://jenkins/job/test/42/"}' "automated" "user" "abc1234" "msg" "match"
    assert_success
    assert_output --partial "hierarchical:[{\"job\":\"parent\""
}

@test "failure_diagnostics_shows_hierarchical_results" {
    _display_early_failure_console() {
        return 1
    }
    _display_failed_jobs_tree() {
        echo "failed-jobs"
    }
    _display_error_log_section() {
        echo "error-log:$4"
    }
    collect_downstream_test_results() {
        [[ "$3" == "failure-console" ]] || fail "failure diagnostics should reuse provided console output"
        echo '[{"job":"parent","stage":"parent","build_number":1,"depth":0,"test_json":"{\"passCount\":0,\"failCount\":0,\"skipCount\":0}"},{"job":"child","stage":"Build Child","build_number":2,"depth":1,"test_json":"{\"passCount\":14,\"failCount\":1,\"skipCount\":0}"}]'
    }
    display_hierarchical_test_results() {
        echo "hierarchical:$1"
    }

    run _display_failure_diagnostics "test-job" "42" "failure-console"
    assert_success
    assert_output --partial "failed-jobs"
    assert_output --partial "hierarchical:[{\"job\":\"parent\""
    assert_output --partial 'error-log:{"passCount":0,"failCount":0,"skipCount":0}'
}

@test "monitoring_completion_shows_hierarchical_results" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS","duration":60000}'
    }
    get_console_output() {
        echo "monitor-console"
    }
    collect_downstream_test_results() {
        [[ "$3" == "monitor-console" ]] || fail "_handle_build_completion should fetch console output for downstream detection"
        echo '[{"job":"parent","stage":"parent","build_number":1,"depth":0,"test_json":"{\"passCount\":19,\"failCount\":0,\"skipCount\":0}"},{"job":"child","stage":"Build Child","build_number":2,"depth":1,"test_json":"{\"passCount\":15,\"failCount\":0,\"skipCount\":0}"}]'
    }
    display_hierarchical_test_results() {
        echo "hierarchical:$1"
    }
    print_finished_line() {
        echo "finished:$1"
    }
    log_info() { :; }
    format_duration() { echo "1m"; }

    run _handle_build_completion "testjob" "42"
    assert_success
    assert_output --partial "hierarchical:[{\"job\":\"parent\""
    assert_output --partial "finished:SUCCESS"
}

@test "monitoring_completion_single_job_unchanged" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS","duration":60000}'
    }
    get_console_output() {
        echo ""
    }
    collect_downstream_test_results() {
        echo '[{"job":"testjob","stage":"testjob","build_number":42,"depth":0,"test_json":"{\"passCount\":19,\"failCount\":0,\"skipCount\":0}"}]'
    }
    display_hierarchical_test_results() {
        echo "hierarchical:$1"
    }
    print_finished_line() {
        echo "finished:$1"
    }
    log_info() { :; }
    format_duration() { echo "1m"; }

    run _handle_build_completion "testjob" "42"
    assert_success
    assert_output --partial 'hierarchical:[{"job":"testjob","stage":"testjob","build_number":42,"depth":0,"test_json":"{\"passCount\":19,\"failCount\":0,\"skipCount\":0}"}]'
    assert_output --partial "finished:SUCCESS"
}

@test "monitoring_comm_error_no_downstream" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS","duration":60000}'
    }
    get_console_output() {
        echo "monitor-console"
    }
    collect_downstream_test_results() {
        return 2
    }
    _note_test_results_comm_failure() {
        echo "note:$1#$2"
    }
    display_test_results_comm_error() {
        echo "comm-error"
    }
    display_hierarchical_test_results() {
        fail "display_hierarchical_test_results should not be called on communication failure"
    }
    print_finished_line() {
        echo "finished:$1"
    }
    log_info() { :; }
    format_duration() { echo "1m"; }

    run _handle_build_completion "testjob" "42"
    assert_success
    assert_output --partial "note:testjob#42"
    assert_output --partial "comm-error"
    assert_output --partial "finished:SUCCESS"
}

@test "oneline_uses_downstream_totals" {
    _LINE_FORMAT_STRING="$_DEFAULT_LINE_FORMAT"
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RESET=""
    _extract_git_info_from_build() {
        _LINE_COMMIT_SHA="abc1234"
        _LINE_BRANCH_NAME="main"
    }
    get_console_output() {
        case "$1#$2" in
            "phandlemono-IT#75")
                echo "parent-console"
                ;;
            *)
                echo ""
                ;;
        esac
    }
    fetch_test_results() {
        case "$1#$2" in
            "phandlemono-IT#75")
                echo '{"passCount":19,"failCount":0,"skipCount":0}'
                ;;
            "phandlemono-handle#66")
                echo '{"passCount":64,"failCount":0,"skipCount":0}'
                ;;
            "phandlemono-signalboot#63")
                echo '{"passCount":15,"failCount":0,"skipCount":0}'
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                printf '%s\n' "phandlemono-signalboot 63" "phandlemono-handle 66"
                ;;
        esac
    }
    get_all_stages() {
        echo '[{"name":"Build SignalBoot"},{"name":"Build Handle"}]'
    }
    extract_stage_logs() {
        case "$2" in
            "Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #63"
                ;;
            "Build Handle")
                echo "Starting building: phandlemono-handle #66"
                ;;
        esac
    }

    run _status_line_for_build_json "phandlemono-IT" "75" '{"number":75,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":341000,"url":"http://jenkins/job/phandlemono-IT/75/"}' "false"
    assert_success
    assert_output --partial "Tests=98/0/0"
}

@test "oneline_parent_404_uses_downstream_totals" {
    _LINE_FORMAT_STRING="$_DEFAULT_LINE_FORMAT"
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RESET=""
    _extract_git_info_from_build() {
        _LINE_COMMIT_SHA="abc1234"
        _LINE_BRANCH_NAME="main"
    }
    get_console_output() {
        case "$1#$2" in
            "phandlemono-IT#73")
                echo "parent-console"
                ;;
            *)
                echo ""
                ;;
        esac
    }
    fetch_test_results() {
        case "$1#$2" in
            "phandlemono-IT#73")
                echo ""
                ;;
            "phandlemono-handle#66")
                echo '{"passCount":83,"failCount":0,"skipCount":0}'
                ;;
            "phandlemono-signalboot#63")
                echo '{"passCount":14,"failCount":1,"skipCount":0}'
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                printf '%s\n' "phandlemono-signalboot 63" "phandlemono-handle 66"
                ;;
        esac
    }
    get_all_stages() {
        echo '[{"name":"Build SignalBoot"},{"name":"Build Handle"}]'
    }
    extract_stage_logs() {
        case "$2" in
            "Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #63"
                ;;
            "Build Handle")
                echo "Starting building: phandlemono-handle #66"
                ;;
        esac
    }

    run _status_line_for_build_json "phandlemono-IT" "73" '{"number":73,"result":"FAILURE","building":false,"timestamp":1706700000000,"duration":249000,"url":"http://jenkins/job/phandlemono-IT/73/"}' "false"
    [ "$status" -eq 1 ]
    assert_output --partial "Tests=97/1/0"
}

@test "oneline_no_downstream_unchanged" {
    _LINE_FORMAT_STRING="$_DEFAULT_LINE_FORMAT"
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RESET=""
    _extract_git_info_from_build() {
        _LINE_COMMIT_SHA="abc1234"
        _LINE_BRANCH_NAME="main"
    }
    get_console_output() {
        echo ""
    }
    detect_all_downstream_builds() {
        fail "detect_all_downstream_builds should not be called without console output"
    }
    fetch_test_results() {
        echo '{"passCount":120,"failCount":0,"skipCount":0}'
    }

    run _status_line_for_build_json "ralph1/main" "42" '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins/job/ralph1/42/"}' "false"
    assert_success
    assert_output --partial "Tests=120/0/0"
}

@test "json_breakdown_present_for_multi_job" {
    collect_downstream_test_results() {
        [[ "$3" == "parent-console" ]] || fail "output_json should pass through console output"
        echo '[
          {"job":"phandlemono-IT","stage":"phandlemono-IT","build_number":73,"depth":0,"test_json":""},
          {"job":"phandlemono-signalboot","stage":"Build SignalBoot","build_number":63,"depth":1,"test_json":"{\"passCount\":14,\"failCount\":1,\"skipCount\":0,\"suites\":[{\"cases\":[{\"className\":\"signalboot.tests.IntegrationTests\",\"name\":\"handles missing config\",\"status\":\"FAILED\",\"errorDetails\":\"expected config to exist\",\"errorStackTrace\":\"line one\\nline two\",\"duration\":1.2,\"age\":1}]}]}"},
          {"job":"phandlemono-handle","stage":"Build Handle","build_number":66,"depth":1,"test_json":"{\"passCount\":83,\"failCount\":0,\"skipCount\":0}"}
        ]'
    }
    _get_nested_stages() {
        echo "[]"
    }
    _build_failure_json() {
        echo '{}'
    }
    _build_info_json() {
        echo '{}'
    }

    run output_json "phandlemono-IT" "73" '{"number":73,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":249000,"url":"http://jenkins/job/phandlemono-IT/73/"}' "manual" "tester" "abc1234" "msg" "your_commit" "parent-console"
    assert_success
    echo "$output" | jq -e '.test_results.total == 98 and .test_results.passed == 97 and .test_results.failed == 1 and .test_results.skipped == 0' >/dev/null
    echo "$output" | jq -e '.test_results.breakdown | length == 3' >/dev/null
    echo "$output" | jq -e '.test_results.breakdown[0].total == null and .test_results.breakdown[0].failed_tests == null' >/dev/null
    echo "$output" | jq -e '.test_results.breakdown[1].stage == "Build SignalBoot" and .test_results.breakdown[1].failed == 1' >/dev/null
    echo "$output" | jq -e '.test_results.failed_tests | length == 1' >/dev/null
}

@test "json_no_breakdown_for_single_job" {
    collect_downstream_test_results() {
        echo '[{"job":"ralph1/main","stage":"ralph1/main","build_number":42,"depth":0,"test_json":"{\"passCount\":120,\"failCount\":0,\"skipCount\":0}"}]'
    }
    _get_nested_stages() {
        echo "[]"
    }
    _build_failure_json() {
        echo '{}'
    }
    _build_info_json() {
        echo '{}'
    }

    run output_json "ralph1/main" "42" '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins/job/ralph1/42/"}' "manual" "tester" "abc1234" "msg" "your_commit" "parent-console"
    assert_success
    echo "$output" | jq -e '.test_results.total == 120 and (.test_results | has("breakdown") | not)' >/dev/null
}

@test "json_totals_match_oneline" {
    _LINE_FORMAT_STRING="$_DEFAULT_LINE_FORMAT"
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RESET=""
    _extract_git_info_from_build() {
        _LINE_COMMIT_SHA="abc1234"
        _LINE_BRANCH_NAME="main"
    }
    get_console_output() {
        case "$1#$2" in
            "phandlemono-IT#73")
                echo "parent-console"
                ;;
            *)
                echo ""
                ;;
        esac
    }
    fetch_test_results() {
        case "$1#$2" in
            "phandlemono-IT#73")
                echo ""
                ;;
            "phandlemono-handle#66")
                echo '{"passCount":83,"failCount":0,"skipCount":0}'
                ;;
            "phandlemono-signalboot#63")
                echo '{"passCount":14,"failCount":1,"skipCount":0}'
                ;;
        esac
    }
    detect_all_downstream_builds() {
        case "$1" in
            "parent-console")
                printf '%s\n' "phandlemono-signalboot 63" "phandlemono-handle 66"
                ;;
        esac
    }
    get_all_stages() {
        echo '[{"name":"Build SignalBoot"},{"name":"Build Handle"}]'
    }
    extract_stage_logs() {
        case "$2" in
            "Build SignalBoot")
                echo "Starting building: phandlemono-signalboot #63"
                ;;
            "Build Handle")
                echo "Starting building: phandlemono-handle #66"
                ;;
        esac
    }
    _get_nested_stages() {
        echo "[]"
    }
    _build_failure_json() {
        echo '{}'
    }
    _build_info_json() {
        echo '{}'
    }

    run _status_line_for_build_json "phandlemono-IT" "73" '{"number":73,"result":"FAILURE","building":false,"timestamp":1706700000000,"duration":249000,"url":"http://jenkins/job/phandlemono-IT/73/"}' "false"
    local line_output="$output"
    [ "$status" -eq 1 ]

    run output_json "phandlemono-IT" "73" '{"number":73,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":249000,"url":"http://jenkins/job/phandlemono-IT/73/"}' "manual" "tester" "abc1234" "msg" "your_commit" "parent-console"
    assert_success
    [ "$(printf '%s' "$line_output" | sed -n 's/.*Tests=\([^ ]*\).*/\1/p')" = "97/1/0" ]
    [ "$(echo "$output" | jq -r '.test_results | "\(.passed)/\(.failed)/\(.skipped)"')" = "97/1/0" ]
}

@test "oneline_comm_error_no_downstream_fallback" {
    _LINE_FORMAT_STRING="$_DEFAULT_LINE_FORMAT"
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RESET=""
    _extract_git_info_from_build() {
        _LINE_COMMIT_SHA="abc1234"
        _LINE_BRANCH_NAME="main"
    }
    get_console_output() {
        fail "get_console_output should not be called after parent communication failure"
    }
    collect_downstream_test_results() {
        fail "collect_downstream_test_results should not be called after parent communication failure"
    }
    fetch_test_results() {
        return 2
    }

    run _status_line_for_build_json "ralph1/main" "42" '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins/job/ralph1/42/"}' "false"
    assert_success
    assert_output --partial "Tests=!err!"
    assert_output --partial "Could not retrieve test results (communication error)"
}
