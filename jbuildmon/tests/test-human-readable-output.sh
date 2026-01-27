#!/usr/bin/env bash
#
# Test script for Chunk 9: Human-Readable Output Functions
#
# Tests:
# 1. format_duration with various inputs
# 2. format_timestamp with epoch milliseconds
# 3. display_success_output format
# 4. display_failure_output format
# 5. display_building_output format
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/jenkins-common.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    ((TESTS_PASSED++))
    echo "  ✓ $1"
}

fail() {
    ((TESTS_FAILED++))
    echo "  ✗ $1"
    echo "    Expected: $2"
    echo "    Got:      $3"
}

run_test() {
    ((TESTS_RUN++))
}

# =============================================================================
# Test format_duration
# =============================================================================
echo ""
echo "Testing format_duration..."

# Test 1: 154000ms → "2m 34s"
run_test
result=$(format_duration 154000)
if [[ "$result" == "2m 34s" ]]; then
    pass "154000ms → '2m 34s'"
else
    fail "154000ms → '2m 34s'" "2m 34s" "$result"
fi

# Test 2: 45000ms → "45s"
run_test
result=$(format_duration 45000)
if [[ "$result" == "45s" ]]; then
    pass "45000ms → '45s'"
else
    fail "45000ms → '45s'" "45s" "$result"
fi

# Test 3: 3661000ms → "1h 1m 1s"
run_test
result=$(format_duration 3661000)
if [[ "$result" == "1h 1m 1s" ]]; then
    pass "3661000ms → '1h 1m 1s'"
else
    fail "3661000ms → '1h 1m 1s'" "1h 1m 1s" "$result"
fi

# Test 4: 0ms → "0s"
run_test
result=$(format_duration 0)
if [[ "$result" == "0s" ]]; then
    pass "0ms → '0s'"
else
    fail "0ms → '0s'" "0s" "$result"
fi

# Test 5: Empty input → "unknown"
run_test
result=$(format_duration "")
if [[ "$result" == "unknown" ]]; then
    pass "empty → 'unknown'"
else
    fail "empty → 'unknown'" "unknown" "$result"
fi

# Test 6: Invalid input → "unknown"
run_test
result=$(format_duration "invalid")
if [[ "$result" == "unknown" ]]; then
    pass "invalid → 'unknown'"
else
    fail "invalid → 'unknown'" "unknown" "$result"
fi

# =============================================================================
# Test format_timestamp
# =============================================================================
echo ""
echo "Testing format_timestamp..."

# Test 1: Valid epoch → returns formatted date
run_test
result=$(format_timestamp 1705329125000)
# Just check it returns a valid date format (YYYY-MM-DD HH:MM:SS)
if [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    pass "Valid epoch → returns formatted date ($result)"
else
    fail "Valid epoch → returns formatted date" "YYYY-MM-DD HH:MM:SS format" "$result"
fi

# Test 2: Empty input → "unknown"
run_test
result=$(format_timestamp "")
if [[ "$result" == "unknown" ]]; then
    pass "empty → 'unknown'"
else
    fail "empty → 'unknown'" "unknown" "$result"
fi

# Test 3: null → "unknown"
run_test
result=$(format_timestamp "null")
if [[ "$result" == "unknown" ]]; then
    pass "null → 'unknown'"
else
    fail "null → 'unknown'" "unknown" "$result"
fi

# =============================================================================
# Test format_timestamp_iso
# =============================================================================
echo ""
echo "Testing format_timestamp_iso..."

# Test 1: Valid epoch → returns ISO format
run_test
result=$(format_timestamp_iso 1705329125000)
if [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    pass "Valid epoch → returns ISO format ($result)"
else
    fail "Valid epoch → returns ISO format" "YYYY-MM-DDTHH:MM:SSZ format" "$result"
fi

# Test 2: Empty → "null"
run_test
result=$(format_timestamp_iso "")
if [[ "$result" == "null" ]]; then
    pass "empty → 'null'"
else
    fail "empty → 'null'" "null" "$result"
fi

# =============================================================================
# Test display_success_output (output format verification)
# =============================================================================
echo ""
echo "Testing display_success_output..."

# Create mock build JSON
mock_build_json='{
    "number": 142,
    "result": "SUCCESS",
    "building": false,
    "timestamp": 1705329125000,
    "duration": 154000,
    "url": "https://jenkins.example.com/job/my-project/142/"
}'

# Test: Success output contains expected elements
run_test
output=$(display_success_output "my-project" "142" "$mock_build_json" "automated" "buildtriggerdude" "abc1234def5678" "Fix login bug" "in_history")

# Check for banner
if echo "$output" | grep -q "BUILD SUCCESSFUL"; then
    pass "Success output contains banner"
else
    fail "Success output contains banner" "BUILD SUCCESSFUL banner" "not found"
fi

# Check for job name
run_test
if echo "$output" | grep -q "Job:.*my-project"; then
    pass "Success output contains job name"
else
    fail "Success output contains job name" "Job: my-project" "not found"
fi

# Check for build number
run_test
if echo "$output" | grep -q "Build:.*#142"; then
    pass "Success output contains build number"
else
    fail "Success output contains build number" "Build: #142" "not found"
fi

# Check for SUCCESS status
run_test
if echo "$output" | grep -q "Status:.*SUCCESS"; then
    pass "Success output contains SUCCESS status"
else
    fail "Success output contains SUCCESS status" "Status: SUCCESS" "not found"
fi

# Check for trigger
run_test
if echo "$output" | grep -q "Trigger:.*Automated (git push)"; then
    pass "Success output contains trigger info"
else
    fail "Success output contains trigger info" "Trigger: Automated (git push)" "not found"
fi

# Check for commit info
run_test
if echo "$output" | grep -q "Commit:.*abc1234"; then
    pass "Success output contains commit SHA"
else
    fail "Success output contains commit SHA" "abc1234" "not found"
fi

# Check for correlation status
run_test
if echo "$output" | grep -q "In your history"; then
    pass "Success output contains correlation status"
else
    fail "Success output contains correlation status" "In your history" "not found"
fi

# Check for duration
run_test
if echo "$output" | grep -q "Duration:.*2m 34s"; then
    pass "Success output contains formatted duration"
else
    fail "Success output contains formatted duration" "Duration: 2m 34s" "not found"
fi

# Check for console URL
run_test
if echo "$output" | grep -q "Console:.*https://jenkins.example.com/job/my-project/142/console"; then
    pass "Success output contains console URL"
else
    fail "Success output contains console URL" "Console: .../console" "not found"
fi

# =============================================================================
# Test display_building_output (output format verification)
# =============================================================================
echo ""
echo "Testing display_building_output..."

# Create mock build JSON for in-progress build
# Use current time minus 3 minutes for timestamp
now_ms=$(($(date +%s) * 1000))
three_min_ago=$((now_ms - 201000))  # 3m 21s ago
mock_building_json="{
    \"number\": 144,
    \"result\": null,
    \"building\": true,
    \"timestamp\": ${three_min_ago},
    \"duration\": 0,
    \"url\": \"https://jenkins.example.com/job/my-project/144/\"
}"

