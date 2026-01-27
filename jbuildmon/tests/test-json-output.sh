#!/usr/bin/env bash
#
# Test script for Chunk 10: JSON Output Functions
#
# Tests:
# 1. output_json for successful build
# 2. output_json for failed build with failure info
# 3. output_json for in-progress build
# 4. JSON structure validation with jq
# 5. Correct handling of null/missing values
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
# Test output_json for successful build
# =============================================================================
echo ""
echo "Testing output_json for successful build..."

mock_success_json='{
    "number": 142,
    "result": "SUCCESS",
    "building": false,
    "timestamp": 1705329125000,
    "duration": 154000,
    "url": "https://jenkins.example.com/job/my-project/142/"
}'

# Test: Valid JSON output
run_test
output=$(output_json "my-project" "142" "$mock_success_json" "automated" "buildtriggerdude" "abc1234def5678" "Fix login bug" "in_history")

# Validate it's valid JSON
if echo "$output" | jq . >/dev/null 2>&1; then
    pass "Output is valid JSON"
else
    fail "Output is valid JSON" "valid JSON" "invalid JSON"
fi

# Test: Contains job field
run_test
job_value=$(echo "$output" | jq -r '.job')
if [[ "$job_value" == "my-project" ]]; then
    pass "JSON contains correct job name"
else
    fail "JSON contains correct job name" "my-project" "$job_value"
fi

# Test: Contains build.number
run_test
build_number=$(echo "$output" | jq -r '.build.number')
if [[ "$build_number" == "142" ]]; then
    pass "JSON contains correct build number"
else
    fail "JSON contains correct build number" "142" "$build_number"
fi

# Test: Contains build.status
run_test
build_status=$(echo "$output" | jq -r '.build.status')
if [[ "$build_status" == "SUCCESS" ]]; then
    pass "JSON contains correct build status"
else
    fail "JSON contains correct build status" "SUCCESS" "$build_status"
fi

# Test: Contains build.building (false)
run_test
building=$(echo "$output" | jq -r '.build.building')
if [[ "$building" == "false" ]]; then
    pass "JSON contains building=false"
else
    fail "JSON contains building=false" "false" "$building"
fi

# Test: Contains duration_seconds
run_test
duration=$(echo "$output" | jq -r '.build.duration_seconds')
if [[ "$duration" == "154" ]]; then
    pass "JSON contains correct duration_seconds (154)"
else
    fail "JSON contains correct duration_seconds" "154" "$duration"
fi

# Test: Contains ISO timestamp
run_test
timestamp=$(echo "$output" | jq -r '.build.timestamp')
if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    pass "JSON contains ISO format timestamp ($timestamp)"
else
    fail "JSON contains ISO format timestamp" "YYYY-MM-DDTHH:MM:SSZ" "$timestamp"
fi

# Test: Contains trigger.type
run_test
trigger_type=$(echo "$output" | jq -r '.trigger.type')
if [[ "$trigger_type" == "automated" ]]; then
    pass "JSON contains correct trigger type"
else
    fail "JSON contains correct trigger type" "automated" "$trigger_type"
fi

# Test: Contains trigger.user
run_test
trigger_user=$(echo "$output" | jq -r '.trigger.user')
if [[ "$trigger_user" == "buildtriggerdude" ]]; then
    pass "JSON contains correct trigger user"
else
    fail "JSON contains correct trigger user" "buildtriggerdude" "$trigger_user"
fi

# Test: Contains commit.sha
run_test
commit_sha=$(echo "$output" | jq -r '.commit.sha')
if [[ "$commit_sha" == "abc1234def5678" ]]; then
    pass "JSON contains correct commit SHA"
else
    fail "JSON contains correct commit SHA" "abc1234def5678" "$commit_sha"
fi

# Test: Contains commit.message
run_test
commit_msg=$(echo "$output" | jq -r '.commit.message')
if [[ "$commit_msg" == "Fix login bug" ]]; then
    pass "JSON contains correct commit message"
else
    fail "JSON contains correct commit message" "Fix login bug" "$commit_msg"
fi

# Test: in_history correlation (in_local_history=true, reachable_from_head=true, is_head=false)
run_test
in_local=$(echo "$output" | jq -r '.commit.in_local_history')
reachable=$(echo "$output" | jq -r '.commit.reachable_from_head')
is_head=$(echo "$output" | jq -r '.commit.is_head')
if [[ "$in_local" == "true" && "$reachable" == "true" && "$is_head" == "false" ]]; then
    pass "JSON contains correct in_history correlation flags"
else
    fail "JSON contains correct in_history correlation flags" "in_local=true, reachable=true, is_head=false" "in_local=$in_local, reachable=$reachable, is_head=$is_head"
fi

# Test: Contains console_url
run_test
console_url=$(echo "$output" | jq -r '.console_url')
if [[ "$console_url" == "https://jenkins.example.com/job/my-project/142/console" ]]; then
    pass "JSON contains correct console URL"
