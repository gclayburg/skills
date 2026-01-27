#!/usr/bin/env bash
#
# Test script for jenkins-common.sh Failure Analysis Functions (Chunk 5)
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

echo "=============================================="
echo "Testing Chunk 5: Failure Analysis Functions"
echo "=============================================="
echo ""

# =============================================================================
# Test check_build_failed function
# =============================================================================
echo "--- Testing check_build_failed ---"

# Test 1: check_build_failed function is defined
if declare -f check_build_failed &>/dev/null; then
    pass "check_build_failed function is defined"
else
    fail "check_build_failed function should be defined"
fi

# Test 2: check_build_failed returns 0 (true) for FAILURE result
test_check_build_failed_failure() {
    get_build_info() {
        echo '{"result":"FAILURE"}'
    }
    export -f get_build_info

    if check_build_failed "my-project" "143"; then
        pass "check_build_failed returns 0 for FAILURE result"
    else
        fail "check_build_failed should return 0 for FAILURE"
    fi

    unset -f get_build_info
}
test_check_build_failed_failure

# Test 3: check_build_failed returns 0 (true) for UNSTABLE result
test_check_build_failed_unstable() {
    get_build_info() {
        echo '{"result":"UNSTABLE"}'
    }
    export -f get_build_info

    if check_build_failed "my-project" "143"; then
        pass "check_build_failed returns 0 for UNSTABLE result"
    else
        fail "check_build_failed should return 0 for UNSTABLE"
    fi

    unset -f get_build_info
}
test_check_build_failed_unstable

# Test 4: check_build_failed returns 0 (true) for ABORTED result
test_check_build_failed_aborted() {
    get_build_info() {
        echo '{"result":"ABORTED"}'
    }
    export -f get_build_info

    if check_build_failed "my-project" "143"; then
        pass "check_build_failed returns 0 for ABORTED result"
    else
        fail "check_build_failed should return 0 for ABORTED"
    fi

    unset -f get_build_info
}
test_check_build_failed_aborted

# Test 5: check_build_failed returns 1 (false) for SUCCESS result
test_check_build_failed_success() {
    get_build_info() {
        echo '{"result":"SUCCESS"}'
    }
    export -f get_build_info

    if ! check_build_failed "my-project" "142"; then
        pass "check_build_failed returns 1 for SUCCESS result"
    else
        fail "check_build_failed should return 1 for SUCCESS"
    fi

    unset -f get_build_info
}
test_check_build_failed_success

echo ""

# =============================================================================
# Test detect_all_downstream_builds function
# =============================================================================
echo "--- Testing detect_all_downstream_builds ---"

# Test 6: detect_all_downstream_builds function is defined
if declare -f detect_all_downstream_builds &>/dev/null; then
    pass "detect_all_downstream_builds function is defined"
else
    fail "detect_all_downstream_builds function should be defined"
fi

# Test 7: detect_all_downstream_builds finds downstream builds
test_detect_all_downstream() {
    local console_output='Started by user buildtriggerdude
[Pipeline] Start of Pipeline
[Pipeline] stage
Starting building: my-project-tests #45
Starting building: my-project-integration #12
[Pipeline] End of Pipeline'

    local result
    result=$(detect_all_downstream_builds "$console_output")

    if [[ "$result" == *"my-project-tests 45"* ]] && [[ "$result" == *"my-project-integration 12"* ]]; then
        pass "detect_all_downstream_builds finds all downstream builds"
    else
        fail "detect_all_downstream_builds should find downstream builds (got: $result)"
    fi
}
test_detect_all_downstream

# Test 8: detect_all_downstream_builds returns empty when no downstream
test_detect_all_downstream_empty() {
    local console_output='Started by user buildtriggerdude
[Pipeline] Start of Pipeline
Building...
[Pipeline] End of Pipeline'

    local result
    result=$(detect_all_downstream_builds "$console_output")

    if [[ -z "$result" ]]; then
        pass "detect_all_downstream_builds returns empty when no downstream"
    else
        fail "detect_all_downstream_builds should return empty (got: $result)"
    fi
}
test_detect_all_downstream_empty

echo ""

# =============================================================================
# Test find_failed_downstream_build function
# =============================================================================
echo "--- Testing find_failed_downstream_build ---"

# Test 9: find_failed_downstream_build function is defined
if declare -f find_failed_downstream_build &>/dev/null; then
    pass "find_failed_downstream_build function is defined"
else
    fail "find_failed_downstream_build function should be defined"
fi

# Test 10: find_failed_downstream_build finds failed build
test_find_failed_downstream() {
    local console_output='Starting building: my-project-tests #45
Starting building: my-project-integration #12'

    # Mock check_build_failed to return failure for integration job
    check_build_failed() {
        local job_name="$1"
        if [[ "$job_name" == "my-project-integration" ]]; then
            return 0
        fi
        return 1
    }
    export -f check_build_failed

    local result
    result=$(find_failed_downstream_build "$console_output")

    unset -f check_build_failed

    if [[ "$result" == "my-project-integration 12" ]]; then
        pass "find_failed_downstream_build finds the failed build"
    else
        fail "find_failed_downstream_build should find failed build (got: $result)"
    fi
}
test_find_failed_downstream

echo ""

# =============================================================================
# Test extract_error_lines function
# =============================================================================
echo "--- Testing extract_error_lines ---"

