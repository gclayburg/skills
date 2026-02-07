#!/usr/bin/env bats

# Unit tests for refactored display_building_output (unified header format)
# Spec reference: unify-follow-log-spec.md, Section 2 (Build Header)
# Plan reference: unify-follow-log-plan.md, Chunk B

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Create a helper script that calls display_building_output with controlled params
    # This avoids needing real Jenkins API calls
    _create_header_test_script
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# Helper: create a test script that calls display_building_output with mock data
_create_header_test_script() {
    # Build a mock build_json with a known timestamp
    # Use current epoch to keep elapsed time small
    local now_epoch_s
    now_epoch_s=$(date +%s)
    local build_timestamp_ms=$(( now_epoch_s * 1000 - 5000 ))  # 5 seconds ago

    MOCK_BUILD_JSON=$(cat <<EOJSON
{"timestamp":${build_timestamp_ms},"url":"http://jenkins.example.com:8080/job/ralph1/80/","building":true,"result":null}
EOJSON
)

    MOCK_CONSOLE_OUTPUT="Started by user buildtriggerdude
Running on agent2paton in /var/jenkins/workspace/ralph1
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git"
}

# =============================================================================
# Test Cases: Header Content
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 2 (Build Header)
@test "header_shows_banner" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "BUILD IN PROGRESS"
}

@test "header_shows_job_field" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "Job:        ralph1"
}

@test "header_shows_build_number" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "Build:      #80"
}

@test "header_shows_status_building" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "BUILDING"
}

# Spec: unify-follow-log-spec.md, Trigger Types
@test "header_shows_trigger_automated" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "Trigger:    Automated (git push)"
}

@test "header_shows_trigger_manual" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "manual" "jsmith" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "Trigger:    Manual (started by jsmith)"
}

# Spec: unify-follow-log-spec.md, Field Descriptions
@test "header_shows_commit" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abcdef" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial 'Commit:     b372452 - "test123"'
}

@test "header_shows_correlation" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "Your commit (HEAD)"
}

@test "header_shows_started_time" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "Started:"
}

@test "header_shows_elapsed_time" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    assert_output --partial "Elapsed:"
}

# =============================================================================
# Test Cases: Elapsed suffix
# =============================================================================

# Spec: unify-follow-log-spec.md, Elapsed Time Display
@test "header_elapsed_no_suffix" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    # Should NOT contain "(so far)"
    refute_output --partial "(so far)"
}

@test "header_elapsed_so_far_suffix" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" "(so far)"
    assert_success
    assert_output --partial "(so far)"
}

# =============================================================================
# Test Cases: Build Info section
# =============================================================================

# Spec: unify-follow-log-spec.md, Section 2 (Build Header)
@test "header_shows_build_info_section" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" \
        "$MOCK_CONSOLE_OUTPUT" ""
    assert_success
    assert_output --partial "=== Build Info ==="
    assert_output --partial "Started by:  buildtriggerdude"
    assert_output --partial "Agent:       agent2paton"
    assert_output --partial "Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git"
}

@test "header_shows_console_url_after_build_info" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" \
        "$MOCK_CONSOLE_OUTPUT" ""
    assert_success
    # Console URL should appear in output
    assert_output --partial "Console:    http://jenkins.example.com:8080/job/ralph1/80/console"
    # Build Info should appear before Console URL
    # Extract line numbers to verify ordering
    local build_info_line console_line
    build_info_line=$(echo "$output" | grep -n "=== Build Info ===" | head -1 | cut -d: -f1)
    console_line=$(echo "$output" | grep -n "Console:" | head -1 | cut -d: -f1)
    [[ "$build_info_line" -lt "$console_line" ]]
}

# =============================================================================
# Test Cases: No stages in header
# =============================================================================

# Spec: unify-follow-log-spec.md - stages are streamed separately, not in header
@test "header_does_not_show_stages" {
    # Mock get_all_stages to return some stages — they should NOT appear in header output
    get_all_stages() {
        echo '[{"name":"Build","status":"SUCCESS","durationMillis":5000}]'
    }
    export -f get_all_stages

    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    # Should not contain stage lines in the header
    refute_output --partial "Stage: Build"
}

# =============================================================================
# Test Cases: Without console output
# =============================================================================

@test "header_without_console_output" {
    run display_building_output "ralph1" "80" "$MOCK_BUILD_JSON" \
        "automated" "scm-trigger" "b372452abc" "test123" "your_commit" "" "" ""
    assert_success
    # Should NOT contain Build Info section
    refute_output --partial "=== Build Info ==="
    # Should still contain Console URL
    assert_output --partial "Console:"
}
