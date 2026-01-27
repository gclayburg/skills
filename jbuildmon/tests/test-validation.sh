#!/usr/bin/env bash
#
# Test script for jenkins-common.sh validation functions (Chunk 2)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Color output for test results
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

# Source the library
source "${LIB_DIR}/jenkins-common.sh"

echo "========================================"
echo "Testing Chunk 2: Validation Functions"
echo "========================================"
echo ""

# =============================================================================
# Test validate_environment
# =============================================================================
echo "--- Testing validate_environment ---"

# Test 1: All vars set → returns success
test_env_all_set() {
    local saved_url="${JENKINS_URL:-}"
    local saved_user="${JENKINS_USER_ID:-}"
    local saved_token="${JENKINS_API_TOKEN:-}"

    export JENKINS_URL="http://jenkins.example.com:8080"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    if validate_environment 2>/dev/null; then
        pass "validate_environment with all vars set returns success"
    else
        fail "validate_environment with all vars set should return success"
    fi

    # Restore
    JENKINS_URL="$saved_url"
    JENKINS_USER_ID="$saved_user"
    JENKINS_API_TOKEN="$saved_token"
}
test_env_all_set

# Test 2: JENKINS_URL unset → returns failure
test_jenkins_url_unset() {
    local saved_url="${JENKINS_URL:-}"
    local saved_user="${JENKINS_USER_ID:-}"
    local saved_token="${JENKINS_API_TOKEN:-}"

    unset JENKINS_URL
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    local output result
    output=$(validate_environment 2>&1)
    result=$?

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"JENKINS_URL"* ]]; then
            pass "validate_environment with JENKINS_URL unset returns failure with message"
        else
            fail "validate_environment should mention JENKINS_URL in error message"
        fi
    else
        fail "validate_environment with JENKINS_URL unset should return failure"
    fi

    # Restore
    export JENKINS_URL="$saved_url"
    export JENKINS_USER_ID="$saved_user"
    export JENKINS_API_TOKEN="$saved_token"
}
test_jenkins_url_unset

# Test 3: JENKINS_USER_ID unset → returns failure
test_jenkins_user_unset() {
    local saved_url="${JENKINS_URL:-}"
    local saved_user="${JENKINS_USER_ID:-}"
    local saved_token="${JENKINS_API_TOKEN:-}"

    export JENKINS_URL="http://jenkins.example.com:8080"
    unset JENKINS_USER_ID
    export JENKINS_API_TOKEN="testtoken"

    local output result
    output=$(validate_environment 2>&1)
    result=$?

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"JENKINS_USER_ID"* ]]; then
            pass "validate_environment with JENKINS_USER_ID unset returns failure with message"
        else
            fail "validate_environment should mention JENKINS_USER_ID in error message"
        fi
    else
        fail "validate_environment with JENKINS_USER_ID unset should return failure"
    fi

    # Restore
    export JENKINS_URL="$saved_url"
    export JENKINS_USER_ID="$saved_user"
    export JENKINS_API_TOKEN="$saved_token"
}
test_jenkins_user_unset

# Test 4: JENKINS_API_TOKEN unset → returns failure
test_jenkins_token_unset() {
    local saved_url="${JENKINS_URL:-}"
    local saved_user="${JENKINS_USER_ID:-}"
    local saved_token="${JENKINS_API_TOKEN:-}"

    export JENKINS_URL="http://jenkins.example.com:8080"
    export JENKINS_USER_ID="testuser"
    unset JENKINS_API_TOKEN

    local output result
    output=$(validate_environment 2>&1)
    result=$?

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"JENKINS_API_TOKEN"* ]]; then
            pass "validate_environment with JENKINS_API_TOKEN unset returns failure with message"
        else
            fail "validate_environment should mention JENKINS_API_TOKEN in error message"
        fi
    else
        fail "validate_environment with JENKINS_API_TOKEN unset should return failure"
    fi

    # Restore
    export JENKINS_URL="$saved_url"
    export JENKINS_USER_ID="$saved_user"
    export JENKINS_API_TOKEN="$saved_token"
}
test_jenkins_token_unset

