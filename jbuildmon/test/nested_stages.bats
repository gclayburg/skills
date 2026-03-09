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

@test "extract_agent_name_preserves_spaces" {
    local console="Running on agent6 guthrie in /home/jenkins/workspace/ralph1"

    local agent
    agent=$(_extract_agent_name "$console")
    [[ "$agent" == "agent6 guthrie" ]]
}

@test "extract_agent_name_with_ansi_prefix" {
    local console=$'\x1b[0mRunning on agent8_sixcore in /var/jenkins/workspace/ralph1'

    local agent
    agent=$(_extract_agent_name "$console")
    [[ "$agent" == "agent8_sixcore" ]]
}

@test "extract_pre_stage_agent_from_console_returns_pipeline_scope_agent" {
    local console='[Pipeline] Start of Pipeline
[Pipeline] node
Running on agent8_sixcore in /var/jenkins/workspace/phandlemono-IT
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Checkout)'

    local agent
    agent=$(_extract_pre_stage_agent_from_console "$console")
    [[ "$agent" == "agent8_sixcore" ]]
}

@test "extract_pre_stage_agent_from_console_ignores_stage_scoped_agents" {
    local console='[Pipeline] stage
[Pipeline] { (Build)
[Pipeline] node
Running on agent7 guthrie in /var/jenkins/workspace/ralph1'

    local agent
    agent=$(_extract_pre_stage_agent_from_console "$console")
    [[ -z "$agent" ]]
}

# =============================================================================
# Test Cases: _build_stage_agent_map
# =============================================================================

@test "build_stage_agent_map_maps_stages_to_agents" {
    local console='[Pipeline] { (Build)
[Pipeline] node
Running on agent6 guthrie in /home/jenkins/workspace/ralph1
[Pipeline] }
[Pipeline] { (Unit Tests A)
[Pipeline] node
Running on agent7 in /home/jenkins/workspace/ralph1
[Pipeline] }'

    local result
    result=$(_build_stage_agent_map "$console")

    [[ $(echo "$result" | jq -r '.["Build"]') == "agent6 guthrie" ]]
    [[ $(echo "$result" | jq -r '.["Unit Tests A"]') == "agent7" ]]
}

@test "build_stage_agent_map_parallel_branches_use_distinct_agents" {
    local console='[Pipeline] { (Unit Tests)
[Pipeline] parallel
[Pipeline] { (Branch: Unit Tests A)
[Pipeline] node
Running on agent7 guthrie in /home/jenkins/workspace/ralph1
[Pipeline] }
[Pipeline] { (Branch: Unit Tests B)
[Pipeline] node
Running on agent8_sixcore in /home/jenkins/workspace/ralph1
[Pipeline] }'

    local result
    result=$(_build_stage_agent_map "$console")

    [[ $(echo "$result" | jq -r '.["Unit Tests A"]') == "agent7 guthrie" ]]
    [[ $(echo "$result" | jq -r '.["Unit Tests B"]') == "agent8_sixcore" ]]
}

@test "build_stage_agent_map_returns_empty_when_no_running_lines" {
    local console='[Pipeline] { (Build)
echo build
[Pipeline] }'

    local result
    result=$(_build_stage_agent_map "$console")

    [[ "$(echo "$result" | jq -c '.')" == "{}" ]]
}

@test "build_stage_agent_map_ignores_unmatched_running_lines" {
    local console='Running on agent9 in /home/jenkins/workspace/ralph1'

    local result
    result=$(_build_stage_agent_map "$console")

    [[ "$(echo "$result" | jq -c '.')" == "{}" ]]
}

@test "build_stage_agent_map_keeps_only_explicit_stage_assignments" {
    local console='[Pipeline] Start of Pipeline
[Pipeline] node
Running on orchestrator1 in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Checkout)
[Pipeline] echo
checkout
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Deploy)
[Pipeline] node
Running on deploy-agent in /workspace
[Pipeline] }
[Pipeline] // stage'

    local result
    result=$(_build_stage_agent_map "$console")

    [[ $(echo "$result" | jq -r '.["Checkout"] // empty') == "" ]]
    [[ $(echo "$result" | jq -r '.["Deploy"]') == "deploy-agent" ]]
}

