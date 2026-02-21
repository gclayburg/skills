#!/usr/bin/env bats

# Tests for buildgit --version option
# Spec reference: 2026-02-21_version-number-spec.md

load test_helper

# =============================================================================
# Setup
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    BUILDGIT="${PROJECT_DIR}/skill/buildgit/scripts/buildgit"

    # Extract expected version from script
    EXPECTED_VERSION="$(grep '^BUILDGIT_VERSION=' "$BUILDGIT" | head -1 | sed 's/BUILDGIT_VERSION="//' | sed 's/"//')"
}

# =============================================================================
# Test Cases
# =============================================================================

@test "version flag prints version string" {
    run "$BUILDGIT" --version
    assert_success
    assert_output "buildgit ${EXPECTED_VERSION}"
}

@test "version flag exits 0" {
    run "$BUILDGIT" --version
    assert_success
}

@test "version flag takes precedence over commands" {
    run "$BUILDGIT" --version status
    assert_success
    assert_output "buildgit ${EXPECTED_VERSION}"
}

@test "help shows version option" {
    run "$BUILDGIT" --help
    assert_success
    assert_output --partial "--version"
    assert_output --partial "Show version number and exit"
}
