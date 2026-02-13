#!/usr/bin/env bats

# Tests for bug fix: show all stages without "(running)" text
# Spec reference: bug-show-all-stages.md
# Fixes: (1) "(running)" shown for completed stages in initial display
#        (2) Missing stages when build completes quickly

load test_helper

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # Source jenkins-common.sh for display functions
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Set up Jenkins environment
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
# Test Cases: _display_completed_stages (Fix 1)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Completed stages are shown
# Spec: bug-show-all-stages.md - completed stages should show duration
# -----------------------------------------------------------------------------
@test "display_completed_stages_shows_success_stages" {
    get_all_stages() {
        echo '[
            {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Build","status":"SUCCESS","durationMillis":3000}
        ]'
    }

    run _display_completed_stages "test-job" "42"

    assert_success
    assert_output --partial "Stage: Checkout SCM"
    assert_output --partial "Stage: Build"
}

# -----------------------------------------------------------------------------
# Test Case: IN_PROGRESS stages are NOT shown (no "(running)")
# Spec: bug-show-all-stages.md - should never show 'running'
# -----------------------------------------------------------------------------
@test "display_completed_stages_skips_in_progress" {
    get_all_stages() {
        echo '[
            {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Agent Setup","status":"IN_PROGRESS","durationMillis":0},
            {"name":"Build","status":"NOT_EXECUTED","durationMillis":0}
        ]'
    }

    run _display_completed_stages "test-job" "42"

    assert_success
    assert_output --partial "Stage: Checkout SCM"
    refute_output --partial "Agent Setup"
    refute_output --partial "running"
    refute_output --partial "Build"
}

# -----------------------------------------------------------------------------
# Test Case: FAILED stages are shown
# Spec: bug-show-all-stages.md - all completed statuses should appear
# -----------------------------------------------------------------------------
@test "display_completed_stages_shows_failed" {
    get_all_stages() {
        echo '[
            {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Build","status":"FAILED","durationMillis":5000}
        ]'
    }

    run _display_completed_stages "test-job" "42"

    assert_success
    assert_output --partial "Stage: Build"
    assert_output --partial "FAILED"
}

# -----------------------------------------------------------------------------
# Test Case: NOT_EXECUTED stages are not shown
# Spec: bug-show-all-stages.md - only show stages with a final status
# -----------------------------------------------------------------------------
@test "display_completed_stages_skips_not_executed" {
    get_all_stages() {
        echo '[
            {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Deploy","status":"NOT_EXECUTED","durationMillis":0}
        ]'
    }

    run _display_completed_stages "test-job" "42"

    assert_success
    assert_output --partial "Stage: Checkout SCM"
    refute_output --partial "Deploy"
    refute_output --partial "not executed"
}