# Test: Building output contains expected elements
run_test
output=$(display_building_output "my-project" "144" "$mock_building_json" "automated" "buildtriggerdude" "789abcd" "Update dependencies" "your_commit" "Running Tests")

# Check for banner
if echo "$output" | grep -q "BUILD IN PROGRESS"; then
    pass "Building output contains banner"
else
    fail "Building output contains banner" "BUILD IN PROGRESS banner" "not found"
fi

# Check for BUILDING status
run_test
if echo "$output" | grep -q "Status:.*BUILDING"; then
    pass "Building output contains BUILDING status"
else
    fail "Building output contains BUILDING status" "Status: BUILDING" "not found"
fi

# Check for current stage
run_test
if echo "$output" | grep -q "Stage:.*Running Tests"; then
    pass "Building output contains current stage"
else
    fail "Building output contains current stage" "Stage: Running Tests" "not found"
fi

# Check for "Your commit (HEAD)" correlation
run_test
if echo "$output" | grep -q "Your commit (HEAD)"; then
    pass "Building output contains 'Your commit (HEAD)' correlation"
else
    fail "Building output contains 'Your commit (HEAD)' correlation" "Your commit (HEAD)" "not found"
fi

# Check for elapsed time (should be around 3m)
run_test
if echo "$output" | grep -q "Elapsed:.*[0-9]"; then
    pass "Building output contains elapsed time"
else
    fail "Building output contains elapsed time" "Elapsed: Nm Ns" "not found"
fi

# =============================================================================
# Test display_failure_output (basic format - no actual Jenkins calls)
# =============================================================================
echo ""
echo "Testing display_failure_output (basic format)..."

mock_failure_json='{
    "number": 143,
    "result": "FAILURE",
    "building": false,
    "timestamp": 1705333822000,
    "duration": 72000,
    "url": "https://jenkins.example.com/job/my-project/143/"
}'

# Mock console output
mock_console="Started by user jsmith
Running on build-agent-01 in /workspace
Obtained Jenkinsfile from git ssh://git@server/repo.git
[Pipeline] stage
[Pipeline] { (Build)
Building...
[Pipeline] }
[Pipeline] stage
[Pipeline] { (Test)
ERROR: Test failed
java.lang.AssertionError: expected 200 but was 401
[Pipeline] }
"

# Test: Failure output contains expected elements
run_test
# Note: This will try to make API calls which will fail, so we just check the basic output structure
output=$(display_failure_output "my-project" "143" "$mock_failure_json" "manual" "jsmith" "def5678" "Add new feature" "not_in_history" "$mock_console" 2>/dev/null || true)

# Check for failure banner
if echo "$output" | grep -q "BUILD FAILED"; then
    pass "Failure output contains banner"
else
    fail "Failure output contains banner" "BUILD FAILED banner" "not found"
fi

# Check for FAILURE status
run_test
if echo "$output" | grep -q "Status:.*FAILURE"; then
    pass "Failure output contains FAILURE status"
else
    fail "Failure output contains FAILURE status" "Status: FAILURE" "not found"
fi

# Check for manual trigger
run_test
if echo "$output" | grep -q "Trigger:.*Manual (started by jsmith)"; then
    pass "Failure output contains manual trigger"
else
    fail "Failure output contains manual trigger" "Trigger: Manual (started by jsmith)" "not found"
fi

# Check for "Not in your history" correlation
run_test
if echo "$output" | grep -q "Not in your history"; then
    pass "Failure output contains 'Not in your history' correlation"
else
    fail "Failure output contains 'Not in your history' correlation" "Not in your history" "not found"
fi

# Check for Build Info section
run_test
if echo "$output" | grep -q "=== Build Info ==="; then
    pass "Failure output contains Build Info section"
else
    fail "Failure output contains Build Info section" "=== Build Info ===" "not found"
fi

# Check for Failed Jobs section
run_test
if echo "$output" | grep -q "=== Failed Jobs ==="; then
    pass "Failure output contains Failed Jobs section"
else
    fail "Failure output contains Failed Jobs section" "=== Failed Jobs ===" "not found"
fi

# Check for Error Logs section
run_test
if echo "$output" | grep -q "=== Error Logs ==="; then
    pass "Failure output contains Error Logs section"
else
    fail "Failure output contains Error Logs section" "=== Error Logs ===" "not found"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================"
echo "Test Summary"
echo "============================================"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