@test "parse_build_metadata_header_uses_full_agent_name" {
    local console='Started by user admin
Running on agent6 guthrie in /home/jenkins/workspace/ralph1'

    _parse_build_metadata "$console"

    [[ "$_META_AGENT" == "agent6 guthrie" ]]
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

@test "map_stages_to_downstream_ignores_parallel_log_bleed_without_stage_job_match" {
    local console='[Pipeline] { (parallel build test)
[Pipeline] parallel
[Pipeline] { (Branch: synconsole build)
[Pipeline] { (Branch: visualsync track)
[Pipeline] { (Branch: dsltestharness)
[Pipeline] stage
[Pipeline] { (synconsole build)
[Pipeline] stage
[Pipeline] { (visualsync track)
[Pipeline] stage
[Pipeline] { (dsltestharness)
[Pipeline] build
Starting building: synconsole #1656
[Pipeline] build
Starting building: dsltestharness #1510
[Pipeline] }'

    local stages='[
        {"name":"synconsole build","status":"FAILED","durationMillis":230000},
        {"name":"visualsync track","status":"SUCCESS","durationMillis":76000},
        {"name":"dsltestharness","status":"SUCCESS","durationMillis":58000}
    ]'

    local result
    result=$(_map_stages_to_downstream "$console" "$stages")

    [[ $(echo "$result" | jq -r '.["synconsole build"].job') == "synconsole" ]]
    [[ $(echo "$result" | jq -r '.["synconsole build"].build') == "1656" ]]
    [[ $(echo "$result" | jq -r '.["dsltestharness"].job') == "dsltestharness" ]]
    [[ $(echo "$result" | jq -r '.["dsltestharness"].build') == "1510" ]]
    [[ $(echo "$result" | jq -r '.["visualsync track"] // empty') == "" ]]
}

@test "map_stages_to_downstream_drops_generic_tests_token_false_positive" {
    local console='[Pipeline] { (tests)
[Pipeline] { (Branch: back front tests)
[Pipeline] { (Branch: panorama)
[Pipeline] stage
[Pipeline] { (back front tests)
[Pipeline] stage
[Pipeline] { (panorama)
[Pipeline] stage
[Pipeline] { (backend tests)
Starting building: panorama_integration_tests #1749
[Pipeline] }'

    local stages='[
        {"name":"tests","status":"SUCCESS","durationMillis":100},
        {"name":"back front tests","status":"SUCCESS","durationMillis":100},
        {"name":"panorama","status":"FAILED","durationMillis":135000},
        {"name":"backend tests","status":"SUCCESS","durationMillis":46000}
    ]'

    local result
    result=$(_map_stages_to_downstream "$console" "$stages")

    [[ $(echo "$result" | jq -r '.panorama.job') == "panorama_integration_tests" ]]
    [[ $(echo "$result" | jq -r '.panorama.build') == "1749" ]]
    [[ $(echo "$result" | jq -r '.tests // empty') == "" ]]
    [[ $(echo "$result" | jq -r '.["back front tests"] // empty') == "" ]]
    [[ $(echo "$result" | jq -r '.["backend tests"] // empty') == "" ]]
}

# =============================================================================
# Test Cases: print_stage_line with indent and agent_prefix
# =============================================================================

@test "print_stage_line_with_agent_prefix" {
    run print_stage_line "Checkout" "SUCCESS" 500 "" "[orchestrator1] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage: [orchestrator1 ] Checkout (<1s)"
}

@test "print_stage_line_with_indent_and_agent" {
    run print_stage_line "Build Handle->Compile Code" "SUCCESS" 18000 "  " "[buildagent9] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:   [buildagent9   ] Build Handle->Compile Code (18s)"
}

@test "print_stage_line_with_space_agent_name_truncates_to_14_chars" {
    run print_stage_line "Build" "SUCCESS" 1000 "" "[agent6 guthrie] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage: [agent6 guthrie] Build (1s)"
}

@test "print_stage_line_nested_failed_with_marker" {
    run print_stage_line "Build Handle->Package Zip" "FAILED" 20000 "  " "[buildagent9] "
    assert_success
    [[ "$output" == *"Stage:   [buildagent9   ] Build Handle->Package Zip (20s)"* ]]
    [[ "$output" == *"← FAILED"* ]]
}

@test "print_stage_line_double_nested_indent" {
    run print_stage_line "A->B->C" "SUCCESS" 5000 "    " "[agent3] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:     [agent3        ] A->B->C (5s)"
}

@test "print_stage_line_nested_not_executed" {
    run print_stage_line "Build Handle->Deploy" "NOT_EXECUTED" "" "  " "[buildagent9] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:   [buildagent9   ] Build Handle->Deploy (not executed)"
}

@test "print_stage_line_nested_in_progress" {
    run print_stage_line "Build Handle->Compile" "IN_PROGRESS" "" "  " "[buildagent9] "
    assert_success
    assert_output "[18:00:18] ℹ   Stage:   [buildagent9   ] Build Handle->Compile (running)"
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
        echo '[Pipeline] { (Build)
[Pipeline] node
Running on agent1 in /workspace
[Pipeline] }
[Pipeline] { (Test)
[Pipeline] node
Running on agent2 in /workspace
[Pipeline] }'
    }

    local result
    result=$(_get_nested_stages "test-job" "42")

    # Should have 2 stages
    [[ $(echo "$result" | jq 'length') == "2" ]]
    # Both at nesting_depth 0
    [[ $(echo "$result" | jq '.[0].nesting_depth') == "0" ]]
    [[ $(echo "$result" | jq '.[1].nesting_depth') == "0" ]]
    # Each stage should use its own mapped agent
    [[ $(echo "$result" | jq -r '.[0].agent') == "agent1" ]]
    [[ $(echo "$result" | jq -r '.[1].agent') == "agent2" ]]
    # Names should be plain (no prefix)
    [[ $(echo "$result" | jq -r '.[0].name') == "Build" ]]
    [[ $(echo "$result" | jq -r '.[1].name') == "Test" ]]
}

@test "get_nested_stages_wrapper_stage_without_running_on_has_empty_agent" {
    get_all_stages() {
        echo '[
            {"name":"Unit Tests","status":"SUCCESS","startTimeMillis":0,"durationMillis":10000},
            {"name":"Unit Tests A","status":"SUCCESS","startTimeMillis":0,"durationMillis":5000}
        ]'
    }

    get_console_output() {
        echo '[Pipeline] { (Unit Tests)
[Pipeline] parallel
[Pipeline] { (Branch: Unit Tests A)
[Pipeline] node
Running on agent7 in /workspace
[Pipeline] }'
    }

    local result
    result=$(_get_nested_stages "test-job" "42")

    [[ $(echo "$result" | jq -r '.[] | select(.name == "Unit Tests").agent') == "" ]]
    [[ $(echo "$result" | jq -r '.[] | select(.name == "Unit Tests A").agent') == "agent7" ]]
}

@test "get_nested_stages_pipeline_scope_agent_applies_when_node_starts_before_first_stage" {
    get_all_stages() {
        echo '[
            {"name":"Declarative: Checkout SCM","status":"SUCCESS","startTimeMillis":0,"durationMillis":500},
            {"name":"Checkout","status":"SUCCESS","startTimeMillis":0,"durationMillis":600},
            {"name":"Trigger Component Builds","status":"SUCCESS","startTimeMillis":0,"durationMillis":120000}
        ]'
    }

    get_console_output() {
        echo '[Pipeline] Start of Pipeline
[Pipeline] node
Running on agent8_sixcore in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Declarative: Checkout SCM)
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Checkout)
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] }
[Pipeline] // stage'
    }

    local result
    result=$(_get_nested_stages "test-job" "42")

    [[ $(echo "$result" | jq -r '.[] | select(.name == "Declarative: Checkout SCM").agent') == "agent8_sixcore" ]]
    [[ $(echo "$result" | jq -r '.[] | select(.name == "Checkout").agent') == "agent8_sixcore" ]]
    [[ $(echo "$result" | jq -r '.[] | select(.name == "Trigger Component Builds").agent') == "agent8_sixcore" ]]
}