# Test 11: extract_error_lines function is defined
if declare -f extract_error_lines &>/dev/null; then
    pass "extract_error_lines function is defined"
else
    fail "extract_error_lines function should be defined"
fi

# Test 12: extract_error_lines extracts ERROR lines
test_extract_error_lines_error() {
    local console_output='Building project...
Compiling...
[ERROR] Build failed
[ERROR] Missing dependency
Build complete'

    local result
    result=$(extract_error_lines "$console_output")

    if [[ "$result" == *"[ERROR] Build failed"* ]] && [[ "$result" == *"[ERROR] Missing dependency"* ]]; then
        pass "extract_error_lines extracts ERROR lines"
    else
        fail "extract_error_lines should extract ERROR lines (got: $result)"
    fi
}
test_extract_error_lines_error

# Test 13: extract_error_lines extracts Exception lines
test_extract_error_lines_exception() {
    local console_output='Running tests...
java.lang.NullPointerException: null
    at com.example.Test.run(Test.java:42)
Tests complete'

    local result
    result=$(extract_error_lines "$console_output")

    if [[ "$result" == *"NullPointerException"* ]]; then
        pass "extract_error_lines extracts Exception lines"
    else
        fail "extract_error_lines should extract Exception lines (got: $result)"
    fi
}
test_extract_error_lines_exception

# Test 14: extract_error_lines returns last lines as fallback
test_extract_error_lines_fallback() {
    local console_output='Line 1
Line 2
Line 3
Line 4
Line 5'

    local result
    result=$(extract_error_lines "$console_output")

    if [[ "$result" == *"Line"* ]]; then
        pass "extract_error_lines returns last lines as fallback"
    else
        fail "extract_error_lines should return last lines as fallback"
    fi
}
test_extract_error_lines_fallback

echo ""

# =============================================================================
# Test extract_stage_logs function
# =============================================================================
echo "--- Testing extract_stage_logs ---"

# Test 15: extract_stage_logs function is defined
if declare -f extract_stage_logs &>/dev/null; then
    pass "extract_stage_logs function is defined"
else
    fail "extract_stage_logs function should be defined"
fi

# Test 16: extract_stage_logs extracts stage-specific logs
test_extract_stage_logs() {
    local console_output='[Pipeline] Start of Pipeline
[Pipeline] { (Build)
Running build step 1
Running build step 2
[Pipeline] }
[Pipeline] { (Test)
Running test step 1
ERROR: Test failed
[Pipeline] }
[Pipeline] End of Pipeline'

    local result
    result=$(extract_stage_logs "$console_output" "Test")

    if [[ "$result" == *"Running test step 1"* ]] && [[ "$result" == *"ERROR: Test failed"* ]]; then
        pass "extract_stage_logs extracts logs for specified stage"
    else
        fail "extract_stage_logs should extract stage logs (got: $result)"
    fi
}
test_extract_stage_logs

# Test 17: extract_stage_logs returns empty for non-existent stage
test_extract_stage_logs_not_found() {
    local console_output='[Pipeline] { (Build)
Building...
[Pipeline] }'

    local result
    result=$(extract_stage_logs "$console_output" "NonExistent")

    if [[ -z "$result" ]]; then
        pass "extract_stage_logs returns empty for non-existent stage"
    else
        fail "extract_stage_logs should return empty for non-existent stage (got: $result)"
    fi
}
test_extract_stage_logs_not_found

echo ""

# =============================================================================
# Test display_build_metadata function
# =============================================================================
echo "--- Testing display_build_metadata ---"

# Test 18: display_build_metadata function is defined
if declare -f display_build_metadata &>/dev/null; then
    pass "display_build_metadata function is defined"
else
    fail "display_build_metadata function should be defined"
fi

# Test 19: display_build_metadata extracts user, agent, and pipeline
test_display_build_metadata() {
    local console_output='Started by user jsmith
Running on build-agent-01 in /var/jenkins/workspace
Obtained Jenkinsfile from git ssh://git@server/repo.git
Building...'

    local result
    result=$(display_build_metadata "$console_output")

    if [[ "$result" == *"jsmith"* ]] && [[ "$result" == *"build-agent-01"* ]] && [[ "$result" == *"Jenkinsfile"* ]]; then
        pass "display_build_metadata extracts user, agent, and pipeline"
    else
        fail "display_build_metadata should extract metadata (got: $result)"
    fi
}
test_display_build_metadata

echo ""

# =============================================================================
# Test analyze_failure function
# =============================================================================
echo "--- Testing analyze_failure ---"

# Test 20: analyze_failure function is defined
if declare -f analyze_failure &>/dev/null; then
    pass "analyze_failure function is defined"
else
    fail "analyze_failure function should be defined"
fi

# Test 21: analyze_failure handles missing console output gracefully
test_analyze_failure_no_console() {
    get_console_output() {
        echo ""
    }
    export -f get_console_output

    local result
    result=$(analyze_failure "my-project" "143" 2>&1)

    unset -f get_console_output

    if [[ "$result" == *"Could not retrieve console output"* ]]; then
        pass "analyze_failure handles missing console output gracefully"
    else
        fail "analyze_failure should handle missing console output (got: $result)"
    fi
}
test_analyze_failure_no_console

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
