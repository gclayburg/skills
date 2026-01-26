#!/usr/bin/env bash
#
# Test script for jenkins-common.sh
# Run from jbuildmon directory: ./lib/test-jenkins-common.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PASSED=0
TEST_FAILED=0

# Colors for test output (simple, don't depend on library)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TEST_PASSED=$((TEST_PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TEST_FAILED=$((TEST_FAILED + 1))
}

# =============================================================================
# Test 1: Source the library
# =============================================================================
echo "=== Test 1: Source the library ==="
if source "${SCRIPT_DIR}/jenkins-common.sh"; then
    pass "Library sourced successfully"
else
    fail "Library failed to source"
    exit 1
fi

# =============================================================================
# Test 2: Verify color variables are set (or empty)
# =============================================================================
echo ""
echo "=== Test 2: Verify color variables exist ==="

for var in COLOR_RESET COLOR_BLUE COLOR_GREEN COLOR_YELLOW COLOR_RED COLOR_CYAN COLOR_BOLD; do
    if declare -p "$var" &>/dev/null; then
        pass "Variable $var is defined"
    else
        fail "Variable $var is not defined"
    fi
done

# =============================================================================
# Test 3: _timestamp returns time in HH:MM:SS format
# =============================================================================
echo ""
echo "=== Test 3: _timestamp format ==="

timestamp=$(_timestamp)
if [[ "$timestamp" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    pass "_timestamp returns HH:MM:SS format: $timestamp"
else
    fail "_timestamp format incorrect: $timestamp (expected HH:MM:SS)"
fi

# =============================================================================
# Test 4: Logging functions output to correct streams
# =============================================================================
echo ""
echo "=== Test 4: Logging functions output ==="

# Test log_info (stdout)
output=$(log_info "test message" 2>/dev/null)
if [[ "$output" == *"test message"* ]] && [[ "$output" == *"ℹ"* ]]; then
    pass "log_info outputs to stdout with info icon"
else
    fail "log_info output incorrect: $output"
fi

# Test log_success (stdout)
output=$(log_success "test message" 2>/dev/null)
if [[ "$output" == *"test message"* ]] && [[ "$output" == *"✓"* ]]; then
    pass "log_success outputs to stdout with checkmark"
else
    fail "log_success output incorrect: $output"
fi

# Test log_warning (stdout)
output=$(log_warning "test message" 2>/dev/null)
if [[ "$output" == *"test message"* ]] && [[ "$output" == *"⚠"* ]]; then
    pass "log_warning outputs to stdout with warning icon"
else
    fail "log_warning output incorrect: $output"
fi

# Test log_error (stderr)
output=$(log_error "test error" 2>&1 >/dev/null)
if [[ "$output" == *"test error"* ]] && [[ "$output" == *"✗"* ]]; then
    pass "log_error outputs to stderr with X icon"
else
    fail "log_error output incorrect: $output"
fi

# =============================================================================
# Test 5: log_banner success format
# =============================================================================
echo ""
echo "=== Test 5: log_banner formats ==="

# Test success banner
output=$(log_banner "success")
if [[ "$output" == *"BUILD SUCCESSFUL"* ]] && [[ "$output" == *"╔"* ]] && [[ "$output" == *"╚"* ]]; then
    pass "log_banner success shows BUILD SUCCESSFUL with box borders"
else
    fail "log_banner success format incorrect"
fi

# Test failure banner
output=$(log_banner "failure")
if [[ "$output" == *"BUILD FAILED"* ]]; then
    pass "log_banner failure shows BUILD FAILED"
else
    fail "log_banner failure format incorrect"
fi

# Test building/in_progress banner
output=$(log_banner "building")
if [[ "$output" == *"BUILD IN PROGRESS"* ]]; then
    pass "log_banner building shows BUILD IN PROGRESS"
else
    fail "log_banner building format incorrect"
fi

output=$(log_banner "in_progress")
if [[ "$output" == *"BUILD IN PROGRESS"* ]]; then
    pass "log_banner in_progress shows BUILD IN PROGRESS"
else
    fail "log_banner in_progress format incorrect"
fi

# =============================================================================
# Test 6: Test with TERM=dumb (colors disabled)
# =============================================================================
echo ""
echo "=== Test 6: Colors disabled with TERM=dumb ==="

# Run in subshell with TERM=dumb
output=$(TERM=dumb bash -c "
    source '${SCRIPT_DIR}/jenkins-common.sh'
    if [[ -z \"\$COLOR_RESET\" && -z \"\$COLOR_BLUE\" && -z \"\$COLOR_GREEN\" ]]; then
        echo 'colors_disabled'
    else
        echo 'colors_enabled'
    fi
")

if [[ "$output" == "colors_disabled" ]]; then
    pass "Colors are disabled when TERM=dumb"
else
    fail "Colors should be disabled when TERM=dumb"
fi

# =============================================================================
# Test 7: Test with NO_COLOR set
# =============================================================================
echo ""
echo "=== Test 7: Colors disabled with NO_COLOR ==="

output=$(NO_COLOR=1 bash -c "
    source '${SCRIPT_DIR}/jenkins-common.sh'
    if [[ -z \"\$COLOR_RESET\" && -z \"\$COLOR_BLUE\" && -z \"\$COLOR_GREEN\" ]]; then
        echo 'colors_disabled'
    else
        echo 'colors_enabled'
    fi
")

if [[ "$output" == "colors_disabled" ]]; then
    pass "Colors are disabled when NO_COLOR is set"
else
    fail "Colors should be disabled when NO_COLOR is set"
fi

# =============================================================================
# Test 8: Multiple sourcing prevention
# =============================================================================
echo ""
echo "=== Test 8: Multiple sourcing prevention ==="

# Source again - should not error or redefine
if source "${SCRIPT_DIR}/jenkins-common.sh" 2>/dev/null; then
    pass "Library can be sourced multiple times without error"
else
    fail "Library failed on second source"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "Test Summary: $TEST_PASSED passed, $TEST_FAILED failed"
echo "=========================================="

if [[ $TEST_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
