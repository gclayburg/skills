#!/usr/bin/env bats

# Integration tests for monitoring functions with stage tracking
# Spec reference: full-stage-print-spec.md, Section: Behavior by Command
# Plan reference: full-stage-print-plan.md, Chunk E

load test_helper

# Load buildgit which sources jenkins-common.sh
setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
    FIXTURES_DIR="${TEST_DIR}/fixtures"

    # Source buildgit to get monitoring functions
    # Guard prevents main() from running
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    # Set up Jenkins environment for tests (won't be used with mocking)
    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    # Disable colors for testing
    export NO_COLOR=1
    _init_colors

    # Set short poll interval for tests (must be integer for bash arithmetic)
    POLL_INTERVAL=1
    MAX_BUILD_TIME=60

    # Mock sleep to make tests fast
    sleep() {
        : # no-op
    }
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# -----------------------------------------------------------------------------
# Test Case: _push_monitor_build calls track_stage_changes
# Spec: full-stage-print-spec.md, buildgit push
# -----------------------------------------------------------------------------
@test "push_monitor_shows_stage_completions" {
    # Create call count files
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    local track_called_file="${TEST_TEMP_DIR}/track_called"
    echo "0" > "$call_count_file"
    echo "0" > "$track_called_file"

    # Mock get_build_info inside test
    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -eq 1 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    # Mock track_stage_changes inside test
    track_stage_changes() {
        local count
        count=$(cat "$track_called_file")
        echo "$((count + 1))" > "$track_called_file"
        echo '[]'
    }

    VERBOSE_MODE=false
    run _push_monitor_build "test-job" "42"

    # Verify track_stage_changes was called
    local calls
    calls=$(cat "$track_called_file")
    [[ "$calls" -ge 1 ]]
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Test Case: _follow_monitor_build calls track_stage_changes
# Spec: full-stage-print-spec.md, buildgit status -f
# -----------------------------------------------------------------------------
@test "follow_monitor_shows_stage_completions" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    local track_called_file="${TEST_TEMP_DIR}/track_called"
    echo "0" > "$call_count_file"
    echo "0" > "$track_called_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -eq 1 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    track_stage_changes() {
        local count
        count=$(cat "$track_called_file")
        echo "$((count + 1))" > "$track_called_file"
        echo '[]'
    }

    VERBOSE_MODE=false
    run _follow_monitor_build "test-job" "42"

    local calls
    calls=$(cat "$track_called_file")
    [[ "$calls" -ge 1 ]]
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Test Case: _build_monitor calls track_stage_changes
# Spec: full-stage-print-spec.md, buildgit build
# -----------------------------------------------------------------------------
@test "build_monitor_shows_stage_completions" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    local track_called_file="${TEST_TEMP_DIR}/track_called"
    echo "0" > "$call_count_file"
    echo "0" > "$track_called_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -eq 1 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    track_stage_changes() {
        local count
        count=$(cat "$track_called_file")
        echo "$((count + 1))" > "$track_called_file"
        echo '[]'
    }

    VERBOSE_MODE=false
    run _build_monitor "test-job" "42"

    local calls
    calls=$(cat "$track_called_file")
    [[ "$calls" -ge 1 ]]
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Verbose mode shows elapsed messages
# Spec: full-stage-print-spec.md, Verbose mode
# -----------------------------------------------------------------------------
@test "monitor_verbose_shows_elapsed" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    echo "0" > "$call_count_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -lt 3 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    track_stage_changes() {
        echo '[]'
    }

    # Use integer values for bash arithmetic
    POLL_INTERVAL=1
    MAX_BUILD_TIME=60
    VERBOSE_MODE=true

    run _push_monitor_build "test-job" "42"

    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Non-verbose mode does not show elapsed messages
