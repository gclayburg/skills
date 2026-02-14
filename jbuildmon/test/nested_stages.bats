#!/usr/bin/env bats

# Unit tests for nested/downstream stage display functions
# Spec reference: nested-jobs-display-spec.md

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Set up Jenkins environment
    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    # Disable colors for testing
    export NO_COLOR=1
    _init_colors

    # Mock _timestamp for predictable output
    _timestamp() { echo "18:00:18"; }
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# Test Cases: _extract_agent_name
# =============================================================================

@test "extract_agent_name_from_console" {
    local console="Started by user admin
Running on buildagent9 in /var/jenkins/workspace/myjob
[Pipeline] Start of Pipeline"

    local agent
    agent=$(_extract_agent_name "$console")
    [[ "$agent" == "buildagent9" ]]
}

@test "extract_agent_name_empty_console" {
    local agent
    agent=$(_extract_agent_name "")
    [[ -z "$agent" ]]
}

@test "extract_agent_name_no_running_on_line" {
    local console="Started by user admin
[Pipeline] Start of Pipeline"

    local agent
    agent=$(_extract_agent_name "$console")
    [[ -z "$agent" ]]
}

@test "extract_agent_name_with_workspace_path" {
    local console="Running on orchestrator1 in /home/jenkins/agent/workspace/ralph1"

    local agent
    agent=$(_extract_agent_name "$console")
    [[ "$agent" == "orchestrator1" ]]
}

# =============================================================================
# Test Cases: _map_stages_to_downstream
# =============================================================================

@test "map_stages_to_downstream_single_match" {
    local console='[Pipeline] { (Build Handle)
[Pipeline] build
Starting building: phandlemono-handle #42
[Pipeline] }
[Pipeline] { (Deploy)
echo deploying
[Pipeline] }'

    local stages='[
        {"name":"Build Handle","status":"FAILED","durationMillis":38000},
        {"name":"Deploy","status":"NOT_EXECUTED","durationMillis":0}
    ]'

    local result
    result=$(_map_stages_to_downstream "$console" "$stages")

    [[ $(echo "$result" | jq -r '.["Build Handle"].job') == "phandlemono-handle" ]]
    [[ $(echo "$result" | jq -r '.["Build Handle"].build') == "42" ]]
    # Deploy stage should NOT have a downstream mapping
    [[ $(echo "$result" | jq -r '.Deploy // empty') == "" ]]
}

@test "map_stages_to_downstream_no_downstream" {
    local console='[Pipeline] { (Build)
echo building
[Pipeline] }
[Pipeline] { (Test)
echo testing
[Pipeline] }'

    local stages='[
        {"name":"Build","status":"SUCCESS","durationMillis":5000},
        {"name":"Test","status":"SUCCESS","durationMillis":10000}
    ]'

    local result
    result=$(_map_stages_to_downstream "$console" "$stages")

    [[ $(echo "$result" | jq 'length') == "0" ]]
}

@test "map_stages_to_downstream_multiple_downstream" {
    local console='[Pipeline] { (Build Handle)
[Pipeline] build
Starting building: handle-job #10
[Pipeline] }
[Pipeline] { (Build SignalBoot)
[Pipeline] build
Starting building: signalboot-job #20
[Pipeline] }'

    local stages='[
        {"name":"Build Handle","status":"SUCCESS","durationMillis":20000},
        {"name":"Build SignalBoot","status":"SUCCESS","durationMillis":25000}
    ]'

    local result
    result=$(_map_stages_to_downstream "$console" "$stages")

    [[ $(echo "$result" | jq -r '.["Build Handle"].job') == "handle-job" ]]
    [[ $(echo "$result" | jq -r '.["Build Handle"].build') == "10" ]]
    [[ $(echo "$result" | jq -r '.["Build SignalBoot"].job') == "signalboot-job" ]]
    [[ $(echo "$result" | jq -r '.["Build SignalBoot"].build') == "20" ]]
}

@test "map_stages_to_downstream_prefers_stage_matching_job_when_multiple_matches_in_stage_logs" {
    local console='[Pipeline] { (Build Handle)
Starting building: phandlemono-handle #24
Starting building: phandlemono-signalboot #25
[Pipeline] }
[Pipeline] { (Build SignalBoot)
Starting building: phandlemono-handle #24
Starting building: phandlemono-signalboot #25
[Pipeline] }'

    local stages='[
        {"name":"Build Handle","status":"FAILED","durationMillis":13000},
        {"name":"Build SignalBoot","status":"SUCCESS","durationMillis":205000}
    ]'

    local result
    result=$(_map_stages_to_downstream "$console" "$stages")

    [[ $(echo "$result" | jq -r '.["Build Handle"].job') == "phandlemono-handle" ]]
    [[ $(echo "$result" | jq -r '.["Build Handle"].build') == "24" ]]
    [[ $(echo "$result" | jq -r '.["Build SignalBoot"].job') == "phandlemono-signalboot" ]]
    [[ $(echo "$result" | jq -r '.["Build SignalBoot"].build') == "25" ]]
}

