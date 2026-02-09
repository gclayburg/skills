#!/usr/bin/env bats

# Tests for jenkins-common.sh library
# Migrated from lib/test-jenkins-common.sh into bats-core

load test_helper

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# Test 1: Source the library
# =============================================================================

@test "jenkins_common_sources_successfully" {
    run bash -c "source '${PROJECT_DIR}/lib/jenkins-common.sh'"
    assert_success
}

# =============================================================================
# Test 2: Color variables exist
# =============================================================================

@test "jenkins_common_color_variables_defined" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    for var in COLOR_RESET COLOR_BLUE COLOR_GREEN COLOR_YELLOW COLOR_RED COLOR_CYAN COLOR_BOLD; do
        # Variable must be declared (may be empty if colors disabled)
        declare -p "$var" &>/dev/null || fail "Variable $var is not defined"
    done
}

# =============================================================================
# Test 3: _timestamp returns HH:MM:SS format
# =============================================================================

@test "jenkins_common_timestamp_format" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    local ts
    ts=$(_timestamp)
    [[ "$ts" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

# =============================================================================
# Test 4: Logging functions output to correct streams
# =============================================================================

@test "jenkins_common_log_info_stdout" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    local output
    output=$(log_info "test message" 2>/dev/null)
    [[ "$output" == *"test message"* ]]
    [[ "$output" == *"ℹ"* ]]
}

@test "jenkins_common_log_success_stdout" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    local output
    output=$(log_success "test message" 2>/dev/null)
    [[ "$output" == *"test message"* ]]
    [[ "$output" == *"✓"* ]]
}

@test "jenkins_common_log_warning_stdout" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    local output
    output=$(log_warning "test message" 2>/dev/null)
    [[ "$output" == *"test message"* ]]
    [[ "$output" == *"⚠"* ]]
}

@test "jenkins_common_log_error_stderr" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    # Capture stderr only (redirect stdout to /dev/null)
    local output
    output=$(log_error "test error" 2>&1 >/dev/null)
    [[ "$output" == *"test error"* ]]
    [[ "$output" == *"✗"* ]]
}

# =============================================================================
# Test 5: log_banner formats
# =============================================================================

@test "jenkins_common_banner_success" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run log_banner "success"
    assert_success
    assert_output --partial "BUILD SUCCESSFUL"
    assert_output --partial "╔"
    assert_output --partial "╚"
}

@test "jenkins_common_banner_failure" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run log_banner "failure"
    assert_success
    assert_output --partial "BUILD FAILED"
}

@test "jenkins_common_banner_building" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run log_banner "building"
    assert_success
    assert_output --partial "BUILD IN PROGRESS"
}

@test "jenkins_common_banner_in_progress" {
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    run log_banner "in_progress"
    assert_success
    assert_output --partial "BUILD IN PROGRESS"
}

# =============================================================================
# Test 6: Colors disabled with TERM=dumb
# =============================================================================

@test "jenkins_common_colors_disabled_term_dumb" {
    local output
    output=$(TERM=dumb bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        if [[ -z \"\$COLOR_RESET\" && -z \"\$COLOR_BLUE\" && -z \"\$COLOR_GREEN\" ]]; then
            echo 'colors_disabled'
        else
            echo 'colors_enabled'
        fi
    ")
    [[ "$output" == "colors_disabled" ]]
}

# =============================================================================
# Test 7: Colors disabled with NO_COLOR
# =============================================================================

@test "jenkins_common_colors_disabled_no_color" {
    local output
    output=$(NO_COLOR=1 bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        if [[ -z \"\$COLOR_RESET\" && -z \"\$COLOR_BLUE\" && -z \"\$COLOR_GREEN\" ]]; then
            echo 'colors_disabled'
        else
            echo 'colors_enabled'
        fi
    ")
    [[ "$output" == "colors_disabled" ]]
}

# =============================================================================
# Test 8: Multiple sourcing prevention
# =============================================================================

@test "jenkins_common_multiple_sourcing" {
    run bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        echo 'ok'
    "
    assert_success
    assert_output "ok"
}
