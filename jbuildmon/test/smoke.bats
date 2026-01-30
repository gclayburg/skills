#!/usr/bin/env bats

# Smoke tests for bats-core setup verification
# See spec: install-bats-core-spec.md#verification

load test_helper

# Spec reference: Verification - basic test passes
@test "smoke_test_passes" {
    run true
    assert_success
}

# Spec reference: bats-assert - assert_success
@test "smoke_test_assert_success" {
    run echo "hello"
    assert_success
}

# Spec reference: bats-assert - assert_failure
@test "smoke_test_assert_failure" {
    run false
    assert_failure
}

# Spec reference: bats-assert - assert_output exact match
@test "smoke_test_assert_output" {
    run echo "hello world"
    assert_output "hello world"
}

# Spec reference: bats-assert - assert_output --partial
@test "smoke_test_assert_output_partial" {
    run echo "hello world"
    assert_output --partial "world"
}

# Spec reference: bats-assert - assert_line
@test "smoke_test_assert_line" {
    run printf "line1\nline2\nline3"
    assert_line --index 0 "line1"
    assert_line --index 1 "line2"
    assert_line --index 2 "line3"
}

# Spec reference: bats-assert - refute_output
@test "smoke_test_refute_output" {
    run echo "hello"
    refute_output "goodbye"
}

# Spec reference: bats-file - assert_file_exists
@test "smoke_test_file_exists" {
    local test_file="${TEST_TEMP_DIR}/test_file.txt"
    echo "content" > "${test_file}"
    assert_file_exists "${test_file}"
}

# Spec reference: bats-file - assert_dir_exists
@test "smoke_test_dir_exists" {
    local test_dir="${TEST_TEMP_DIR}/test_dir"
    mkdir -p "${test_dir}"
    assert_dir_exists "${test_dir}"
}

# Spec reference: Test Helper Configuration - TEST_TEMP_DIR is available
@test "smoke_test_temp_dir_available" {
    # Verify TEST_TEMP_DIR exists and is writable
    assert_dir_exists "${TEST_TEMP_DIR}"

    # Verify we can write to it
    local test_file="${TEST_TEMP_DIR}/write_test.txt"
    echo "test content" > "${test_file}"
    assert_file_exists "${test_file}"
}
# minor test trigger