else
    fail "JSON contains correct console URL" "https://jenkins.example.com/job/my-project/142/console" "$console_url"
fi

# Test: No failure object for success
run_test
has_failure=$(echo "$output" | jq 'has("failure")')
if [[ "$has_failure" == "false" ]]; then
    pass "JSON does not contain failure object for success"
else
    fail "JSON does not contain failure object for success" "no failure object" "has failure object"
fi

# =============================================================================
# Test output_json for in-progress build
# =============================================================================
echo ""
echo "Testing output_json for in-progress build..."

mock_building_json='{
    "number": 144,
    "result": null,
    "building": true,
    "timestamp": 1705330000000,
    "duration": 0,
    "url": "https://jenkins.example.com/job/my-project/144/"
}'

# Test: building=true output
run_test
output=$(output_json "my-project" "144" "$mock_building_json" "automated" "buildtriggerdude" "789abcd" "Update deps" "your_commit")

building=$(echo "$output" | jq -r '.build.building')
if [[ "$building" == "true" ]]; then
    pass "In-progress build has building=true"
else
    fail "In-progress build has building=true" "true" "$building"
fi

# Test: status is null for in-progress
run_test
status=$(echo "$output" | jq -r '.build.status')
if [[ "$status" == "null" ]]; then
    pass "In-progress build has status=null"
else
    fail "In-progress build has status=null" "null" "$status"
fi

# Test: your_commit correlation (is_head=true)
run_test
is_head=$(echo "$output" | jq -r '.commit.is_head')
in_local=$(echo "$output" | jq -r '.commit.in_local_history')
reachable=$(echo "$output" | jq -r '.commit.reachable_from_head')
if [[ "$is_head" == "true" && "$in_local" == "true" && "$reachable" == "true" ]]; then
    pass "your_commit correlation has correct flags"
else
    fail "your_commit correlation has correct flags" "is_head=true, in_local=true, reachable=true" "is_head=$is_head, in_local=$in_local, reachable=$reachable"
fi

# =============================================================================
# Test output_json for failed build
# =============================================================================
echo ""
echo "Testing output_json for failed build..."

mock_failure_json='{
    "number": 143,
    "result": "FAILURE",
    "building": false,
    "timestamp": 1705333822000,
    "duration": 72000,
    "url": "https://jenkins.example.com/job/my-project/143/"
}'

# Mock console output with build info
mock_console="Started by user jsmith
Running on build-agent-01 in /workspace
Obtained Jenkinsfile from git ssh://git@server/repo.git
[Pipeline] stage
[Pipeline] { (Build)
Building...
[Pipeline] }
[Pipeline] stage
[Pipeline] { (Test)
ERROR: Test failed: testUserLogin
java.lang.AssertionError: expected:<200> but was:<401>
[Pipeline] }
"

# Test: Failed build output with console
run_test
output=$(output_json "my-project" "143" "$mock_failure_json" "manual" "jsmith" "def5678" "Add feature" "not_in_history" "$mock_console")

# Valid JSON
if echo "$output" | jq . >/dev/null 2>&1; then
    pass "Failed build output is valid JSON"
else
    fail "Failed build output is valid JSON" "valid JSON" "invalid JSON"
fi

# Test: Contains failure object
run_test
has_failure=$(echo "$output" | jq 'has("failure")')
if [[ "$has_failure" == "true" ]]; then
    pass "Failed build JSON contains failure object"
else
    fail "Failed build JSON contains failure object" "has failure" "no failure"
fi

# Test: Contains build_info object
run_test
has_build_info=$(echo "$output" | jq 'has("build_info")')
if [[ "$has_build_info" == "true" ]]; then
    pass "Failed build JSON contains build_info object"
else
    fail "Failed build JSON contains build_info object" "has build_info" "no build_info"
fi

# Test: build_info.started_by
run_test
started_by=$(echo "$output" | jq -r '.build_info.started_by')
if [[ "$started_by" == "jsmith" ]]; then
    pass "build_info.started_by is correct"
else
    fail "build_info.started_by is correct" "jsmith" "$started_by"
fi

# Test: build_info.agent
run_test
agent=$(echo "$output" | jq -r '.build_info.agent')
if [[ "$agent" == "build-agent-01" ]]; then
    pass "build_info.agent is correct"
else
    fail "build_info.agent is correct" "build-agent-01" "$agent"
fi

# Test: build_info.pipeline
run_test
pipeline=$(echo "$output" | jq -r '.build_info.pipeline')
if [[ "$pipeline" == "Jenkinsfile from git ssh://git@server/repo.git" ]]; then
    pass "build_info.pipeline is correct"
else
    fail "build_info.pipeline is correct" "Jenkinsfile from git ssh://git@server/repo.git" "$pipeline"
fi

# Test: failure.failed_jobs is array
run_test
failed_jobs_type=$(echo "$output" | jq -r '.failure.failed_jobs | type')
if [[ "$failed_jobs_type" == "array" ]]; then
    pass "failure.failed_jobs is an array"
