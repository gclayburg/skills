#!/usr/bin/env bats

# Tests for buildgit verbose mode stdout routing

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

create_stdout_test_wrapper() {
    cat > "${TEST_TEMP_DIR}/stdout_test.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

PROJECT_DIR="${PROJECT_DIR}"
source "${PROJECT_DIR}/lib/jenkins-common.sh"

VERBOSE_MODE=false

main() {
    local action="${1:-}"
    shift || true

    if [[ "${1:-}" == "--verbose" ]]; then
        VERBOSE_MODE=true
    fi

    case "$action" in
        "test_info")
            bg_log_info "This is info message"
            ;;
        "test_success")
            bg_log_success "This is success message"
            ;;
        *)
            echo "Unknown action"
            exit 1
            ;;
    esac
}

main "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/stdout_test.sh"
}

@test "verbose_info_goes_to_stdout" {
    export PROJECT_DIR
    create_stdout_test_wrapper

    run bash -c "bash '${TEST_TEMP_DIR}/stdout_test.sh' test_info --verbose 2>/dev/null"

    assert_success
    assert_output --partial "This is info message"

    run bash -c "bash '${TEST_TEMP_DIR}/stdout_test.sh' test_info --verbose 1>/dev/null 2>&1"

    assert_success
    assert_output ""
}

@test "verbose_success_goes_to_stdout" {
    export PROJECT_DIR
    create_stdout_test_wrapper

    run bash -c "bash '${TEST_TEMP_DIR}/stdout_test.sh' test_success --verbose 2>/dev/null"

    assert_success
    assert_output --partial "This is success message"

    run bash -c "bash '${TEST_TEMP_DIR}/stdout_test.sh' test_success --verbose 1>/dev/null 2>&1"

    assert_success
    assert_output ""
}

@test "quiet_mode_no_output" {
    export PROJECT_DIR
    create_stdout_test_wrapper

    run bash -c "bash '${TEST_TEMP_DIR}/stdout_test.sh' test_info 3>&- 2>&1"
    assert_success
    assert_output ""

    run bash -c "bash '${TEST_TEMP_DIR}/stdout_test.sh' test_success 3>&- 2>&1"
    assert_success
    assert_output ""
}

@test "buildgit_bg_log_info_uses_stdout" {
    run grep -A3 "bg_log_info()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    refute_output --partial ">&2"
}

@test "buildgit_bg_log_success_uses_stdout" {
    run grep -A3 "bg_log_success()" "${PROJECT_DIR}/lib/jenkins-common.sh"
    assert_success
    refute_output --partial ">&2"
}