# =============================================================================
# Test Cases: print_stage_line with indent and agent_prefix
# =============================================================================

@test "print_stage_line_with_agent_prefix" {
    run print_stage_line "Checkout" "SUCCESS" 500 "" "[orchestrator1] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage: [orchestrator1] Checkout (<1s)"
}

@test "print_stage_line_with_indent_and_agent" {
    run print_stage_line "Build Handle->Compile Code" "SUCCESS" 18000 "  " "[buildagent9] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:   [buildagent9] Build Handle->Compile Code (18s)"
}

@test "print_stage_line_nested_failed_with_marker" {
    run print_stage_line "Build Handle->Package Zip" "FAILED" 20000 "  " "[buildagent9] "
    assert_success
    [[ "$output" == *"Stage:   [buildagent9] Build Handle->Package Zip (20s)"* ]]
    [[ "$output" == *"← FAILED"* ]]
}

@test "print_stage_line_double_nested_indent" {
    run print_stage_line "A->B->C" "SUCCESS" 5000 "    " "[agent3] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:     [agent3] A->B->C (5s)"
}

@test "print_stage_line_nested_not_executed" {
    run print_stage_line "Build Handle->Deploy" "NOT_EXECUTED" "" "  " "[buildagent9] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:   [buildagent9] Build Handle->Deploy (not executed)"
}

@test "print_stage_line_nested_in_progress" {
    run print_stage_line "Build Handle->Compile" "IN_PROGRESS" "" "  " "[buildagent9] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:   [buildagent9] Build Handle->Compile (running)"
}

@test "print_stage_line_backward_compatible_no_indent_no_agent" {
    # When indent and agent_prefix are empty, output should be identical to before
    run print_stage_line "Build" "SUCCESS" 15000
    assert_success
    assert_output "[18:00:18] ℹ   Stage: Build (15s)"
}

@test "print_stage_line_backward_compatible_empty_strings" {
    run print_stage_line "Build" "SUCCESS" 15000 "" ""
    assert_success
    assert_output "[18:00:18] ℹ   Stage: Build (15s)"
}

# =============================================================================
# Test Cases: _get_nested_stages
# =============================================================================

@test "get_nested_stages_no_downstream" {
    # Mock: simple pipeline with no downstream builds
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000},
            {"name":"Test","status":"SUCCESS","startTimeMillis":0,"durationMillis":10000}
        ]'
    }
    get_console_output() {
        echo "Running on agent1 in /workspace"
    }

    local result
    result=$(_get_nested_stages "test-job" "42")

    # Should have 2 stages
    [[ $(echo "$result" | jq 'length') == "2" ]]
    # Both at nesting_depth 0
    [[ $(echo "$result" | jq '.[0].nesting_depth') == "0" ]]
    [[ $(echo "$result" | jq '.[1].nesting_depth') == "0" ]]
    # Agent should be present
    [[ $(echo "$result" | jq -r '.[0].agent') == "agent1" ]]
    # Names should be plain (no prefix)
    [[ $(echo "$result" | jq -r '.[0].name') == "Build" ]]
    [[ $(echo "$result" | jq -r '.[1].name') == "Test" ]]
}

@test "get_nested_stages_with_downstream" {
    # Tracking which job is requested
    local _call_job=""

    get_all_stages() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo '[
                {"name":"Checkout","status":"SUCCESS","startTimeMillis":0,"durationMillis":500},
                {"name":"Build Handle","status":"FAILED","startTimeMillis":0,"durationMillis":38000}
            ]'
        elif [[ "$job" == "downstream-job" ]]; then
            echo '[
                {"name":"Compile Code","status":"SUCCESS","startTimeMillis":0,"durationMillis":18000},
                {"name":"Package Zip","status":"FAILED","startTimeMillis":0,"durationMillis":20000}
            ]'
        else
            echo '[]'
        fi
    }

    get_console_output() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo 'Running on orchestrator1 in /workspace
