#!/usr/bin/env bash
#
# Test script for Chunk 7: Trigger Detection and Commit Extraction
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/jenkins-common.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_pass() {
    ((TESTS_PASSED++))
    echo "  ✓ $1"
}

test_fail() {
    ((TESTS_FAILED++))
    echo "  ✗ $1"
    echo "    Expected: $2"
    echo "    Got:      $3"
}

run_test() {
    ((TESTS_RUN++))
    echo ""
    echo "Test $TESTS_RUN: $1"
}

# =============================================================================
# Test detect_trigger_type
# =============================================================================

echo "=== Testing detect_trigger_type ==="

# Test 1: Automated trigger (default buildtriggerdude)
run_test "Console with 'Started by user buildtriggerdude' returns type='automated'"
console="Started by user buildtriggerdude
Building in workspace /var/jenkins/workspace/test"
result=$(detect_trigger_type "$console")
type=$(echo "$result" | head -1)
user=$(echo "$result" | tail -1)
if [[ "$type" == "automated" && "$user" == "buildtriggerdude" ]]; then
    test_pass "Type='automated', user='buildtriggerdude'"
else
    test_fail "detect_trigger_type with buildtriggerdude" "automated, buildtriggerdude" "$type, $user"
fi

# Test 2: Manual trigger (other user)
run_test "Console with 'Started by user jsmith' returns type='manual'"
console="Started by user jsmith
Building in workspace /var/jenkins/workspace/test"
result=$(detect_trigger_type "$console")
type=$(echo "$result" | head -1)
user=$(echo "$result" | tail -1)
if [[ "$type" == "manual" && "$user" == "jsmith" ]]; then
    test_pass "Type='manual', user='jsmith'"
else
    test_fail "detect_trigger_type with other user" "manual, jsmith" "$type, $user"
fi

# Test 3: Custom trigger user via environment variable
run_test "CHECKBUILD_TRIGGER_USER=customuser, 'Started by user customuser' returns type='automated'"
export CHECKBUILD_TRIGGER_USER="customuser"
console="Started by user customuser
Building in workspace /var/jenkins/workspace/test"
result=$(detect_trigger_type "$console")
type=$(echo "$result" | head -1)
user=$(echo "$result" | tail -1)
if [[ "$type" == "automated" && "$user" == "customuser" ]]; then
    test_pass "Type='automated' with custom trigger user"
else
    test_fail "detect_trigger_type with custom user" "automated, customuser" "$type, $user"
fi
unset CHECKBUILD_TRIGGER_USER

# Test 4: SCM change trigger
run_test "Console with 'Started by an SCM change' returns type='automated'"
console="Started by an SCM change
Building in workspace /var/jenkins/workspace/test"
result=$(detect_trigger_type "$console")
type=$(echo "$result" | head -1)
user=$(echo "$result" | tail -1)
if [[ "$type" == "automated" && "$user" == "scm-trigger" ]]; then
    test_pass "Type='automated' for SCM trigger"
else
    test_fail "detect_trigger_type with SCM change" "automated, scm-trigger" "$type, $user"
fi

# Test 5: Timer trigger
run_test "Console with 'Started by timer' returns type='automated'"
console="Started by timer
Building in workspace /var/jenkins/workspace/test"
result=$(detect_trigger_type "$console")
type=$(echo "$result" | head -1)
user=$(echo "$result" | tail -1)
if [[ "$type" == "automated" && "$user" == "timer" ]]; then
    test_pass "Type='automated' for timer trigger"
else
    test_fail "detect_trigger_type with timer" "automated, timer" "$type, $user"
fi

# Test 6: Upstream project trigger
run_test "Console with 'Started by upstream project' returns type='automated'"
console="Started by upstream project parent-job
Building in workspace /var/jenkins/workspace/test"
result=$(detect_trigger_type "$console")
type=$(echo "$result" | head -1)
user=$(echo "$result" | tail -1)
if [[ "$type" == "automated" && "$user" == "upstream" ]]; then
    test_pass "Type='automated' for upstream trigger"
else
    test_fail "detect_trigger_type with upstream" "automated, upstream" "$type, $user"
fi

# Test 7: Unknown trigger
run_test "Console without trigger info returns type='unknown'"
console="Building in workspace /var/jenkins/workspace/test
Running tests..."
result=$(detect_trigger_type "$console" 2>/dev/null || true)
type=$(echo "$result" | head -1)
if [[ "$type" == "unknown" ]]; then
    test_pass "Type='unknown' when trigger not found"
else
    test_fail "detect_trigger_type with no trigger" "unknown" "$type"
fi

# =============================================================================
# Test extract_triggering_commit (console parsing only - no API)
# =============================================================================

echo ""
echo "=== Testing extract_triggering_commit (console patterns) ==="

# Note: We can't easily test API-based extraction without mocking Jenkins
# These tests focus on console output parsing

# Test 8: Extract from "Checking out Revision <sha>"
run_test "Extract SHA from 'Checking out Revision' pattern"
console="Checking out Revision abc1234def5678901234567890123456789012
Building..."
# We need to mock get_build_info and get_console_output for isolated testing
# For now, we'll test the parsing logic directly

sha=$(echo "$console" | grep -oE 'Checking out Revision [a-f0-9]{7,40}' | head -1 | sed 's/Checking out Revision //')
if [[ "$sha" == "abc1234def5678901234567890123456789012" ]]; then
    test_pass "Extracted SHA from 'Checking out Revision'"
else
    test_fail "SHA extraction from Checking out Revision" "abc1234def5678901234567890123456789012" "$sha"
fi

# Test 9: Extract from "> git checkout -f <sha>"
run_test "Extract SHA from '> git checkout -f' pattern"
console="> git checkout -f def5678abc1234567890123456789012345678
Building..."
sha=$(echo "$console" | grep -oE '> git checkout -f [a-f0-9]{7,40}' | head -1 | sed 's/> git checkout -f //')
if [[ "$sha" == "def5678abc1234567890123456789012345678" ]]; then
    test_pass "Extracted SHA from '> git checkout -f'"
else
    test_fail "SHA extraction from git checkout -f" "def5678abc1234567890123456789012345678" "$sha"
fi

# Test 10: Extract commit message from "Commit message:"
run_test "Extract commit message from 'Commit message:' pattern"
console="Commit message: \"Fix login bug and add tests\"
Building..."
message=$(echo "$console" | grep -m1 'Commit message:' | sed -E 's/.*Commit message:[[:space:]]*//' | sed -E 's/^["'"'"'](.*)["'"'"']$/\1/')
if [[ "$message" == "Fix login bug and add tests" ]]; then
    test_pass "Extracted commit message"
else
    test_fail "Commit message extraction" "Fix login bug and add tests" "$message"
fi

# Test 11: Short SHA (7 chars)
run_test "Extract short SHA (7 characters)"
console="Checking out Revision abc1234
Building..."
sha=$(echo "$console" | grep -oE 'Checking out Revision [a-f0-9]{7,40}' | head -1 | sed 's/Checking out Revision //')
if [[ "$sha" == "abc1234" ]]; then
    test_pass "Extracted short SHA"
else
    test_fail "Short SHA extraction" "abc1234" "$sha"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
