#!/usr/bin/env bats

# Unit tests for detect_trigger_type function
# Spec reference: bug2026-01-31-checkbuild-silent-exit-spec.md
# Plan reference: bug2026-01-31-checkbuild-silent-exit-plan.md#chunk-a

load test_helper

# Load the jenkins-common.sh library containing detect_trigger_type
setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 when no trigger pattern matches
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 1
# -----------------------------------------------------------------------------
@test "detect_trigger_type_returns_0_for_unknown" {
    local console_output='[Pipeline] Start of Pipeline
Some random output
[Pipeline] End of Pipeline'

    run detect_trigger_type "$console_output"
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: Function outputs "unknown" on both lines when no pattern matches
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 1
# -----------------------------------------------------------------------------
@test "detect_trigger_type_outputs_unknown_for_no_match" {
    local console_output='[Pipeline] Start of Pipeline
Some random output
[Pipeline] End of Pipeline'

    run detect_trigger_type "$console_output"
    assert_success
    # Should output two lines, both "unknown"
    local lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true
    assert [ "${lines[0]}" = "unknown" ]
    assert [ "${lines[1]}" = "unknown" ]
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 for "Started by user" pattern
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 1
# -----------------------------------------------------------------------------
@test "detect_trigger_type_returns_0_for_user_trigger" {
    local console_output='Started by user testuser
[Pipeline] Start of Pipeline'

    run detect_trigger_type "$console_output"
    assert_success
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 for "Started by an SCM change" pattern
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 1
# -----------------------------------------------------------------------------
@test "detect_trigger_type_returns_0_for_scm_trigger" {
    local console_output='Started by an SCM change
[Pipeline] Start of Pipeline'

    run detect_trigger_type "$console_output"
    assert_success
    assert_output --partial "scm"
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 for "Started by timer" pattern
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 1
# -----------------------------------------------------------------------------
@test "detect_trigger_type_returns_0_for_timer_trigger" {
    local console_output='Started by timer
[Pipeline] Start of Pipeline'

    run detect_trigger_type "$console_output"
    assert_success
    assert_output --partial "timer"
}

@test "detect_trigger_type_from_build_json_prefers_api_user_cause" {
    local build_json='{"actions":[{"_class":"hudson.model.CauseAction","causes":[{"_class":"hudson.model.Cause$UserIdCause","userName":"Ralph AI Read Only"}]}]}'

    run detect_trigger_type_from_build_json "$build_json"
    assert_success
    assert_line --index 0 "manual"
    assert_line --index 1 "Ralph AI Read Only"
}

@test "detect_trigger_type_from_build_json_maps_branch_indexing_to_scm" {
    local build_json='{"actions":[{"_class":"hudson.model.CauseAction","causes":[{"_class":"jenkins.branch.BranchIndexingCause"}]}]}'

    run detect_trigger_type_from_build_json "$build_json"
    assert_success
    assert_line --index 0 "scm"
    assert_line --index 1 "unknown"
}

@test "detect_trigger_type_from_build_json_manual_with_empty_user_keeps_manual" {
    local build_json='{"actions":[{"_class":"hudson.model.CauseAction","causes":[{"_class":"hudson.model.Cause$UserIdCause","userName":""}]}]}'

    run detect_trigger_type_from_build_json "$build_json"
    assert_success
    assert_line --index 0 "manual"
    assert_line --index 1 ""
}

# -----------------------------------------------------------------------------
# Test Case: Function returns 0 for "Started by upstream project" pattern
# Spec: bug2026-01-31-checkbuild-silent-exit-spec.md, Section: Solution - Change 1
# -----------------------------------------------------------------------------
@test "detect_trigger_type_returns_0_for_upstream_trigger" {
    local console_output='Started by upstream project "parent-job" build number 123
[Pipeline] Start of Pipeline'

    run detect_trigger_type "$console_output"
    assert_success
    assert_output --partial "upstream"
}