@test "get_nested_stages_pipeline_scope_agent_fills_unmapped_stages_only" {
    get_all_stages() {
        echo '[
            {"name":"Checkout","status":"SUCCESS","startTimeMillis":0,"durationMillis":500},
            {"name":"Deploy","status":"SUCCESS","startTimeMillis":0,"durationMillis":3000}
        ]'
    }

    get_console_output() {
        echo '[Pipeline] Start of Pipeline
[Pipeline] node
Running on orchestrator1 in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Checkout)
[Pipeline] echo
checkout
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Deploy)
[Pipeline] node
Running on deploy-agent in /workspace
[Pipeline] }
[Pipeline] // stage'
    }

    local result
    result=$(_get_nested_stages "test-job" "42")

    [[ $(echo "$result" | jq -r '.[] | select(.name == "Checkout").agent') == "orchestrator1" ]]
    [[ $(echo "$result" | jq -r '.[] | select(.name == "Deploy").agent') == "deploy-agent" ]]
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
            echo '[Pipeline] { (Checkout)
[Pipeline] node
Running on orchestrator1 in /workspace
echo checkout
[Pipeline] }
[Pipeline] { (Build Handle)
[Pipeline] node
Running on orchestrator2 in /workspace
[Pipeline] build
Starting building: downstream-job #10
[Pipeline] }'
        elif [[ "$job" == "downstream-job" ]]; then
            echo '[Pipeline] { (Compile Code)