[Pipeline] { (Checkout)
echo checkout
[Pipeline] }
[Pipeline] { (Build Handle)
[Pipeline] build
Starting building: downstream-job #10
[Pipeline] }'
        elif [[ "$job" == "downstream-job" ]]; then
            echo 'Running on buildagent9 in /workspace'
        else
            echo ''
        fi
    }

    local result
    result=$(_get_nested_stages "parent-job" "1")

    # Should have 4 stages: Checkout, downstream Compile, downstream Package, Build Handle
    [[ $(echo "$result" | jq 'length') == "4" ]]

    # First: Checkout (nesting_depth 0, agent orchestrator1)
    [[ $(echo "$result" | jq -r '.[0].name') == "Checkout" ]]
    [[ $(echo "$result" | jq '.[0].nesting_depth') == "0" ]]
    [[ $(echo "$result" | jq -r '.[0].agent') == "orchestrator1" ]]

    # Second: Build Handle->Compile Code (nested, depth 1)
    [[ $(echo "$result" | jq -r '.[1].name') == "Build Handle->Compile Code" ]]
    [[ $(echo "$result" | jq '.[1].nesting_depth') == "1" ]]
    [[ $(echo "$result" | jq -r '.[1].agent') == "buildagent9" ]]
    [[ $(echo "$result" | jq -r '.[1].parent_stage') == "Build Handle" ]]
    [[ $(echo "$result" | jq -r '.[1].downstream_job') == "downstream-job" ]]

    # Third: Build Handle->Package Zip (nested, depth 1, FAILED)
    [[ $(echo "$result" | jq -r '.[2].name') == "Build Handle->Package Zip" ]]
    [[ $(echo "$result" | jq -r '.[2].status') == "FAILED" ]]

    # Fourth: Build Handle (parent, has_downstream)
    [[ $(echo "$result" | jq -r '.[3].name') == "Build Handle" ]]
    [[ $(echo "$result" | jq '.[3].has_downstream') == "true" ]]
    [[ $(echo "$result" | jq '.[3].nesting_depth') == "0" ]]
}

@test "get_nested_stages_graceful_degradation" {
    # Parent stages work, but downstream API fails
    get_all_stages() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo '[
                {"name":"Build","status":"FAILED","startTimeMillis":0,"durationMillis":30000}
            ]'
        else
            # Downstream API failure
            return 1
        fi
    }

    get_console_output() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo 'Running on orchestrator1 in /workspace
[Pipeline] { (Build)
Starting building: failing-job #99
[Pipeline] }'
        else
            return 1
        fi
    }

    local result
    result=$(_get_nested_stages "parent-job" "1")

    # Should still have the parent stage (graceful degradation)
    [[ $(echo "$result" | jq 'length') -ge 1 ]]
    [[ $(echo "$result" | jq -r '.[-1].name') == "Build" ]]
}

@test "get_nested_stages_recursive_3_levels" {
    get_all_stages() {
        local job="$1"
        case "$job" in
            level0-job)
                echo '[{"name":"Trigger","status":"SUCCESS","startTimeMillis":0,"durationMillis":50000}]'
                ;;
            level1-job)
                echo '[{"name":"SubTrigger","status":"SUCCESS","startTimeMillis":0,"durationMillis":30000}]'
                ;;
            level2-job)
                echo '[{"name":"Leaf","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000}]'
                ;;
            *)
                echo '[]'
                ;;
        esac
    }

    get_console_output() {
        local job="$1"
        case "$job" in
            level0-job)
                echo 'Running on orch0 in /ws
[Pipeline] { (Trigger)
Starting building: level1-job #1
[Pipeline] }'
                ;;
            level1-job)
                echo 'Running on orch1 in /ws
[Pipeline] { (SubTrigger)
Starting building: level2-job #1
[Pipeline] }'
                ;;
            level2-job)
                echo 'Running on leaf-agent in /ws'
                ;;
            *)
                echo ''
                ;;
        esac
    }

    local result
    result=$(_get_nested_stages "level0-job" "1")

    # Should have: Trigger->SubTrigger->Leaf (depth 2), Trigger->SubTrigger (depth 1), Trigger (depth 0)
    [[ $(echo "$result" | jq 'length') == "3" ]]

    # Deepest level first
    [[ $(echo "$result" | jq -r '.[0].name') == "Trigger->SubTrigger->Leaf" ]]
    [[ $(echo "$result" | jq '.[0].nesting_depth') == "2" ]]
    [[ $(echo "$result" | jq -r '.[0].agent') == "leaf-agent" ]]

    # Middle level
    [[ $(echo "$result" | jq -r '.[1].name') == "Trigger->SubTrigger" ]]
    [[ $(echo "$result" | jq '.[1].nesting_depth') == "1" ]]
    [[ $(echo "$result" | jq '.[1].has_downstream') == "true" ]]

    # Top level
    [[ $(echo "$result" | jq -r '.[2].name') == "Trigger" ]]
    [[ $(echo "$result" | jq '.[2].nesting_depth') == "0" ]]
    [[ $(echo "$result" | jq '.[2].has_downstream') == "true" ]]
}

