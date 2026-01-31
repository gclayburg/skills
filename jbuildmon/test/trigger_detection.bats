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
    # Should output "automated" and "scm-trigger"
    assert_output --partial "automated"
    assert_output --partial "scm-trigger"
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
    # Should output "automated" and "timer"
    assert_output --partial "automated"
    assert_output --partial "timer"
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
    # Should output "automated" and "upstream"
    assert_output --partial "automated"
    assert_output --partial "upstream"
}