[Pipeline] node
Running on buildagent9 in /workspace
[Pipeline] }
[Pipeline] { (Package Zip)
[Pipeline] node
Running on buildagent10 in /workspace'
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
    [[ $(echo "$result" | jq -r '.[2].agent') == "buildagent10" ]]

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
                echo '[Pipeline] { (Leaf)
[Pipeline] node
Running on leaf-agent in /ws'
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

@test "get_nested_stages_downstream_pipeline_scope_agent_applies_recursively" {
    get_all_stages() {
        local job="$1"
        case "$job" in
            parent-job)
                echo '[{"name":"Build Handle","status":"SUCCESS","startTimeMillis":0,"durationMillis":38000}]'
                ;;
            downstream-job)
                echo '[
                    {"name":"Checkout","status":"SUCCESS","startTimeMillis":0,"durationMillis":500},
                    {"name":"Package","status":"SUCCESS","startTimeMillis":0,"durationMillis":1200}
                ]'
                ;;
            *)
                echo '[]'
                ;;
        esac
    }

    get_console_output() {
        local job="$1"
        case "$job" in
            parent-job)
                echo '[Pipeline] { (Build Handle)
Starting building: downstream-job #10
[Pipeline] }'
                ;;
            downstream-job)
                echo '[Pipeline] Start of Pipeline
[Pipeline] node
Running on buildagent9 in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Checkout)
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Package)
[Pipeline] }
[Pipeline] // stage'
                ;;
            *)
                echo ''
                ;;
        esac
    }

    local result
    result=$(_get_nested_stages "parent-job" "1")

    [[ $(echo "$result" | jq -r '.[] | select(.name == "Build Handle->Checkout").agent') == "buildagent9" ]]
    [[ $(echo "$result" | jq -r '.[] | select(.name == "Build Handle->Package").agent') == "buildagent9" ]]
}