else
    fail "failure.failed_jobs is an array" "array" "$failed_jobs_type"
fi

# Test: failure.root_cause_job
run_test
root_cause=$(echo "$output" | jq -r '.failure.root_cause_job')
if [[ "$root_cause" == "my-project" ]]; then
    pass "failure.root_cause_job is correct"
else
    fail "failure.root_cause_job is correct" "my-project" "$root_cause"
fi

# Test: error_summary contains error text
run_test
error_summary=$(echo "$output" | jq -r '.failure.error_summary // ""')
if [[ "$error_summary" == *"ERROR"* || "$error_summary" == *"Test failed"* || "$error_summary" == *"AssertionError"* ]]; then
    pass "error_summary contains error information"
else
    fail "error_summary contains error information" "error text" "$error_summary"
fi

# Test: not_in_history correlation (in_local=true, reachable=false, is_head=false)
run_test
in_local=$(echo "$output" | jq -r '.commit.in_local_history')
reachable=$(echo "$output" | jq -r '.commit.reachable_from_head')
is_head=$(echo "$output" | jq -r '.commit.is_head')
if [[ "$in_local" == "true" && "$reachable" == "false" && "$is_head" == "false" ]]; then
    pass "not_in_history correlation has correct flags"
else
    fail "not_in_history correlation has correct flags" "in_local=true, reachable=false, is_head=false" "in_local=$in_local, reachable=$reachable, is_head=$is_head"
fi

# =============================================================================
# Test unknown commit correlation
# =============================================================================
echo ""
echo "Testing unknown commit correlation..."

run_test
output=$(output_json "my-project" "142" "$mock_success_json" "automated" "buildtriggerdude" "unknown" "unknown" "unknown")

in_local=$(echo "$output" | jq -r '.commit.in_local_history')
reachable=$(echo "$output" | jq -r '.commit.reachable_from_head')
is_head=$(echo "$output" | jq -r '.commit.is_head')
if [[ "$in_local" == "false" && "$reachable" == "false" && "$is_head" == "false" ]]; then
    pass "unknown correlation has all flags false"
else
    fail "unknown correlation has all flags false" "all false" "in_local=$in_local, reachable=$reachable, is_head=$is_head"
fi

# =============================================================================
# Test _extract_error_summary
# =============================================================================
echo ""
echo "Testing _extract_error_summary..."

# Test: Extracts ERROR line
run_test
summary=$(_extract_error_summary "Some output
ERROR: Build failed due to tests
More output")
if [[ "$summary" == *"ERROR"* && "$summary" == *"Build failed"* ]]; then
    pass "Extracts ERROR line"
else
    fail "Extracts ERROR line" "ERROR: Build failed..." "$summary"
fi

# Test: Extracts AssertionError
run_test
summary=$(_extract_error_summary "Running tests
java.lang.AssertionError: expected 200 but got 401
Stack trace follows")
if [[ "$summary" == *"AssertionError"* ]]; then
    pass "Extracts AssertionError"
else
    fail "Extracts AssertionError" "AssertionError..." "$summary"
fi

# Test: Extracts test failure
run_test
summary=$(_extract_error_summary "Building
Test testLogin failed: connection refused
Done")
if [[ "$summary" == *"Test"* && "$summary" == *"failed"* ]]; then
    pass "Extracts test failure line"
else
    fail "Extracts test failure line" "Test...failed..." "$summary"
fi

# =============================================================================
# Test _build_info_json
# =============================================================================
echo ""
echo "Testing _build_info_json..."

# Test: Extracts all fields
run_test
info_json=$(_build_info_json "Started by user testuser
Running on agent-5 in /workspace
Obtained Jenkinsfile from git https://github.com/org/repo.git
Build starting")

# Valid JSON
if echo "$info_json" | jq . >/dev/null 2>&1; then
    pass "_build_info_json returns valid JSON"
else
    fail "_build_info_json returns valid JSON" "valid JSON" "invalid"
fi

# Check fields
run_test
started=$(echo "$info_json" | jq -r '.started_by')
agent=$(echo "$info_json" | jq -r '.agent')
pipeline=$(echo "$info_json" | jq -r '.pipeline')
if [[ "$started" == "testuser" && "$agent" == "agent-5" && "$pipeline" == *"Jenkinsfile"* ]]; then
    pass "_build_info_json extracts correct fields"
else
    fail "_build_info_json extracts correct fields" "testuser, agent-5, Jenkinsfile..." "started=$started, agent=$agent, pipeline=$pipeline"
fi

# Test: Empty console returns nulls
run_test
info_json=$(_build_info_json "")
started=$(echo "$info_json" | jq -r '.started_by')
if [[ "$started" == "null" ]]; then
    pass "Empty console returns null for started_by"
else
    fail "Empty console returns null for started_by" "null" "$started"
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
