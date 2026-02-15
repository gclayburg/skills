#!/usr/bin/env bats

# Unit tests for parallel stages display
# Spec reference: bug-parallel-stages-display-spec.md

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Mock _timestamp for predictable output
    _timestamp() {
        echo "12:34:56"
    }
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# _detect_parallel_branches tests
# =============================================================================

@test "detect_parallel_branches_basic" {
    local console_output='[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] { (Branch: Build Handle)
Building handle...
[Pipeline] }
[Pipeline] { (Branch: Build SignalBoot)
Building signalboot...
[Pipeline] }
[Pipeline] }
[Pipeline] { (Verify Docker Images)'

    run _detect_parallel_branches "$console_output" "Trigger Component Builds"
    assert_success
    # Should return JSON array with both branch names
    local parsed
    parsed=$(echo "$output" | jq -r '.[]' | sort)
    echo "$parsed" | grep -q "Build Handle"
    echo "$parsed" | grep -q "Build SignalBoot"
}

@test "detect_parallel_branches_not_parallel" {
    local console_output='[Pipeline] { (Build)
Building project...
[Pipeline] }
[Pipeline] { (Test)
Testing...
[Pipeline] }'

    run _detect_parallel_branches "$console_output" "Build"
    assert_success
    # Should return empty string for non-parallel stage
    assert_output ""
}

@test "detect_parallel_branches_empty_console" {
    run _detect_parallel_branches "" "SomeStage"
    assert_success
    assert_output ""
}

@test "detect_parallel_branches_nonexistent_stage" {
    local console_output='[Pipeline] { (Build)
Building...
[Pipeline] }'

    run _detect_parallel_branches "$console_output" "NonExistent"
    assert_success
    assert_output ""
}

@test "detect_parallel_branches_three_branches" {
    local console_output='[Pipeline] { (Parallel Build)
[Pipeline] parallel
[Pipeline] { (Branch: Alpha)
alpha...
[Pipeline] }
[Pipeline] { (Branch: Beta)
beta...
[Pipeline] }
[Pipeline] { (Branch: Gamma)
gamma...
[Pipeline] }
[Pipeline] }'

    run _detect_parallel_branches "$console_output" "Parallel Build"
    assert_success
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -eq 3 ]]
    echo "$output" | jq -r '.[]' | grep -q "Alpha"
    echo "$output" | jq -r '.[]' | grep -q "Beta"
    echo "$output" | jq -r '.[]' | grep -q "Gamma"
}

@test "detect_parallel_branches_in_progress_wrapper_without_closing_brace" {
    # Simulates monitoring mode where wrapper block is still open and console
    # output ends before the final [Pipeline] } for the wrapper stage.
    local console_output='[Pipeline] { (parallel build test)
[Pipeline] parallel
[Pipeline] { (Branch: synconsole build)
[Pipeline] stage
[Pipeline] { (compile & bundle)
...still running...
[Pipeline] }
[Pipeline] { (Branch: visualsync track)
[Pipeline] stage
[Pipeline] { (compile & bundle)
...still running...'

    run _detect_parallel_branches "$console_output" "parallel build test"
    assert_success
    local parsed
    parsed=$(echo "$output" | jq -r '.[]')
    echo "$parsed" | grep -q "synconsole build"
    echo "$parsed" | grep -q "visualsync track"
}

@test "detect_parallel_branches_uses_matching_parallel_block_when_stage_name_repeats" {
    local console_output='[Pipeline] { (parallel build test)
not a parallel wrapper here
[Pipeline] }
[Pipeline] { (parallel build test)
[Pipeline] parallel
[Pipeline] { (Branch: synconsole build)
...
[Pipeline] }
[Pipeline] { (Branch: visualsync track)
...
[Pipeline] }
[Pipeline] { (Branch: dsltestharness)
...
[Pipeline] }
[Pipeline] }'

    run _detect_parallel_branches "$console_output" "parallel build test"
    assert_success
    local parsed
    parsed=$(echo "$output" | jq -r '.[]')
    echo "$parsed" | grep -q "synconsole build"
    echo "$parsed" | grep -q "visualsync track"
    echo "$parsed" | grep -q "dsltestharness"
}

# =============================================================================
# extract_stage_logs with Branch: prefix tests
# =============================================================================

@test "extract_stage_logs_finds_parallel_branch_logs" {
    local console_output='[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] { (Branch: Build Handle)
[Pipeline] sh
+ echo building handle
building handle
[Pipeline] }
[Pipeline] { (Branch: Build SignalBoot)
[Pipeline] sh
+ echo building signalboot
building signalboot
[Pipeline] }
[Pipeline] }'

    # Searching for "Build Handle" should find it via Branch: fallback
    run extract_stage_logs "$console_output" "Build Handle"
    assert_success
    assert_output --partial "building handle"
    refute_output --partial "building signalboot"
}