@test "get_nested_stages_parallel_wrapper_printed_after_branches" {
    get_all_stages() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo '[
                {"name":"Trigger Component Builds","status":"SUCCESS","startTimeMillis":0,"durationMillis":114},
                {"name":"Build Handle","status":"FAILED","startTimeMillis":1,"durationMillis":13000},
                {"name":"Build SignalBoot","status":"SUCCESS","startTimeMillis":2,"durationMillis":205000},
                {"name":"Verify","status":"SUCCESS","startTimeMillis":3,"durationMillis":1000}
            ]'
        elif [[ "$job" == "handle-job" ]]; then
            echo '[{"name":"Compile","status":"FAILED","startTimeMillis":0,"durationMillis":1000}]'
        elif [[ "$job" == "signalboot-job" ]]; then
            echo '[{"name":"Compile","status":"SUCCESS","startTimeMillis":0,"durationMillis":1000}]'
        else
            echo '[]'
        fi
    }

    get_console_output() {
        local job="$1"
        if [[ "$job" == "parent-job" ]]; then
            echo 'Running on orch in /ws
[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] { (Branch: Build Handle)
Starting building: handle-job #1
[Pipeline] }
[Pipeline] { (Branch: Build SignalBoot)
Starting building: signalboot-job #2
[Pipeline] }
[Pipeline] }'
        elif [[ "$job" == "handle-job" ]]; then
            echo 'Running on h1 in /ws'
        elif [[ "$job" == "signalboot-job" ]]; then
            echo 'Running on s2 in /ws'
        else
            echo ''
        fi
    }

    local result
    result=$(_get_nested_stages "parent-job" "1")

    local idx_wrapper idx_signal idx_verify
    idx_wrapper=$(echo "$result" | jq 'to_entries[] | select(.value.name == "Trigger Component Builds") | .key')
    idx_signal=$(echo "$result" | jq 'to_entries[] | select(.value.name == "Build SignalBoot") | .key')
    idx_verify=$(echo "$result" | jq 'to_entries[] | select(.value.name == "Verify") | .key')

    [[ "$idx_wrapper" -gt "$idx_signal" ]]
    [[ "$idx_verify" -gt "$idx_wrapper" ]]
}

@test "get_nested_stages_nests_parallel_branch_substages_with_branch_agents_and_aggregate_durations" {
    get_all_stages() {
        echo '[
            {"name":"Declarative: Checkout SCM","status":"SUCCESS","startTimeMillis":0,"durationMillis":500},
            {"name":"policyStart bounce","status":"SUCCESS","startTimeMillis":1,"durationMillis":57000},
            {"name":"palmer tests","status":"SUCCESS","startTimeMillis":2,"durationMillis":0},
            {"name":"guthrie tests","status":"SUCCESS","startTimeMillis":3,"durationMillis":0},
            {"name":"parallel tests","status":"SUCCESS","startTimeMillis":4,"durationMillis":0},
            {"name":"synconsolemongo42","status":"SUCCESS","startTimeMillis":5,"durationMillis":40000},
            {"name":"batchrun","status":"SUCCESS","startTimeMillis":6,"durationMillis":95000},
            {"name":"bundletest","status":"SUCCESS","startTimeMillis":7,"durationMillis":30000},
            {"name":"TLSauth","status":"SUCCESS","startTimeMillis":8,"durationMillis":28000},
            {"name":"Declarative: Post Actions","status":"SUCCESS","startTimeMillis":9,"durationMillis":400}
        ]'
    }

    get_console_output() {
        echo '[Pipeline] Start of Pipeline
[Pipeline] node
Running on agent6 guthrie in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Declarative: Checkout SCM)
[Pipeline] }
[Pipeline] stage
[Pipeline] { (parallel tests)
[Pipeline] parallel
[Pipeline] { (Branch: policyStart bounce)
[Pipeline] echo
policy
[Pipeline] }
[Pipeline] { (Branch: palmer tests)
[Pipeline] node
Running on agent1paton in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (batchrun)
[Pipeline] sh
batchrun
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] { (Branch: guthrie tests)
[Pipeline] {
[Pipeline] stage
[Pipeline] { (synconsolemongo42)
[Pipeline] sh
one
[Pipeline] }
[Pipeline] stage
[Pipeline] { (bundletest)
[Pipeline] sh
two
[Pipeline] }
[Pipeline] stage
[Pipeline] { (TLSauth)
[Pipeline] sh
three
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] stage
[Pipeline] { (Declarative: Post Actions)
[Pipeline] }'
    }

    local result
    result=$(_get_nested_stages "test-job" "42")

    [[ "$(echo "$result" | jq -c '[.[] | .name]')" == '["Declarative: Checkout SCM","policyStart bounce","palmer tests->batchrun","palmer tests","guthrie tests->synconsolemongo42","guthrie tests->bundletest","guthrie tests->TLSauth","guthrie tests","parallel tests","Declarative: Post Actions"]' ]]
    [[ "$(echo "$result" | jq '[.[] | select(.name == "batchrun" or .name == "synconsolemongo42" or .name == "bundletest" or .name == "TLSauth")] | length')" == "0" ]]

    [[ "$(echo "$result" | jq -r '.[] | select(.name == "palmer tests->batchrun").agent')" == "agent1paton" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "palmer tests").agent')" == "agent1paton" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "guthrie tests->synconsolemongo42").agent')" == "agent6 guthrie" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "guthrie tests").agent')" == "agent6 guthrie" ]]

    [[ "$(echo "$result" | jq -r '.[] | select(.name == "palmer tests->batchrun").parallel_path')" == "2" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "guthrie tests->bundletest").parallel_path')" == "3" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "guthrie tests->bundletest").parent_branch_stage')" == "guthrie tests" ]]

    [[ "$(echo "$result" | jq -r '.[] | select(.name == "palmer tests").durationMillis')" == "95000" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "guthrie tests").durationMillis')" == "98000" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "parallel tests").durationMillis')" == "98000" ]]
}