# =============================================================================
# Test Cases: _display_nested_stages_json
# =============================================================================

@test "display_nested_stages_with_indentation" {
    local nested_json='[
        {"name":"Checkout","status":"SUCCESS","durationMillis":500,"agent":"orchestrator1","nesting_depth":0},
        {"name":"Build Handle->Compile Code","status":"SUCCESS","durationMillis":18000,"agent":"buildagent9","nesting_depth":1},
        {"name":"Build Handle->Package Zip","status":"FAILED","durationMillis":20000,"agent":"buildagent9","nesting_depth":1},
        {"name":"Build Handle","status":"FAILED","durationMillis":38000,"agent":"orchestrator1","nesting_depth":0,"has_downstream":true}
    ]'

    run _display_nested_stages_json "$nested_json" "false"
    assert_success

    # Check that all stages are displayed
    [[ "$output" == *"[orchestrator1] Checkout (<1s)"* ]]
    [[ "$output" == *"  [buildagent9] Build Handle->Compile Code (18s)"* ]]
    [[ "$output" == *"  [buildagent9] Build Handle->Package Zip (20s)"* ]]
    [[ "$output" == *"← FAILED"* ]]
    [[ "$output" == *"[orchestrator1] Build Handle (38s)"* ]]
}

@test "display_nested_stages_completed_only" {
    local nested_json='[
        {"name":"Checkout","status":"SUCCESS","durationMillis":500,"agent":"agent1","nesting_depth":0},
        {"name":"Build->Compile","status":"IN_PROGRESS","durationMillis":0,"agent":"agent2","nesting_depth":1},
        {"name":"Build","status":"IN_PROGRESS","durationMillis":0,"agent":"agent1","nesting_depth":0},
        {"name":"Deploy","status":"NOT_EXECUTED","durationMillis":0,"agent":"agent1","nesting_depth":0}
    ]'

    run _display_nested_stages_json "$nested_json" "true"
    assert_success

    # Only completed stages should show
    [[ "$output" == *"Checkout"* ]]
    [[ "$output" != *"Compile"* ]]
    [[ "$output" != *"Deploy"* ]]
}

@test "display_nested_stages_not_executed_shown" {
    # When completed_only is false, NOT_EXECUTED nested stages should show
    local nested_json='[
        {"name":"Build Handle->Compile","status":"SUCCESS","durationMillis":18000,"agent":"buildagent9","nesting_depth":1},
        {"name":"Build Handle->Deploy","status":"NOT_EXECUTED","durationMillis":0,"agent":"buildagent9","nesting_depth":1},
        {"name":"Build Handle","status":"FAILED","durationMillis":38000,"agent":"orchestrator1","nesting_depth":0}
    ]'

    run _display_nested_stages_json "$nested_json" "false"
    assert_success

    [[ "$output" == *"Build Handle->Compile"* ]]
    [[ "$output" == *"Build Handle->Deploy (not executed)"* ]]
    [[ "$output" == *"Build Handle (38s)"* ]]
}

# =============================================================================
# Test Cases: _track_nested_stage_changes
# =============================================================================

@test "track_nested_no_downstream_backward_compatible" {
    # When there are no downstream builds, behavior matches original track_stage_changes
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":15000}
        ]'
    }
    get_console_output() { echo ""; }

    local previous='[]'
    local stderr_output
    stderr_output=$(_track_nested_stage_changes "test-job" "42" "$previous" "false" 2>&1 >/dev/null)
    local output
    output=$(_track_nested_stage_changes "test-job" "42" "$previous" "false" 2>/dev/null)

    # Should print the completed stage
    [[ "$stderr_output" == *"Stage: Build (15s)"* ]]

    # Should return composite state
    [[ $(echo "$output" | jq '.parent | length') == "1" ]]
}

@test "track_nested_detects_downstream_build" {
    local _call_count=0

    get_all_stages() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo '[
                {"name":"Build Handle","status":"IN_PROGRESS","startTimeMillis":0,"durationMillis":0}
            ]'
        elif [[ "$job" == "downstream-job" ]]; then
            echo '[
                {"name":"Compile","status":"SUCCESS","startTimeMillis":0,"durationMillis":10000}
            ]'
        else
            echo '[]'
        fi
    }

    get_console_output() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo 'Running on orchestrator1 in /ws