@test "extract_stage_logs_parallel_branch_signalboot" {
    local console_output='[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] { (Branch: Build Handle)
handle content
[Pipeline] }
[Pipeline] { (Branch: Build SignalBoot)
signalboot content
[Pipeline] }
[Pipeline] }'

    run extract_stage_logs "$console_output" "Build SignalBoot"
    assert_success
    assert_output --partial "signalboot content"
    refute_output --partial "handle content"
}

@test "extract_stage_logs_prefers_direct_match_over_branch" {
    # When a stage has a direct match (not Branch:), it should use that
    local console_output='[Pipeline] { (Build)
direct match content
[Pipeline] }'

    run extract_stage_logs "$console_output" "Build"
    assert_success
    assert_output --partial "direct match content"
}

# =============================================================================
# print_stage_line with parallel marker tests
# =============================================================================

@test "print_stage_line_with_parallel_marker" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "18:00:20"; }

    run print_stage_line "Build Handle->Checkout" "SUCCESS" 500 "  " "[buildagent9] " "║ "
    assert_success
    assert_output "[18:00:20] ℹ   Stage:   ║ [buildagent9   ] Build Handle->Checkout (<1s)"
}

@test "print_stage_line_parallel_branch_itself" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "18:00:41"; }

    run print_stage_line "Build Handle" "SUCCESS" 21000 "  " "[orchestrator1] " "║ "
    assert_success
    assert_output "[18:00:41] ℹ   Stage:   ║ [orchestrator1 ] Build Handle (21s)"
}

@test "print_stage_line_wrapper_no_marker" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "18:00:42"; }

    run print_stage_line "Trigger Component Builds" "SUCCESS" 21000 "" "[orchestrator1] " ""
    assert_success
    assert_output "[18:00:42] ℹ   Stage: [orchestrator1 ] Trigger Component Builds (21s)"
}

@test "print_stage_line_no_parallel_marker_by_default" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:34:56"; }

    # Without 6th arg, should produce same output as before
    run print_stage_line "Build" "SUCCESS" 15000
    assert_success
    assert_output "[12:34:56] ℹ   Stage: Build (15s)"
}

@test "print_stage_line_parallel_marker_with_failed" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "15:34:38"; }

    run print_stage_line "Build Handle" "FAILED" 9524 "  " "[agent8_sixcore] " "║ "
    assert_success
    assert_output --partial "║ [agent8_sixcore] Build Handle (9s)"
    assert_output --partial "← FAILED"
}

# =============================================================================
# _display_nested_stages_json with parallel annotations
# =============================================================================