@test "get_nested_stages_maps_interleaved_parallel_branch_substages_to_the_correct_branch" {
    get_all_stages() {
        echo '[
            {"id":"37","name":"Setup","status":"SUCCESS","startTimeMillis":0,"durationMillis":1000},
            {"id":"47","name":"Quick Task","status":"SUCCESS","startTimeMillis":1,"durationMillis":3000},
            {"id":"48","name":"Slow Pipeline","status":"SUCCESS","startTimeMillis":2,"durationMillis":0},
            {"id":"49","name":"Default Pipeline","status":"SUCCESS","startTimeMillis":3,"durationMillis":0},
            {"id":"43","name":"Parallel Work","status":"SUCCESS","startTimeMillis":4,"durationMillis":0},
            {"id":"58","name":"Lint","status":"SUCCESS","startTimeMillis":5,"durationMillis":2000},
            {"id":"68","name":"Compile","status":"SUCCESS","startTimeMillis":6,"durationMillis":4000},
            {"id":"74","name":"Analyze","status":"SUCCESS","startTimeMillis":7,"durationMillis":3000},
            {"id":"83","name":"Package","status":"SUCCESS","startTimeMillis":8,"durationMillis":3000},
            {"id":"89","name":"Report","status":"SUCCESS","startTimeMillis":9,"durationMillis":2000},
            {"id":"110","name":"Finalize","status":"SUCCESS","startTimeMillis":10,"durationMillis":1000}
        ]'
    }

    get_console_output() {
        echo '[Pipeline] Start of Pipeline
[Pipeline] node
Running on agent8_sixcore in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Setup)
[Pipeline] }
[Pipeline] stage
[Pipeline] { (Parallel Work)
[Pipeline] parallel
[Pipeline] { (Branch: Quick Task)
[Pipeline] { (Branch: Slow Pipeline)
[Pipeline] { (Branch: Default Pipeline)
[Pipeline] stage
[Pipeline] { (Quick Task)
[Pipeline] stage
[Pipeline] { (Slow Pipeline)
[Pipeline] stage
[Pipeline] { (Default Pipeline)
[Pipeline] node
Running on agent1paton in /workspace
[Pipeline] stage
[Pipeline] { (Lint)
[Pipeline] echo
Linting on default agent...
[Pipeline] sleep
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Compile)
[Pipeline] echo
Compiling on slownode...
[Pipeline] sleep
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Analyze)
[Pipeline] echo
Analyzing on default agent...
[Pipeline] sleep
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Package)
[Pipeline] echo
Packaging on slownode...
[Pipeline] sleep
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Report)
[Pipeline] echo
Reporting on default agent...
[Pipeline] sleep
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // node
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // parallel
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Finalize)
[Pipeline] }
[Pipeline] }'
    }

    get_blue_ocean_nodes() {
        echo '[
            {"id":"37","name":"Setup","type":"STAGE","firstParent":"","durationMillis":1000},
            {"id":"43","name":"Parallel Work","type":"STAGE","firstParent":"37","durationMillis":0},
            {"id":"47","name":"Quick Task","type":"PARALLEL","firstParent":"43","durationMillis":3000},
            {"id":"48","name":"Slow Pipeline","type":"PARALLEL","firstParent":"43","durationMillis":0},
            {"id":"49","name":"Default Pipeline","type":"PARALLEL","firstParent":"43","durationMillis":0},
            {"id":"58","name":"Lint","type":"STAGE","firstParent":"49","durationMillis":2000},
            {"id":"68","name":"Compile","type":"STAGE","firstParent":"48","durationMillis":4000},
            {"id":"74","name":"Analyze","type":"STAGE","firstParent":"58","durationMillis":3000},
            {"id":"83","name":"Package","type":"STAGE","firstParent":"68","durationMillis":3000},
            {"id":"89","name":"Report","type":"STAGE","firstParent":"74","durationMillis":2000},
            {"id":"110","name":"Finalize","type":"STAGE","firstParent":"","durationMillis":1000}
        ]'
    }

    get_blue_ocean_node_steps() {
        local _job="$1"
        local _build="$2"
        local node_id="$3"

        if [[ "$node_id" == "48" ]]; then
            echo '[{"displayName":"Check out from version control","displayDescription":""},{"displayName":"Print Message","displayDescription":"Compiling on slownode..."}]'
        else
            echo '[]'
        fi
    }

    local result
    result=$(_get_nested_stages "test-job" "42")

    [[ "$(echo "$result" | jq -c '[.[] | .name]')" == '["Setup","Quick Task","Slow Pipeline->Compile","Slow Pipeline->Package","Slow Pipeline","Default Pipeline->Lint","Default Pipeline->Analyze","Default Pipeline->Report","Default Pipeline","Parallel Work","Finalize"]' ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "Slow Pipeline->Compile").agent')" == "agent1paton" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "Default Pipeline->Lint").agent')" == "agent8_sixcore" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "Slow Pipeline").durationMillis')" == "7000" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "Default Pipeline").durationMillis')" == "7000" ]]
    [[ "$(echo "$result" | jq -r '.[] | select(.name == "Parallel Work").durationMillis')" == "7000" ]]
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
    [[ "$output" == *"[orchestrator1 ] Checkout (<1s)"* ]]
    [[ "$output" == *"  [buildagent9   ] Build Handle->Compile Code (18s)"* ]]
    [[ "$output" == *"  [buildagent9   ] Build Handle->Package Zip (20s)"* ]]
    [[ "$output" == *"← FAILED"* ]]
    [[ "$output" == *"[orchestrator1 ] Build Handle (38s)"* ]]
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
            echo '[Pipeline] { (Build Handle)
