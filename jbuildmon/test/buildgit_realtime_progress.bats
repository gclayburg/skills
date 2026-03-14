#!/usr/bin/env bats

# Tests for buildgit real-time progress stdout routing

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

create_progress_test_wrapper() {
    cat > "${TEST_TEMP_DIR}/progress_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

PROJECT_DIR="${PROJECT_DIR}"
source "${PROJECT_DIR}/lib/jenkins-common.sh"

main() {
    local action="${1:-}"

    case "$action" in
        "test_progress")
            bg_log_progress "Build in progress... (30s elapsed)"
            ;;
        "test_stage_completion")
            bg_log_progress_success "Stage completed: Checkout"
            ;;
        *)
            echo "Unknown action"
            exit 1
            ;;
    esac
}

main "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/progress_test.sh"
}

@test "stage_completion_shown_without_verbose" {
    export PROJECT_DIR
    create_progress_test_wrapper

    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_stage_completion 2>/dev/null"

    assert_success
    assert_output --partial "Stage completed: Checkout"
}

@test "elapsed_time_shown_without_verbose" {
    export PROJECT_DIR
    create_progress_test_wrapper

    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_progress 2>/dev/null"

    assert_success
    assert_output --partial "Build in progress"
    assert_output --partial "elapsed"
}

@test "stage_completion_format_correct" {
    export PROJECT_DIR
    create_progress_test_wrapper

    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_stage_completion 2>/dev/null"

    assert_success
    assert_output --partial "Stage completed:"
    assert_output --partial "✓"
}

@test "progress_output_to_stdout" {
    export PROJECT_DIR
    create_progress_test_wrapper

    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_progress 2>/dev/null"

    assert_success
    assert_output --partial "Build in progress"

    run bash -c "bash '${TEST_TEMP_DIR}/progress_test.sh' test_progress 1>/dev/null 2>&1"

    assert_success
    assert_output ""
}

@test "buildgit_has_bg_log_progress_function" {
    run grep -A3 "bg_log_progress()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    assert_output --partial "log_info"
    refute_output --partial ">&2"
}

@test "buildgit_has_bg_log_progress_success_function" {
    run grep -A3 "bg_log_progress_success()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    assert_output --partial "log_success"
    refute_output --partial ">&2"
}

@test "buildgit_does_not_log_inside_command_substitution" {
    run bash -c "if command -v rg >/dev/null 2>&1; then rg -n '\\$\\(.*bg_log_(info|success|progress|progress_success)' '${PROJECT_DIR}' -g '*.sh' -g 'buildgit'; else grep -REn '\\$\\(.*bg_log_(info|success|progress|progress_success)' '${PROJECT_DIR}' --include='*.sh' --include='buildgit'; fi"
    assert_failure
    assert_output ""
}

@test "follow_monitor_uses_bg_log_progress_for_elapsed_time" {
    run grep -n 'bg_log_progress "Build in progress... (${elapsed}s elapsed)"' "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "bg_log_progress"
    assert_output --partial "elapsed"
}

@test "follow_monitor_has_stage_completion_tracking" {
    run grep -n "_track_nested_stage_changes" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_track_nested_stage_changes"
}

@test "push_monitor_uses_bg_log_progress_for_elapsed_time" {
    run grep "_monitor_build" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_monitor_build"
}

@test "push_monitor_has_stage_completion_tracking" {
    run grep -c "^_push_monitor_build()" "${PROJECT_DIR}/buildgit"
    assert_failure
}

@test "build_monitor_uses_bg_log_progress_for_elapsed_time" {
    run grep "_monitor_build" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_monitor_build"
}

@test "build_monitor_has_stage_completion_tracking" {
    run grep -c "^_build_monitor()" "${PROJECT_DIR}/buildgit"
    assert_failure
}