[Pipeline] { (Build Handle)
Starting building: downstream-job #10
[Pipeline] }'
        elif [[ "$job" == "downstream-job" ]]; then
            echo 'Running on buildagent9 in /ws'
        else
            echo ''
        fi
    }

    local previous='[]'
    local stderr_output
    stderr_output=$(_track_nested_stage_changes "parent-job" "1" "$previous" "false" 2>&1 >/dev/null)

    # Should print the downstream stage completion
    [[ "$stderr_output" == *"Build Handle->Compile"* ]]
    [[ "$stderr_output" == *"[buildagent9]"* ]]
}

@test "track_nested_preserves_composite_state" {
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000}
        ]'
    }
    get_console_output() { echo "Running on agent1 in /ws"; }

    local first_state
    first_state=$(_track_nested_stage_changes "test-job" "42" "[]" "false" 2>/dev/null)

    # Verify composite structure
    [[ $(echo "$first_state" | jq 'has("parent")') == "true" ]]
    [[ $(echo "$first_state" | jq 'has("downstream")') == "true" ]]
    [[ $(echo "$first_state" | jq 'has("stage_downstream_map")') == "true" ]]
}

@test "track_nested_backward_compat_with_flat_state" {
    # If previous state is a flat array (old format), it should still work
    get_all_stages() {
        echo '[
            {"name":"Build","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000}
        ]'
    }
    get_console_output() { echo ""; }

    local previous='[{"name":"Build","status":"IN_PROGRESS","startTimeMillis":0,"durationMillis":0}]'
    local stderr_output
    stderr_output=$(_track_nested_stage_changes "test-job" "42" "$previous" "false" 2>&1 >/dev/null)

    # Should print the completed stage (transition from IN_PROGRESS to SUCCESS)
    [[ "$stderr_output" == *"Stage: Build (5s)"* ]]
}

# =============================================================================
# Test Cases: JSON output with nested stages
# =============================================================================

@test "json_output_includes_nested_stages" {
    # Source buildgit for output_json
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    get_all_stages() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo '[
                {"name":"Checkout","status":"SUCCESS","startTimeMillis":0,"durationMillis":500},
                {"name":"Build Handle","status":"FAILED","startTimeMillis":0,"durationMillis":38000}
            ]'
        elif [[ "$job" == "downstream-job" ]]; then
            echo '[
                {"name":"Compile","status":"SUCCESS","startTimeMillis":0,"durationMillis":18000},
                {"name":"Package","status":"FAILED","startTimeMillis":0,"durationMillis":20000}
            ]'
        else
            echo '[]'
        fi
    }

    get_console_output() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo 'Running on orchestrator1 in /workspace
[Pipeline] { (Checkout)
echo checkout
[Pipeline] }
[Pipeline] { (Build Handle)
Starting building: downstream-job #10
[Pipeline] }'
        elif [[ "$job" == "downstream-job" ]]; then
            echo 'Running on buildagent9 in /workspace'
        else
            echo ''
        fi
    }

    # Mock other functions used by output_json
    fetch_test_results() { echo ""; }
    _build_failure_json() {
        echo '{"failed_jobs":["parent-job"],"root_cause_job":"parent-job","failed_stage":null,"error_summary":null,"console_output":null,"console_log":null}'
    }
    _build_info_json() {
        echo '{"started_by":null,"agent":"orchestrator1","pipeline":null}'
    }

    local build_json='{"result":"FAILURE","building":false,"duration":38000,"timestamp":1700000000000,"url":"http://jenkins/job/parent-job/1/"}'
    local console_output='Running on orchestrator1 in /workspace
[Pipeline] { (Checkout)
echo checkout
[Pipeline] }
[Pipeline] { (Build Handle)
Starting building: downstream-job #10
[Pipeline] }'

    local result
    result=$(output_json "parent-job" "1" "$build_json" "automated" "" "abc1234" "test commit" "unknown" "$console_output")

    # Verify stages array exists
    [[ $(echo "$result" | jq '.stages | length') -ge 3 ]]

    # Check nested stage has downstream fields
    local nested_stage
    nested_stage=$(echo "$result" | jq '.stages[] | select(.name == "Build Handle->Compile")')
    [[ $(echo "$nested_stage" | jq -r '.agent') == "buildagent9" ]]
    [[ $(echo "$nested_stage" | jq -r '.downstream_job') == "downstream-job" ]]
    [[ $(echo "$nested_stage" | jq '.nesting_depth') == "1" ]]

    # Check parent stage has has_downstream
    local parent_stage
    parent_stage=$(echo "$result" | jq '.stages[] | select(.name == "Build Handle")')
    [[ $(echo "$parent_stage" | jq '.has_downstream') == "true" ]]
}