@test "display_nested_stages_json_parallel_marker" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "18:00:20"; }

    local stages_json='[
        {"name": "Checkout", "status": "SUCCESS", "durationMillis": 500, "agent": "orch1", "nesting_depth": 0},
        {"name": "Build Handle->Compile", "status": "SUCCESS", "durationMillis": 10000, "agent": "agent9", "nesting_depth": 1, "parallel_branch": "Build Handle", "parallel_path": "1"},
        {"name": "Build Handle", "status": "SUCCESS", "durationMillis": 21000, "agent": "orch1", "nesting_depth": 0, "parallel_branch": "Build Handle", "parallel_wrapper": "Trigger Component Builds", "parallel_path": "1", "has_downstream": true},
        {"name": "Trigger Component Builds", "status": "SUCCESS", "durationMillis": 21114, "agent": "orch1", "nesting_depth": 0, "is_parallel_wrapper": true, "parallel_branches": ["Build Handle"]}
    ]'

    run _display_nested_stages_json "$stages_json" "false"
    assert_success
    # Checkout should NOT have parallel marker
    assert_output --partial "Stage: [orch1         ] Checkout (<1s)"
    # Nested stage of parallel branch should have numbered marker
    assert_output --partial "║1 [agent9        ] Build Handle->Compile"
    # Parallel branch itself should have numbered marker
    assert_output --partial "║1 [orch1         ] Build Handle (21s)"
    # Wrapper stage should NOT have ║
    assert_output --partial "Stage: [orch1         ] Trigger Component Builds (21s)"
}

@test "display_nested_stages_json_nested_parallel_path_marker" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "18:00:20"; }

    local stages_json='[
        {"name": "Nested Branch Stage", "status": "SUCCESS", "durationMillis": 500, "agent": "agent14", "nesting_depth": 1, "parallel_path": "3.1"}
    ]'

    run _display_nested_stages_json "$stages_json" "false"
    assert_success
    assert_output --partial "║3.1 [agent14       ] Nested Branch Stage (<1s)"
}

@test "get_nested_stages_preserves_nested_parallel_paths_under_parent_parallel_branch" {
    get_all_stages() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo '[
                {"name":"parallel build test","status":"SUCCESS","startTimeMillis":0,"durationMillis":1000},
                {"name":"synconsole build","status":"SUCCESS","startTimeMillis":0,"durationMillis":900}
            ]'
        elif [[ "$job" == "synconsole" ]]; then
            echo '[
                {"name":"tests","status":"SUCCESS","startTimeMillis":0,"durationMillis":600},
                {"name":"back front tests","status":"SUCCESS","startTimeMillis":0,"durationMillis":500},
                {"name":"panorama","status":"SUCCESS","startTimeMillis":0,"durationMillis":500}
            ]'
        else
            echo '[]'
        fi
    }

    get_console_output() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo 'Running on orchestrator1 in /workspace
[Pipeline] { (parallel build test)
[Pipeline] parallel
[Pipeline] { (Branch: synconsole build)
Starting building: synconsole #12
[Pipeline] }
[Pipeline] }'
        elif [[ "$job" == "synconsole" ]]; then
            echo 'Running on agent7 in /workspace
[Pipeline] { (tests)
[Pipeline] parallel
[Pipeline] { (Branch: back front tests)
echo one
[Pipeline] }
[Pipeline] { (Branch: panorama)
echo two
[Pipeline] }
[Pipeline] }'
        else
            echo ''
        fi
    }

    local result
    result=$(_get_nested_stages "parent-job" "1")

    # Parent parallel branch path should be 1
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "synconsole build") | .parallel_path')" == "1" ]]
    # Nested parallel branches should keep nested numbering, not collapse to parent path
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "synconsole build->back front tests") | .parallel_path')" == "1.1" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "synconsole build->panorama") | .parallel_path')" == "1.2" ]]
}

# =============================================================================
# Integration: no parallel stages unaffected
# =============================================================================

@test "print_stage_line_backward_compatible_no_sixth_arg" {
    NO_COLOR=1 source "${PROJECT_DIR}/lib/jenkins-common.sh"
    _timestamp() { echo "12:34:56"; }

    # Existing callers that pass only 5 args should still work
    run print_stage_line "Deploy" "SUCCESS" 5000 "  " "[agent1] "
    assert_success
    assert_output "[12:34:56] ℹ   Stage:   [agent1        ] Deploy (5s)"
}

