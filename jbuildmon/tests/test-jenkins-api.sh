#!/usr/bin/env bash
#
# Test script for jenkins-common.sh Jenkins API functions (Chunk 3)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Color output for test results
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
    ((TESTS_SKIPPED++))
}

# Set up environment for sourcing (validation requires these)
export JENKINS_URL="http://jenkins.example.com:8080"
export JENKINS_USER_ID="testuser"
export JENKINS_API_TOKEN="testtoken"

# Source the library
source "${LIB_DIR}/jenkins-common.sh"

echo "========================================"
echo "Testing Chunk 3: Jenkins API Functions"
echo "========================================"
echo ""

# =============================================================================
# Test jenkins_api function definition and behavior
# =============================================================================
echo "--- Testing jenkins_api ---"

# Test 1: jenkins_api function is defined
if declare -f jenkins_api &>/dev/null; then
    pass "jenkins_api function is defined"
else
    fail "jenkins_api function should be defined"
fi

# Test 2: jenkins_api constructs correct URL
# We can't make real API calls, but we can verify it uses JENKINS_URL
test_jenkins_api_url_construction() {
    # Override curl to capture the URL
    local captured_url=""
    curl() {
        for arg in "$@"; do
            if [[ "$arg" == http* ]]; then
                captured_url="$arg"
            fi
        done
        return 1  # Simulate failure so we don't need real response
    }
    export -f curl

    # Call jenkins_api (will fail but we capture the URL)
    jenkins_api "/job/test/api/json" 2>/dev/null || true

    # Unset the override
    unset -f curl

    if [[ "$captured_url" == "http://jenkins.example.com:8080/job/test/api/json" ]]; then
        pass "jenkins_api constructs correct URL from JENKINS_URL + endpoint"
    else
        fail "jenkins_api should construct URL correctly (got: $captured_url)"
    fi
}
test_jenkins_api_url_construction

echo ""

# =============================================================================
# Test jenkins_api_with_status function
# =============================================================================
echo "--- Testing jenkins_api_with_status ---"

# Test 3: jenkins_api_with_status function is defined
if declare -f jenkins_api_with_status &>/dev/null; then
    pass "jenkins_api_with_status function is defined"
else
    fail "jenkins_api_with_status function should be defined"
fi

# Test 4: jenkins_api_with_status function uses correct curl options
# We verify the function definition includes the expected -w pattern
test_jenkins_api_with_status_format() {
    local func_body
    func_body=$(declare -f jenkins_api_with_status)

    if [[ "$func_body" == *"-w"* ]] && [[ "$func_body" == *"http_code"* ]]; then
        pass "jenkins_api_with_status uses curl -w for HTTP status code"
    else
        fail "jenkins_api_with_status should use -w flag to get HTTP status"
    fi
}
test_jenkins_api_with_status_format

# Test 5: jenkins_api_with_status returns body and status on separate lines
# This test verifies the output format by inspecting the function behavior
test_jenkins_api_with_status_output() {
    # Verify the function includes newline before http_code
    local func_body
    func_body=$(declare -f jenkins_api_with_status)

    if [[ "$func_body" == *'"\n%{http_code}"'* ]] || [[ "$func_body" == *"'\\n%{http_code}'"* ]]; then
        pass "jenkins_api_with_status returns body and HTTP status code on separate lines"
    else
        fail "jenkins_api_with_status should use newline before http_code format"
    fi
}
test_jenkins_api_with_status_output

echo ""

# =============================================================================
# Test verify_jenkins_connection function
# =============================================================================
echo "--- Testing verify_jenkins_connection ---"

# Test 6: verify_jenkins_connection function is defined
if declare -f verify_jenkins_connection &>/dev/null; then
    pass "verify_jenkins_connection function is defined"
else
    fail "verify_jenkins_connection function should be defined"
fi

# Test 7: verify_jenkins_connection returns success on HTTP 200
test_verify_connection_success() {
    jenkins_api_with_status() {
        echo '{"_class":"hudson.model.Hudson"}'
        echo "200"
    }
    export -f jenkins_api_with_status

    if verify_jenkins_connection >/dev/null 2>&1; then
        pass "verify_jenkins_connection returns success on HTTP 200"
    else
        fail "verify_jenkins_connection should return success on HTTP 200"
    fi

    unset -f jenkins_api_with_status
}
test_verify_connection_success

