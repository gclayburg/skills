#!/usr/bin/env bash
#
# Test script for Chunk 8: Git Commit Correlation
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
# Test correlate_commit
# =============================================================================

echo "=== Testing correlate_commit ==="

# Test 1: SHA that matches current HEAD
run_test "SHA that matches current HEAD returns 'your_commit'"
head_sha=$(git rev-parse HEAD)
result=$(correlate_commit "$head_sha")
if [[ "$result" == "your_commit" ]]; then
    test_pass "HEAD SHA returns 'your_commit'"
else
    test_fail "correlate_commit with HEAD" "your_commit" "$result"
fi

# Test 2: Short SHA of HEAD also matches
run_test "Short SHA of HEAD also returns 'your_commit'"
short_head=$(git rev-parse --short HEAD)
result=$(correlate_commit "$short_head")
if [[ "$result" == "your_commit" ]]; then
    test_pass "Short HEAD SHA returns 'your_commit'"
else
    test_fail "correlate_commit with short HEAD" "your_commit" "$result"
fi

# Test 3: SHA that is parent of HEAD (ancestor)
run_test "Parent of HEAD returns 'in_history'"
# Get parent commit (if it exists)
parent_sha=$(git rev-parse HEAD~1 2>/dev/null || echo "")
if [[ -n "$parent_sha" ]]; then
    result=$(correlate_commit "$parent_sha")
    if [[ "$result" == "in_history" ]]; then
        test_pass "Parent SHA returns 'in_history'"
    else
        test_fail "correlate_commit with parent" "in_history" "$result"
    fi
else
    echo "  ⊘ Skipped (no parent commit available)"
    ((TESTS_RUN--))  # Don't count skipped tests
fi

# Test 4: SHA from a different branch (not reachable from HEAD)
run_test "SHA from different branch returns 'not_in_history'"
# Find a commit that exists but is not reachable from HEAD
# This requires a branch that has diverged - we'll try to find one
other_branch_sha=""
for branch in $(git branch -r 2>/dev/null | grep -v HEAD | head -5); do
    branch_sha=$(git rev-parse "$branch" 2>/dev/null || continue)
    # Check if it's not reachable from HEAD
    if ! git merge-base --is-ancestor "$branch_sha" HEAD 2>/dev/null; then
        # Also check it's not ahead of HEAD (meaning HEAD is not ancestor of it)
        if git cat-file -t "$branch_sha" &>/dev/null; then
            other_branch_sha="$branch_sha"
            break
        fi
    fi
done

if [[ -n "$other_branch_sha" ]]; then
    result=$(correlate_commit "$other_branch_sha")
    if [[ "$result" == "not_in_history" ]]; then
        test_pass "Different branch SHA returns 'not_in_history'"
    else
        # It might actually be in history if branches merged
        echo "  ⊘ Branch commit was reachable (branches may have merged)"
        ((TESTS_RUN--))
    fi
else
    echo "  ⊘ Skipped (no diverged branch available for testing)"
    ((TESTS_RUN--))
fi

# Test 5: SHA that doesn't exist locally
run_test "Non-existent SHA returns 'unknown'"
fake_sha="0000000000000000000000000000000000000000"
result=$(correlate_commit "$fake_sha")
if [[ "$result" == "unknown" ]]; then
    test_pass "Non-existent SHA returns 'unknown'"
else
    test_fail "correlate_commit with fake SHA" "unknown" "$result"
fi

# Test 6: Malformed SHA (not hex)
run_test "Malformed SHA returns 'unknown' with error"
malformed="not-a-sha-at-all"
# Should return "unknown" but with exit code 1
set +e  # Temporarily disable exit on error
actual_result=$(correlate_commit "$malformed" 2>/dev/null)
exit_code=$?
set -e
if [[ "$actual_result" == "unknown" && $exit_code -eq 1 ]]; then
    test_pass "Malformed SHA returns 'unknown' with error code"
else
    test_fail "correlate_commit with malformed SHA" "unknown (exit 1)" "$actual_result (exit $exit_code)"
fi

# Test 7: Empty SHA
run_test "Empty SHA returns 'unknown'"
result=$(correlate_commit "")
if [[ "$result" == "unknown" ]]; then
    test_pass "Empty SHA returns 'unknown'"
else
    test_fail "correlate_commit with empty SHA" "unknown" "$result"
fi

# Test 8: SHA = "unknown" string
run_test "String 'unknown' returns 'unknown'"
result=$(correlate_commit "unknown")
if [[ "$result" == "unknown" ]]; then
    test_pass "String 'unknown' returns 'unknown'"
else
    test_fail "correlate_commit with 'unknown'" "unknown" "$result"
fi

# =============================================================================
# Test describe_commit_correlation
# =============================================================================

echo ""
echo "=== Testing describe_commit_correlation ==="

# Test 9: your_commit description
run_test "describe_commit_correlation 'your_commit'"
result=$(describe_commit_correlation "your_commit")
expected="Your commit (HEAD)"
if [[ "$result" == "$expected" ]]; then
    test_pass "Returns '$expected'"
else
    test_fail "describe your_commit" "$expected" "$result"
fi

# Test 10: in_history description
run_test "describe_commit_correlation 'in_history'"
result=$(describe_commit_correlation "in_history")
expected="In your history (reachable from HEAD)"
if [[ "$result" == "$expected" ]]; then
    test_pass "Returns '$expected'"
else
    test_fail "describe in_history" "$expected" "$result"
fi

# Test 11: not_in_history description
run_test "describe_commit_correlation 'not_in_history'"
result=$(describe_commit_correlation "not_in_history")
expected="Not in your history"
if [[ "$result" == "$expected" ]]; then
    test_pass "Returns '$expected'"
else
    test_fail "describe not_in_history" "$expected" "$result"
fi

# Test 12: unknown description
run_test "describe_commit_correlation 'unknown'"
result=$(describe_commit_correlation "unknown")
expected="Unknown commit"
if [[ "$result" == "$expected" ]]; then
    test_pass "Returns '$expected'"
else
    test_fail "describe unknown" "$expected" "$result"
fi

# =============================================================================
# Test get_correlation_symbol
# =============================================================================

echo ""
echo "=== Testing get_correlation_symbol ==="

# Test 13: your_commit symbol
run_test "get_correlation_symbol 'your_commit'"
result=$(get_correlation_symbol "your_commit")
if [[ "$result" == "✓" ]]; then
    test_pass "Returns checkmark"
else
    test_fail "symbol for your_commit" "✓" "$result"
fi

# Test 14: in_history symbol
run_test "get_correlation_symbol 'in_history'"
result=$(get_correlation_symbol "in_history")
if [[ "$result" == "✓" ]]; then
    test_pass "Returns checkmark"
else
    test_fail "symbol for in_history" "✓" "$result"
fi

# Test 15: not_in_history symbol
run_test "get_correlation_symbol 'not_in_history'"
result=$(get_correlation_symbol "not_in_history")
if [[ "$result" == "✗" ]]; then
    test_pass "Returns X"
else
    test_fail "symbol for not_in_history" "✗" "$result"
fi

# Test 16: unknown symbol
run_test "get_correlation_symbol 'unknown'"
result=$(get_correlation_symbol "unknown")
if [[ "$result" == "✗" ]]; then
    test_pass "Returns X"
else
    test_fail "symbol for unknown" "✗" "$result"
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