# -----------------------------------------------------------------------------
# Test Case: _display_completed_stages saves stage JSON to global
# Spec: bug-show-all-stages.md - monitor needs banner state for initialization
# -----------------------------------------------------------------------------
@test "display_completed_stages_sets_banner_stages_json" {
    get_all_stages() {
        echo '[
            {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Agent Setup","status":"IN_PROGRESS","durationMillis":0}
        ]'
    }

    _display_completed_stages "test-job" "42"

    # Global should contain the full stages JSON (including IN_PROGRESS)
    [[ "$_BANNER_STAGES_JSON" == *"Checkout SCM"* ]]
    [[ "$_BANNER_STAGES_JSON" == *"IN_PROGRESS"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Mixed statuses - only completed shown
# Spec: bug-show-all-stages.md - matches the exact bug scenario
# -----------------------------------------------------------------------------
@test "display_completed_stages_mixed_statuses" {
    get_all_stages() {
        echo '[
            {"name":"Declarative: Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Declarative: Agent Setup","status":"IN_PROGRESS","durationMillis":0},
            {"name":"Initialize Submodules","status":"SUCCESS","durationMillis":10000}
        ]'
    }

    run _display_completed_stages "test-job" "42"

    assert_success
    assert_output --partial "Stage: Declarative: Checkout SCM"
    assert_output --partial "Stage: Initialize Submodules"
    refute_output --partial "Agent Setup"
    refute_output --partial "running"
}

# =============================================================================
# Test Cases: track_stage_changes NOT_EXECUTED → completed (Fix 2)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Stage going NOT_EXECUTED → SUCCESS is printed
# Spec: bug-show-all-stages.md - fast stages that appear already completed
# -----------------------------------------------------------------------------
@test "track_stage_changes_prints_not_executed_to_success" {
    local previous='[{"name":"Checkout","status":"SUCCESS","durationMillis":500}]'

    get_all_stages() {
        echo '[
            {"name":"Checkout","status":"SUCCESS","durationMillis":500},
            {"name":"Build","status":"SUCCESS","durationMillis":3000}
        ]'
    }

    run bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        export NO_COLOR=1
        _init_colors
        get_all_stages() {
            echo '[{\"name\":\"Checkout\",\"status\":\"SUCCESS\",\"durationMillis\":500},{\"name\":\"Build\",\"status\":\"SUCCESS\",\"durationMillis\":3000}]'
        }
        track_stage_changes 'test-job' '42' '$previous' 'false' 2>&1 1>/dev/null
    "

    assert_success
    # Build should be printed (NOT_EXECUTED → SUCCESS)
    assert_output --partial "Stage: Build"
}

# -----------------------------------------------------------------------------
# Test Case: Already-known completed stages are NOT re-printed
# Spec: bug-show-all-stages.md - no duplicate stage lines
# -----------------------------------------------------------------------------
@test "track_stage_changes_no_duplicate_completed" {
    local previous='[{"name":"Checkout","status":"SUCCESS","durationMillis":500}]'

    run bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        export NO_COLOR=1
        _init_colors
        get_all_stages() {
            echo '[{\"name\":\"Checkout\",\"status\":\"SUCCESS\",\"durationMillis\":500}]'
        }
        track_stage_changes 'test-job' '42' '$previous' 'false' 2>&1 1>/dev/null
    "

    assert_success
    # Checkout should NOT be re-printed (was already SUCCESS in previous)
    refute_output --partial "Stage: Checkout"
}

# -----------------------------------------------------------------------------
# Test Case: Multiple fast stages all printed
# Spec: bug-show-all-stages.md - all 6 stages must appear
# -----------------------------------------------------------------------------
@test "track_stage_changes_prints_multiple_fast_stages" {
    local previous='[{"name":"Stage1","status":"SUCCESS","durationMillis":500},{"name":"Stage2","status":"IN_PROGRESS","durationMillis":0}]'

    run bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        export NO_COLOR=1
        _init_colors
        get_all_stages() {
            echo '[{\"name\":\"Stage1\",\"status\":\"SUCCESS\",\"durationMillis\":500},{\"name\":\"Stage2\",\"status\":\"SUCCESS\",\"durationMillis\":1000},{\"name\":\"Stage3\",\"status\":\"SUCCESS\",\"durationMillis\":2000},{\"name\":\"Stage4\",\"status\":\"SUCCESS\",\"durationMillis\":500}]'
        }
        track_stage_changes 'test-job' '42' '$previous' 'false' 2>&1 1>/dev/null
    "

    assert_success
    # Stage1: SUCCESS→SUCCESS, skip
    refute_output --partial "Stage: Stage1"
    # Stage2: IN_PROGRESS→SUCCESS, print
    assert_output --partial "Stage: Stage2"
    # Stage3: NOT_EXECUTED→SUCCESS, print
    assert_output --partial "Stage: Stage3"
    # Stage4: NOT_EXECUTED→SUCCESS, print
    assert_output --partial "Stage: Stage4"
}

# =============================================================================
# Test Cases: _monitor_build uses banner state (Fix 3)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Monitor uses _BANNER_STAGES_JSON for initial state
# Spec: bug-show-all-stages.md - monitor should use banner state
# -----------------------------------------------------------------------------
@test "monitor_build_uses_banner_stages_json" {
    # Source buildgit for _monitor_build
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    local first_prev_file="${TEST_TEMP_DIR}/first_prev"
    local call_count_file="${TEST_TEMP_DIR}/call_count"
    echo "0" > "$call_count_file"

    # Set banner stages (simulating what _display_completed_stages sets)
    _BANNER_STAGES_JSON='[{"name":"Checkout","status":"SUCCESS","durationMillis":500}]'

    get_build_info() {
        echo '{"building": false, "result": "SUCCESS"}'
    }

    _track_nested_stage_changes() {
        local previous_state="$3"
        local count
        count=$(cat "$call_count_file")
        if [[ "$count" -eq 0 ]]; then
            echo "$previous_state" > "$first_prev_file"
        fi
        echo "$((count + 1))" > "$call_count_file"
        echo "$previous_state"
    }

    sleep() { :; }
    POLL_INTERVAL=1
    MAX_BUILD_TIME=60
    VERBOSE_MODE=false

    run _monitor_build "test-job" "42"

    assert_success
    # Verify the first call to _track_nested_stage_changes received the banner state
    local first_prev
    first_prev=$(cat "$first_prev_file")
    [[ "$first_prev" == *"Checkout"* ]]
    [[ "$first_prev" == *"SUCCESS"* ]]
}

# -----------------------------------------------------------------------------
# Test Case: Monitor resets _BANNER_STAGES_JSON after reading
# Spec: bug-show-all-stages.md - prevent stale state
# -----------------------------------------------------------------------------
@test "monitor_build_resets_banner_stages_json" {
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    local reset_check_file="${TEST_TEMP_DIR}/reset_check"

    _BANNER_STAGES_JSON='[{"name":"Checkout","status":"SUCCESS","durationMillis":500}]'

    get_build_info() {
        # Capture _BANNER_STAGES_JSON state during execution
        echo "$_BANNER_STAGES_JSON" > "$reset_check_file"
        echo '{"building": false, "result": "SUCCESS"}'
    }

    _track_nested_stage_changes() {
        echo '[]'
    }

    sleep() { :; }
    POLL_INTERVAL=1
    MAX_BUILD_TIME=60
    VERBOSE_MODE=false

    _monitor_build "test-job" "42"

    # After _monitor_build returns, _BANNER_STAGES_JSON should be reset
    [[ -z "$_BANNER_STAGES_JSON" || "$_BANNER_STAGES_JSON" == "" ]]
}

# -----------------------------------------------------------------------------
# Test Case: Monitor tracks stages before checking completion
# Spec: bug-show-all-stages.md - final iteration catches transitions
# -----------------------------------------------------------------------------
@test "monitor_build_tracks_stages_before_completion_check" {
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    local track_called_file="${TEST_TEMP_DIR}/track_called"
    echo "0" > "$track_called_file"

    get_build_info() {
        # Build already complete on first poll
        echo '{"building": false, "result": "SUCCESS"}'
    }

    _track_nested_stage_changes() {
        local count
        count=$(cat "$track_called_file")
        echo "$((count + 1))" > "$track_called_file"
        echo '[]'
    }

    sleep() { :; }
    POLL_INTERVAL=1
    MAX_BUILD_TIME=60
    VERBOSE_MODE=false
    _BANNER_STAGES_JSON=""

    run _monitor_build "test-job" "42"

    assert_success
    # _track_nested_stage_changes should have been called at least once
    # even though build was already complete
    local calls
    calls=$(cat "$track_called_file")
    [[ "$calls" -ge 1 ]]
}

# =============================================================================
# Test Cases: End-to-end scenario (all stages shown)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Case: Full scenario - all stages visible when build completes quickly
# Spec: bug-show-all-stages.md - the exact bug scenario
# -----------------------------------------------------------------------------
@test "all_stages_shown_for_fast_completing_build" {
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    local api_call_count_file="${TEST_TEMP_DIR}/api_calls"
    echo "0" > "$api_call_count_file"

    # Banner stages: 2 complete, 1 in-progress, 3 not started
    _BANNER_STAGES_JSON='[
        {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
        {"name":"Agent Setup","status":"SUCCESS","durationMillis":1000},
        {"name":"Init Submodules","status":"IN_PROGRESS","durationMillis":0}
    ]'

    get_build_info() {
        # Build complete on first poll
        echo '{"building": false, "result": "SUCCESS"}'
    }

    # On the first (and only) poll, all 6 stages are now complete
    get_all_stages() {
        echo '[
            {"name":"Checkout SCM","status":"SUCCESS","durationMillis":500},
            {"name":"Agent Setup","status":"SUCCESS","durationMillis":1000},
            {"name":"Init Submodules","status":"SUCCESS","durationMillis":10000},
            {"name":"Build","status":"SUCCESS","durationMillis":500},
            {"name":"Unit Tests","status":"SUCCESS","durationMillis":2000},
            {"name":"Deploy","status":"SUCCESS","durationMillis":500}
        ]'
    }

    sleep() { :; }
    POLL_INTERVAL=1
    MAX_BUILD_TIME=60
    VERBOSE_MODE=false

    # Capture stderr (where track_stage_changes prints)
    run bash -c "
        export _BUILDGIT_TESTING=1
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        source '${PROJECT_DIR}/buildgit'
        export NO_COLOR=1
        _init_colors

        _BANNER_STAGES_JSON='[{\"name\":\"Checkout SCM\",\"status\":\"SUCCESS\",\"durationMillis\":500},{\"name\":\"Agent Setup\",\"status\":\"SUCCESS\",\"durationMillis\":1000},{\"name\":\"Init Submodules\",\"status\":\"IN_PROGRESS\",\"durationMillis\":0}]'

        get_build_info() {
            echo '{\"building\": false, \"result\": \"SUCCESS\"}'
        }

        get_all_stages() {
            echo '[{\"name\":\"Checkout SCM\",\"status\":\"SUCCESS\",\"durationMillis\":500},{\"name\":\"Agent Setup\",\"status\":\"SUCCESS\",\"durationMillis\":1000},{\"name\":\"Init Submodules\",\"status\":\"SUCCESS\",\"durationMillis\":10000},{\"name\":\"Build\",\"status\":\"SUCCESS\",\"durationMillis\":500},{\"name\":\"Unit Tests\",\"status\":\"SUCCESS\",\"durationMillis\":2000},{\"name\":\"Deploy\",\"status\":\"SUCCESS\",\"durationMillis\":500}]'
        }

        sleep() { :; }
        POLL_INTERVAL=1
        MAX_BUILD_TIME=60
        VERBOSE_MODE=false

        _monitor_build 'test-job' '42' 2>&1
    "

    assert_success
    # Checkout SCM: was SUCCESS in banner state, still SUCCESS → NOT printed (already shown by banner)
    refute_output --partial "Stage: Checkout SCM"
    # Agent Setup: was SUCCESS in banner state, still SUCCESS → NOT printed
    refute_output --partial "Stage: Agent Setup"
    # Init Submodules: was IN_PROGRESS, now SUCCESS → PRINTED
    assert_output --partial "Stage: Init Submodules"
    # Build: was NOT_EXECUTED, now SUCCESS → PRINTED
    assert_output --partial "Stage: Build"
    # Unit Tests: was NOT_EXECUTED, now SUCCESS → PRINTED
    assert_output --partial "Stage: Unit Tests"
    # Deploy: was NOT_EXECUTED, now SUCCESS → PRINTED
    assert_output --partial "Stage: Deploy"

    # No "(running)" text anywhere
    refute_output --partial "running"
}