# Test 8: verify_jenkins_connection handles 401 appropriately
test_verify_connection_401() {
    jenkins_api_with_status() {
        echo 'Unauthorized'
        echo "401"
    }
    export -f jenkins_api_with_status

    local output
    output=$(verify_jenkins_connection 2>&1)
    local result=$?

    unset -f jenkins_api_with_status

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"401"* ]] && [[ "$output" == *"authentication"* ]]; then
            pass "verify_jenkins_connection handles 401 with helpful message"
        else
            fail "verify_jenkins_connection should mention 401 and authentication (got: $output)"
        fi
    else
        fail "verify_jenkins_connection should return failure on 401"
    fi
}
test_verify_connection_401

# Test 9: verify_jenkins_connection handles 403 appropriately
test_verify_connection_403() {
    jenkins_api_with_status() {
        echo 'Forbidden'
        echo "403"
    }
    export -f jenkins_api_with_status

    local output
    output=$(verify_jenkins_connection 2>&1)
    local result=$?

    unset -f jenkins_api_with_status

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"403"* ]] && [[ "$output" == *"permission"* ]]; then
            pass "verify_jenkins_connection handles 403 with helpful message"
        else
            fail "verify_jenkins_connection should mention 403 and permission (got: $output)"
        fi
    else
        fail "verify_jenkins_connection should return failure on 403"
    fi
}
test_verify_connection_403

echo ""

# =============================================================================
# Test verify_job_exists function
# =============================================================================
echo "--- Testing verify_job_exists ---"

# Test 10: verify_job_exists function is defined
if declare -f verify_job_exists &>/dev/null; then
    pass "verify_job_exists function is defined"
else
    fail "verify_job_exists function should be defined"
fi

# Test 11: verify_job_exists sets JOB_URL global on success
test_verify_job_sets_url() {
    JOB_URL=""  # Reset
    jenkins_api_with_status() {
        echo '{"_class":"hudson.model.FreeStyleProject"}'
        echo "200"
    }
    export -f jenkins_api_with_status

    verify_job_exists "my-test-job" >/dev/null 2>&1
    local result=$?

    unset -f jenkins_api_with_status

    if [[ $result -eq 0 ]] && [[ "$JOB_URL" == "http://jenkins.example.com:8080/job/my-test-job" ]]; then
        pass "verify_job_exists sets JOB_URL global on success"
    else
        fail "verify_job_exists should set JOB_URL (result=$result, JOB_URL=$JOB_URL)"
    fi
}
test_verify_job_sets_url

# Test 12: verify_job_exists handles 404 appropriately
test_verify_job_404() {
    jenkins_api_with_status() {
        echo 'Not Found'
        echo "404"
    }
    export -f jenkins_api_with_status

    local output
    output=$(verify_job_exists "nonexistent-job" 2>&1)
    local result=$?

    unset -f jenkins_api_with_status

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"not found"* ]] || [[ "$output" == *"404"* ]]; then
            pass "verify_job_exists handles 404 with helpful message"
        else
            fail "verify_job_exists should mention job not found (got: $output)"
        fi
    else
        fail "verify_job_exists should return failure on 404"
    fi
}
test_verify_job_404

# Test 13: verify_job_exists returns success for valid job
test_verify_job_success() {
    jenkins_api_with_status() {
        echo '{"_class":"hudson.model.FreeStyleProject","displayName":"my-job"}'
        echo "200"
    }
    export -f jenkins_api_with_status

    if verify_job_exists "my-job" >/dev/null 2>&1; then
        pass "verify_job_exists returns success for valid job"
    else
        fail "verify_job_exists should return success for valid job"
    fi

    unset -f jenkins_api_with_status
}
test_verify_job_success

echo ""

# =============================================================================
# Integration Tests (only run if JENKINS_URL points to a real server)
# =============================================================================
echo "--- Integration Tests (require live Jenkins) ---"

# Check if we might have a real Jenkins server configured
if [[ -n "${JENKINS_URL:-}" ]] && [[ "${JENKINS_URL}" != "http://jenkins.example.com:8080" ]]; then
    echo "Live Jenkins detected at $JENKINS_URL"

    # Test actual connectivity
    if verify_jenkins_connection 2>/dev/null; then
        pass "Integration: verify_jenkins_connection to live Jenkins"
    else
        skip "Integration: Could not connect to live Jenkins"
    fi
else
    skip "Integration tests: No live Jenkins configured (set JENKINS_URL, JENKINS_USER_ID, JENKINS_API_TOKEN)"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed:  ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed:  ${RED}${TESTS_FAILED}${NC}"
echo -e "Skipped: ${YELLOW}${TESTS_SKIPPED}${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
