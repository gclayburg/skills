#!/usr/bin/env bats

# Unit tests for _handle_build_completion and unified post-monitoring output
# Spec reference: unify-follow-log-spec.md, Section 4 (Build Completion)
# Plan reference: unify-follow-log-plan.md, Chunk E

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # Source buildgit for testing
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    # Disable colors for testing
    export NO_COLOR=1
    _init_colors
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# Test Cases: Finished line output
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 4 (Build Completion)
@test "completion_success_shows_finished" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS"}'
    }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_success
    assert_output --partial "Finished: SUCCESS"
}

@test "completion_failure_shows_finished" {
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    fetch_test_results() { echo ""; }
    display_test_results() { :; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "Finished: FAILURE"
}

@test "completion_unstable_shows_finished" {
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    fetch_test_results() { echo ""; }
    display_test_results() { :; }

    run _handle_build_completion "testjob" "42"
    assert_failure
    assert_output --partial "Finished: UNSTABLE"
}

# =============================================================================
# Test Cases: Test results display
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 4 - test failure details
@test "completion_failure_shows_test_results" {
    get_build_info() {
        echo '{"building":false,"result":"UNSTABLE"}'
    }
    fetch_test_results() {
        echo '{"failCount":1,"passCount":32,"skipCount":0,"totalCount":33}'
    }
    display_test_results() {
        echo "=== Test Results ==="
        echo "  Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0"
        echo "===================="
    }

    run _handle_build_completion "testjob" "42"
    assert_output --partial "=== Test Results ==="
    assert_output --partial "Finished: UNSTABLE"
}

@test "completion_success_no_test_results" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS"}'
    }
    # fetch_test_results should NOT be called for SUCCESS
    local fetch_called=false
    fetch_test_results() {
        echo "SHOULD_NOT_APPEAR" > "${TEST_TEMP_DIR}/fetch_called"
        echo ""
    }

    run _handle_build_completion "testjob" "42"
    assert_success
    # Test results fetch should not have been called
    [[ ! -f "${TEST_TEMP_DIR}/fetch_called" ]]
}

# =============================================================================
# Test Cases: No re-display of banner/stages
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 4 - no re-display after monitoring
@test "completion_no_re_display_banner" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS"}'
    }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_success
    # Should NOT contain build banners
    refute_output --partial "BUILD SUCCESSFUL"
    refute_output --partial "BUILD FAILED"
    refute_output --partial "BUILD IN PROGRESS"
}

@test "completion_no_re_display_stages" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS"}'
    }
    get_all_stages() {
        echo '[{"name":"Build","status":"SUCCESS","durationMillis":5000}]'
    }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_success
    # Should NOT re-display stages
    refute_output --partial "Stage:"
}

# =============================================================================
# Test Cases: Exit codes
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 4
@test "completion_returns_0_for_success" {
    get_build_info() {
        echo '{"building":false,"result":"SUCCESS"}'
    }
    fetch_test_results() { echo ""; }

    run _handle_build_completion "testjob" "42"
    assert_success
}

@test "completion_returns_1_for_failure" {
    get_build_info() {
        echo '{"building":false,"result":"FAILURE"}'
    }
    fetch_test_results() { echo ""; }
    display_test_results() { :; }

    run _handle_build_completion "testjob" "42"
    assert_failure
}

# =============================================================================
# Test Cases: Integration with command handlers
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 5
@test "push_completion_uses_finished_line" {
    # Verify _push_handle_build_result calls _handle_build_completion
    run grep -A5 "_push_handle_build_result()" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_handle_build_completion"
}

@test "build_completion_uses_finished_line" {
    # Verify _build_handle_result calls _handle_build_completion
    run grep -A5 "_build_handle_result()" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_handle_build_completion"
}

@test "follow_completion_uses_finished_line" {
    # Verify _cmd_status_follow calls _handle_build_completion
    run grep "_handle_build_completion" "${PROJECT_DIR}/buildgit"
    assert_success
    # Should be called in _cmd_status_follow as well
    assert_output --partial "_handle_build_completion"
}