# =============================================================================
# Monitoring mode deferral tests for _track_nested_stage_changes
# Spec reference: bug2026-02-14-monitoring-missing-stages-spec.md
# =============================================================================

@test "wrapper_deferred_until_branches_terminal" {
    # Poll 1: wrapper is SUCCESS but one branch is IN_PROGRESS → wrapper should NOT print
    # Poll 2: both branches terminal → wrapper prints
    local poll_count_file="${TEST_TEMP_DIR}/poll_count"
    echo "0" > "$poll_count_file"

    get_all_stages() {
        echo '[{"name":"parallel build test","status":"SUCCESS","startTimeMillis":0,"durationMillis":245000}]'
    }
    get_console_output() { echo "Running on agent6 in /ws"; }

    _get_nested_stages() {
        local count
        count=$(cat "$poll_count_file")
        count=$((count + 1))
        echo "$count" > "$poll_count_file"

        if [[ $count -eq 1 ]]; then
            echo '[
                {"name":"branch1","status":"SUCCESS","durationMillis":120000,"agent":"agent6","nesting_depth":1,"parallel_path":"1","parallel_branch":"branch1"},
                {"name":"branch2","status":"IN_PROGRESS","durationMillis":0,"agent":"agent7","nesting_depth":1,"parallel_path":"2","parallel_branch":"branch2"},
                {"name":"parallel build test","status":"SUCCESS","durationMillis":2000,"agent":"agent6","nesting_depth":0,"is_parallel_wrapper":true,"parallel_branches":["branch1","branch2"]}
            ]'
        else
            echo '[
                {"name":"branch1","status":"SUCCESS","durationMillis":120000,"agent":"agent6","nesting_depth":1,"parallel_path":"1","parallel_branch":"branch1"},
                {"name":"branch2","status":"SUCCESS","durationMillis":200000,"agent":"agent7","nesting_depth":1,"parallel_path":"2","parallel_branch":"branch2"},
                {"name":"parallel build test","status":"SUCCESS","durationMillis":245000,"agent":"agent6","nesting_depth":0,"is_parallel_wrapper":true,"parallel_branches":["branch1","branch2"]}
            ]'
        fi
    }

    # Poll 1 — capture stdout (state) and stderr (printed output) in one call
    local state1 stderr1_file="${TEST_TEMP_DIR}/stderr1"
    state1=$(_track_nested_stage_changes "test-job" "42" "[]" "false" 2>"$stderr1_file")
    local stderr1
    stderr1=$(cat "$stderr1_file")

    # Wrapper should NOT be printed on poll 1 (branch2 still IN_PROGRESS)
    [[ "$stderr1" != *"parallel build test"* ]]
    # branch1 should print (it's terminal and simple)
    [[ "$stderr1" == *"branch1"* ]]

    # Poll 2 - pass state from poll 1
    local stderr2_file="${TEST_TEMP_DIR}/stderr2"
    state2=$(_track_nested_stage_changes "test-job" "42" "$state1" "false" 2>"$stderr2_file")
    local stderr2
    stderr2=$(cat "$stderr2_file")

    # Now wrapper should print
    [[ "$stderr2" == *"parallel build test"* ]]
}