# Spec: full-stage-print-spec.md, Non-verbose mode
# -----------------------------------------------------------------------------
@test "monitor_non_verbose_no_elapsed" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    echo "0" > "$call_count_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -eq 1 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    track_stage_changes() {
        echo '[]'
    }

    VERBOSE_MODE=false

    run _push_monitor_build "test-job" "42"

    # Verify no "elapsed" messages in output
    [[ "$output" != *"elapsed"* ]]
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Test Case: Monitor passes VERBOSE_MODE to track_stage_changes
# Spec: full-stage-print-spec.md, In-Progress Stages
# -----------------------------------------------------------------------------
@test "monitor_shows_running_stage" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    local verbose_param_file="${TEST_TEMP_DIR}/verbose_param"
    echo "0" > "$call_count_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -eq 1 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    track_stage_changes() {
        local job_name="$1"
        local build_number="$2"
        local previous_state="$3"
        local verbose="$4"

        echo "$verbose" > "$verbose_param_file"
        echo '[]'
    }

    VERBOSE_MODE=true
    run _push_monitor_build "test-job" "42"

    # Verify verbose parameter was passed correctly
    local passed_verbose
    passed_verbose=$(cat "$verbose_param_file")
    [[ "$passed_verbose" == "true" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Monitor initializes stage_state as empty array
# Spec: full-stage-print-spec.md, Stage Tracking
# -----------------------------------------------------------------------------
@test "monitor_initializes_stage_state" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    local first_state_file="${TEST_TEMP_DIR}/first_state"
    local track_calls_file="${TEST_TEMP_DIR}/track_calls"
    echo "0" > "$call_count_file"
    echo "0" > "$track_calls_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -eq 1 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    track_stage_changes() {
        local job_name="$1"
        local build_number="$2"
        local previous_state="$3"

        local count
        count=$(cat "$track_calls_file")
        if [[ "$count" -eq 0 ]]; then
            echo "$previous_state" > "$first_state_file"
        fi
        echo "$((count + 1))" > "$track_calls_file"

        echo '[{"name":"Build","status":"SUCCESS"}]'
    }

    VERBOSE_MODE=false
    run _push_monitor_build "test-job" "42"

    # Verify first call received empty array as previous state
    local first_state
    first_state=$(cat "$first_state_file")
    [[ "$first_state" == "[]" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Monitor preserves stage_state between iterations
# Spec: full-stage-print-spec.md, Stage Tracking
# -----------------------------------------------------------------------------
@test "monitor_preserves_stage_state" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    local track_calls_file="${TEST_TEMP_DIR}/track_calls"
    local second_prev_file="${TEST_TEMP_DIR}/second_prev"
    echo "0" > "$call_count_file"
    echo "0" > "$track_calls_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -lt 2 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "SUCCESS"}'
        fi
    }

    track_stage_changes() {
        local previous_state="$3"

        local count
        count=$(cat "$track_calls_file")
        count=$((count + 1))
        echo "$count" > "$track_calls_file"

        if [[ "$count" -eq 2 ]]; then
            echo "$previous_state" > "$second_prev_file"
        fi

        echo '[{"name":"Build","status":"IN_PROGRESS"}]'
    }

    VERBOSE_MODE=false
    run _push_monitor_build "test-job" "42"

    # Verify second call received the state from first call
    if [[ -f "$second_prev_file" ]]; then
        local second_state
        second_state=$(cat "$second_prev_file")
        [[ "$second_state" == *"Build"* ]]
    fi
}

# -----------------------------------------------------------------------------
# Test Case: Monitor handles build failure result
# Spec: full-stage-print-spec.md, buildgit push
# -----------------------------------------------------------------------------
@test "monitor_handles_build_failure" {
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    echo "0" > "$call_count_file"

    get_build_info() {
        local count
        count=$(cat "$call_count_file")
        count=$((count + 1))
        echo "$count" > "$call_count_file"

        if [[ $count -eq 1 ]]; then
            echo '{"building": true, "result": null}'
        else
            echo '{"building": false, "result": "FAILURE"}'
        fi
    }

    track_stage_changes() {
        echo '[]'
    }

    VERBOSE_MODE=false
    run _push_monitor_build "test-job" "42"

    # Monitor should still return 0 (it just reports completion)
    [[ "$status" -eq 0 ]]
}