# Test 5: Invalid JENKINS_URL format → returns failure
test_invalid_url_format() {
    local saved_url="${JENKINS_URL:-}"
    local saved_user="${JENKINS_USER_ID:-}"
    local saved_token="${JENKINS_API_TOKEN:-}"

    export JENKINS_URL="not-a-valid-url"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    local output result
    output=$(validate_environment 2>&1)
    result=$?

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"http://"* ]] || [[ "$output" == *"https://"* ]]; then
            pass "validate_environment with invalid URL returns failure with helpful message"
        else
            fail "validate_environment should mention required URL format"
        fi
    else
        fail "validate_environment with invalid URL should return failure"
    fi

    # Restore
    export JENKINS_URL="$saved_url"
    export JENKINS_USER_ID="$saved_user"
    export JENKINS_API_TOKEN="$saved_token"
}
test_invalid_url_format

# Test 6: JENKINS_URL trailing slash is normalized
test_trailing_slash_normalized() {
    local saved_url="${JENKINS_URL:-}"
    local saved_user="${JENKINS_USER_ID:-}"
    local saved_token="${JENKINS_API_TOKEN:-}"

    export JENKINS_URL="http://jenkins.example.com:8080/"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    validate_environment 2>/dev/null

    if [[ "$JENKINS_URL" == "http://jenkins.example.com:8080" ]]; then
        pass "validate_environment normalizes trailing slash"
    else
        fail "validate_environment should strip trailing slash (got: $JENKINS_URL)"
    fi

    # Restore
    export JENKINS_URL="$saved_url"
    export JENKINS_USER_ID="$saved_user"
    export JENKINS_API_TOKEN="$saved_token"
}
test_trailing_slash_normalized

echo ""

# =============================================================================
# Test validate_dependencies
# =============================================================================
echo "--- Testing validate_dependencies ---"

# Test 7: jq and curl available → returns success
if command -v jq &>/dev/null && command -v curl &>/dev/null; then
    if validate_dependencies 2>/dev/null; then
        pass "validate_dependencies with jq and curl available returns success"
    else
        fail "validate_dependencies should return success when dependencies are available"
    fi
else
    echo "SKIP: jq or curl not available in test environment"
fi

# Test 8: validate_dependencies function is defined
if declare -f validate_dependencies &>/dev/null; then
    pass "validate_dependencies function is defined"
else
    fail "validate_dependencies function should be defined"
fi

echo ""

# =============================================================================
# Test validate_git_repository
# =============================================================================
echo "--- Testing validate_git_repository ---"

# Test 9: From within a git repo → returns success
if validate_git_repository 2>/dev/null; then
    pass "validate_git_repository from within git repo returns success"
else
    fail "validate_git_repository should return success when in git repo with origin"
fi

# Test 10: From outside a git repo → returns failure
test_outside_git_repo() {
    local temp_dir
    temp_dir=$(mktemp -d)
    local saved_pwd="$PWD"

    cd "$temp_dir"

    local output result
    output=$(validate_git_repository 2>&1)
    result=$?

    cd "$saved_pwd"
    rm -rf "$temp_dir"

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"Not a git repository"* ]]; then
            pass "validate_git_repository outside git repo returns failure with message"
        else
            fail "validate_git_repository should say 'Not a git repository' (got: $output)"
        fi
    else
        fail "validate_git_repository outside git repo should return failure"
    fi
}
test_outside_git_repo

# Test 11: From repo without origin → returns failure
test_repo_without_origin() {
    local temp_dir
    temp_dir=$(mktemp -d)
    local saved_pwd="$PWD"

    cd "$temp_dir"
    git init -q

    local output result
    output=$(validate_git_repository 2>&1)
    result=$?

    cd "$saved_pwd"
    rm -rf "$temp_dir"

    if [[ $result -ne 0 ]]; then
        if [[ "$output" == *"origin"* ]]; then
            pass "validate_git_repository without origin returns failure with message"
        else
            fail "validate_git_repository should mention 'origin' remote (got: $output)"
        fi
    else
        fail "validate_git_repository without origin should return failure"
    fi
}
test_repo_without_origin

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