@test "downstream_stage_deferred_until_children_appear" {
    # Poll 1: parent has has_downstream=true but no children → defer
    # Poll 2: children appear → parent prints
    local poll_count_file="${TEST_TEMP_DIR}/poll_count"
    echo "0" > "$poll_count_file"

    get_all_stages() {
        echo '[{"name":"Build Handle","status":"SUCCESS","startTimeMillis":0,"durationMillis":38000}]'
    }
    get_console_output() { echo "Running on agent1 in /ws"; }

    _get_nested_stages() {
        local count
        count=$(cat "$poll_count_file")
        count=$((count + 1))
        echo "$count" > "$poll_count_file"

        if [[ $count -eq 1 ]]; then
            echo '[
                {"name":"Build Handle","status":"SUCCESS","durationMillis":38000,"agent":"agent1","nesting_depth":0,"has_downstream":true}
            ]'
        else
            echo '[
                {"name":"Build Handle->Compile","status":"SUCCESS","durationMillis":10000,"agent":"buildagent9","nesting_depth":1},
                {"name":"Build Handle","status":"SUCCESS","durationMillis":38000,"agent":"agent1","nesting_depth":0,"has_downstream":true}
            ]'
        fi
    }

    # Poll 1 — capture stdout (state) and stderr (printed output) in one call
    local state1 stderr1_file="${TEST_TEMP_DIR}/stderr1"
    state1=$(_track_nested_stage_changes "test-job" "42" "[]" "false" 2>"$stderr1_file")
    local stderr1
    stderr1=$(cat "$stderr1_file")

    # Build Handle should NOT print (no children yet)
    [[ "$stderr1" != *"Build Handle"* ]]

    # Poll 2
    local stderr2_file="${TEST_TEMP_DIR}/stderr2"
    local state2
    state2=$(_track_nested_stage_changes "test-job" "42" "$state1" "false" 2>"$stderr2_file")
    local stderr2
    stderr2=$(cat "$stderr2_file")

    # Now Build Handle should print, along with its child
    [[ "$stderr2" == *"Build Handle->Compile"* ]]
    [[ "$stderr2" == *"Build Handle (38s)"* ]]
}

@test "simple_stages_print_immediately" {
    # Regression: stages without wrapper/downstream flags print on first terminal
    get_all_stages() {
        echo '[
            {"name":"Checkout","status":"SUCCESS","startTimeMillis":0,"durationMillis":3000},
            {"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":15000}
        ]'
    }
    get_console_output() { echo "Running on agent1 in /ws"; }

    _get_nested_stages() {
        echo '[
            {"name":"Checkout","status":"SUCCESS","durationMillis":3000,"agent":"agent1","nesting_depth":0},
            {"name":"Build","status":"SUCCESS","durationMillis":15000,"agent":"agent1","nesting_depth":0}
        ]'
    }

    local stderr_output
    stderr_output=$(_track_nested_stage_changes "test-job" "42" "[]" "false" 2>&1 >/dev/null)

    # Both stages should print immediately
    [[ "$stderr_output" == *"Checkout (3s)"* ]]
    [[ "$stderr_output" == *"Build (15s)"* ]]
}

@test "deferred_wrapper_uses_correct_duration" {
    # Wrapper should print with the aggregate duration, not the premature API duration
    get_all_stages() {
        echo '[{"name":"parallel build test","status":"SUCCESS","startTimeMillis":0,"durationMillis":245000}]'
    }
    get_console_output() { echo "Running on agent6 in /ws"; }

    _get_nested_stages() {
        echo '[
            {"name":"branch1","status":"SUCCESS","durationMillis":120000,"agent":"agent6","nesting_depth":1,"parallel_path":"1","parallel_branch":"branch1"},
            {"name":"branch2","status":"SUCCESS","durationMillis":200000,"agent":"agent7","nesting_depth":1,"parallel_path":"2","parallel_branch":"branch2"},
            {"name":"parallel build test","status":"SUCCESS","durationMillis":245000,"agent":"agent6","nesting_depth":0,"is_parallel_wrapper":true,"parallel_branches":["branch1","branch2"]}
        ]'
    }

    local stderr_output
    stderr_output=$(_track_nested_stage_changes "test-job" "42" "[]" "false" 2>&1 >/dev/null)

    # Wrapper should show the aggregate duration (245s = 4m 5s), not 2s
    [[ "$stderr_output" == *"parallel build test (4m 5s)"* ]]
}