[Pipeline] node
Running on orchestrator1 in /ws
Starting building: downstream-job #10
[Pipeline] }'
        elif [[ "$job" == "downstream-job" ]]; then
            echo '[Pipeline] { (Compile)
[Pipeline] node
Running on buildagent9 in /ws'
        else
            echo ''
        fi
    }

    local previous='[]'
    local stderr_output
    stderr_output=$(_track_nested_stage_changes "parent-job" "1" "$previous" "false" 2>&1 >/dev/null)

    # Should print the downstream stage completion
    [[ "$stderr_output" == *"Build Handle->Compile"* ]]
    [[ "$stderr_output" == *"[buildagent9   ]"* ]]
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
            echo '[Pipeline] { (Checkout)
[Pipeline] node
Running on orchestrator1 in /workspace
echo checkout
[Pipeline] }
[Pipeline] { (Build Handle)
[Pipeline] node
Running on orchestrator2 in /workspace
Starting building: downstream-job #10
[Pipeline] }'
        elif [[ "$job" == "downstream-job" ]]; then
            echo '[Pipeline] { (Compile)
[Pipeline] node
Running on buildagent9 in /workspace
[Pipeline] }
[Pipeline] { (Package)
[Pipeline] node
Running on buildagent10 in /workspace'
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
    local console_output='[Pipeline] { (Checkout)
[Pipeline] node
Running on orchestrator1 in /workspace
echo checkout
[Pipeline] }
[Pipeline] { (Build Handle)
[Pipeline] node
Running on orchestrator2 in /workspace
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

@test "json_output_includes_parallel_branch_substage_fields" {
    _BUILDGIT_TESTING=1
    source "${PROJECT_DIR}/buildgit"

    get_all_stages() {
        echo '[
            {"name":"parallel tests","status":"SUCCESS","startTimeMillis":0,"durationMillis":0},
            {"name":"policyStart bounce","status":"SUCCESS","startTimeMillis":1,"durationMillis":57000},
            {"name":"palmer tests","status":"SUCCESS","startTimeMillis":2,"durationMillis":0},
            {"name":"guthrie tests","status":"SUCCESS","startTimeMillis":3,"durationMillis":0},
            {"name":"synconsolemongo42","status":"SUCCESS","startTimeMillis":4,"durationMillis":40000},
            {"name":"batchrun","status":"SUCCESS","startTimeMillis":5,"durationMillis":95000},
            {"name":"bundletest","status":"SUCCESS","startTimeMillis":6,"durationMillis":30000},
            {"name":"TLSauth","status":"SUCCESS","startTimeMillis":7,"durationMillis":28000}
        ]'
    }

    get_console_output() {
        echo '[Pipeline] Start of Pipeline
[Pipeline] node
Running on agent6 guthrie in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (parallel tests)
[Pipeline] parallel
[Pipeline] { (Branch: policyStart bounce)
[Pipeline] echo
policy
[Pipeline] }
[Pipeline] { (Branch: palmer tests)
[Pipeline] node
Running on agent1paton in /workspace
[Pipeline] {
[Pipeline] stage
[Pipeline] { (batchrun)
[Pipeline] sh
batchrun
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] { (Branch: guthrie tests)
[Pipeline] {
[Pipeline] stage
[Pipeline] { (synconsolemongo42)
[Pipeline] sh
one
[Pipeline] }
[Pipeline] stage
[Pipeline] { (bundletest)
[Pipeline] sh
two
[Pipeline] }
[Pipeline] stage
[Pipeline] { (TLSauth)
[Pipeline] sh
three
[Pipeline] }
[Pipeline] }
[Pipeline] }
[Pipeline] }'
    }

    fetch_test_results() { echo ""; }
    _build_failure_json() { echo '{"failed_jobs":[],"root_cause_job":null,"failed_stage":null,"error_summary":null,"console_output":null,"console_log":null}'; }
    _build_info_json() { echo '{"started_by":null,"agent":"agent6 guthrie","pipeline":null}'; }

    local build_json='{"result":"SUCCESS","building":false,"duration":98000,"timestamp":1700000000000,"url":"http://jenkins/job/test-job/42/"}'
    local result
    result=$(output_json "test-job" "42" "$build_json" "automated" "" "abc1234" "test commit" "unknown" "")

    local substage
    substage=$(echo "$result" | jq '.stages[] | select(.name == "guthrie tests->synconsolemongo42")')
    [[ "$(echo "$substage" | jq -r '.parallel_branch')" == "guthrie tests" ]]
    [[ "$(echo "$substage" | jq -r '.parallel_wrapper')" == "parallel tests" ]]
    [[ "$(echo "$substage" | jq -r '.parallel_path')" == "3" ]]
    [[ "$(echo "$substage" | jq -r '.parent_branch_stage')" == "guthrie tests" ]]
}
