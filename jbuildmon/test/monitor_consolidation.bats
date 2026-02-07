#!/usr/bin/env bats

# Unit tests for consolidated _monitor_build function
# Spec reference: unify-follow-log-spec.md, Implementation Requirements
# Plan reference: unify-follow-log-plan.md, Chunk C

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # Store original environment
    ORIG_JENKINS_URL="${JENKINS_URL:-}"
    ORIG_JENKINS_USER_ID="${JENKINS_USER_ID:-}"
    ORIG_JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
    export JENKINS_URL="${ORIG_JENKINS_URL}"
    export JENKINS_USER_ID="${ORIG_JENKINS_USER_ID}"
    export JENKINS_API_TOKEN="${ORIG_JENKINS_API_TOKEN}"
}

# Helper: create a test wrapper that sources buildgit and mocks APIs
_create_monitor_test_wrapper() {
    local get_build_info_body="$1"
    local track_stage_body="${2:-echo '[]'}"

    cat > "${TEST_TEMP_DIR}/monitor_test.sh" << OUTEREOF
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export _BUILDGIT_TESTING=1

source "\${PROJECT_DIR}/buildgit"

# Override API functions with mocks
get_build_info() {
    ${get_build_info_body}
}

track_stage_changes() {
    ${track_stage_body}
}

# Use very short intervals for testing
MAX_BUILD_TIME=\${MAX_BUILD_TIME:-3}
POLL_INTERVAL=\${POLL_INTERVAL:-1}

# Run the function
_monitor_build "\$@"
OUTEREOF
    chmod +x "${TEST_TEMP_DIR}/monitor_test.sh"
}

# =============================================================================
# Test Cases: Function existence
# =============================================================================

# Spec: unify-follow-log-spec.md, Implementation Requirements
@test "monitor_build_function_exists" {
    # Match the function definition line (starts with _monitor_build() {)
    run grep -cE "^_monitor_build\(\)" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output "1"
}

@test "old_follow_monitor_removed" {
    run grep -c "_follow_monitor_build()" "${PROJECT_DIR}/buildgit"
    # Should NOT find the function definition (grep returns 1 if no match)
    assert_failure
}

@test "old_push_monitor_removed" {
    run grep -c "_push_monitor_build()" "${PROJECT_DIR}/buildgit"
    assert_failure
}

@test "old_build_monitor_removed" {
    run grep -c "_build_monitor()" "${PROJECT_DIR}/buildgit"
    assert_failure
}

# =============================================================================
# Test Cases: Behavior
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 3 (Stage Output)
@test "monitor_returns_0_on_completion" {
    _create_monitor_test_wrapper \
        'echo "{\"building\":false,\"result\":\"SUCCESS\"}"'

    run bash "${TEST_TEMP_DIR}/monitor_test.sh" "testjob" "42"
    assert_success
}

@test "monitor_returns_1_on_timeout" {
    _create_monitor_test_wrapper \
        'echo "{\"building\":true,\"result\":null}"'

    MAX_BUILD_TIME=2 POLL_INTERVAL=1 \
        run bash "${TEST_TEMP_DIR}/monitor_test.sh" "testjob" "42"
    assert_failure
}

@test "monitor_handles_api_failure" {
    # Return empty 5 times to trigger failure
    _create_monitor_test_wrapper \
        'echo ""'

    MAX_BUILD_TIME=30 POLL_INTERVAL=1 \
        run bash "${TEST_TEMP_DIR}/monitor_test.sh" "testjob" "42"
    assert_failure
}

@test "monitor_tracks_stages" {
    # Build completes on 2nd poll; track_stage_changes should be called
    # Use file-based counters because get_build_info runs in subshell via $()
    local call_count_file="${TEST_TEMP_DIR}/api_calls"
    local track_count_file="${TEST_TEMP_DIR}/track_calls"
    echo "0" > "$call_count_file"
    echo "0" > "$track_count_file"

    cat > "${TEST_TEMP_DIR}/monitor_test.sh" << OUTEREOF
#!/usr/bin/env bash
set -euo pipefail

export PROJECT_DIR="${PROJECT_DIR}"
export _BUILDGIT_TESTING=1

source "\${PROJECT_DIR}/buildgit"

CALL_COUNT_FILE="${call_count_file}"
TRACK_COUNT_FILE="${track_count_file}"

get_build_info() {
    local count=\$(cat "\$CALL_COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$CALL_COUNT_FILE"
    if [[ \$count -ge 2 ]]; then
        echo '{"building":false,"result":"SUCCESS"}'
    else
        echo '{"building":true,"result":null}'
    fi
}

track_stage_changes() {
    local count=\$(cat "\$TRACK_COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$TRACK_COUNT_FILE"
    echo '[]'
}

MAX_BUILD_TIME=10
POLL_INTERVAL=1

_monitor_build "\$@"
echo "track_calls=\$(cat "\$TRACK_COUNT_FILE")"
OUTEREOF
    chmod +x "${TEST_TEMP_DIR}/monitor_test.sh"

    run bash "${TEST_TEMP_DIR}/monitor_test.sh" "testjob" "42"
    assert_success
    # track_stage_changes should have been called at least once
    assert_output --partial "track_calls="
    local count
    count=$(echo "$output" | grep "track_calls=" | sed 's/track_calls=//')
    [[ "$count" -ge 1 ]]
}

# =============================================================================
# Test Cases: Callers updated
# =============================================================================

@test "push_calls_monitor_build" {
    run grep "_monitor_build" "${PROJECT_DIR}/buildgit"
    assert_success
    assert_output --partial "_monitor_build"
}

@test "no_references_to_old_functions" {
    # Ensure no call sites reference the old functions (excluding comments)
    run grep -E "^\s+_follow_monitor_build|^\s+_push_monitor_build|^\s+_build_monitor" "${PROJECT_DIR}/buildgit"
    assert_failure
}
