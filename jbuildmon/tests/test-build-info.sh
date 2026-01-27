#!/usr/bin/env bash
#
# Test script for jenkins-common.sh Build Information Functions (Chunk 4)
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
echo "Testing Chunk 4: Build Information Functions"
echo "=============================================="
echo ""

# =============================================================================
# Test get_build_info function
# =============================================================================
echo "--- Testing get_build_info ---"

# Test 1: get_build_info function is defined
if declare -f get_build_info &>/dev/null; then
    pass "get_build_info function is defined"
else
    fail "get_build_info function should be defined"
fi

# Test 2: get_build_info returns JSON with expected fields for completed build
test_get_build_info_completed() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowRun","number":142,"result":"SUCCESS","building":false,"timestamp":1705327925000,"duration":154000,"url":"http://jenkins.example.com:8080/job/my-project/142/"}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_build_info "my-project" "142")

    unset -f jenkins_api

    # Verify JSON contains expected fields
    local number result_field building
    number=$(echo "$result" | jq -r '.number')
    result_field=$(echo "$result" | jq -r '.result')
    building=$(echo "$result" | jq -r '.building')

    if [[ "$number" == "142" ]] && [[ "$result_field" == "SUCCESS" ]] && [[ "$building" == "false" ]]; then
        pass "get_build_info returns JSON with number, result, building fields"
    else
        fail "get_build_info should return JSON with expected fields (got: number=$number, result=$result_field, building=$building)"
    fi
}
test_get_build_info_completed

# Test 3: get_build_info returns JSON for in-progress build
test_get_build_info_in_progress() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowRun","number":143,"result":null,"building":true,"timestamp":1705328000000,"duration":0,"url":"http://jenkins.example.com:8080/job/my-project/143/"}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_build_info "my-project" "143")

    unset -f jenkins_api

    local building result_field
    building=$(echo "$result" | jq -r '.building')
    result_field=$(echo "$result" | jq -r '.result')

    if [[ "$building" == "true" ]] && [[ "$result_field" == "null" ]]; then
        pass "get_build_info returns building=true, result=null for in-progress build"
    else
        fail "get_build_info should return building=true, result=null for in-progress (got: building=$building, result=$result_field)"
    fi
}
test_get_build_info_in_progress

# Test 4: get_build_info returns empty string on API failure
test_get_build_info_failure() {
    jenkins_api() {
        return 1
    }
    export -f jenkins_api

    local result
    result=$(get_build_info "my-project" "999")

    unset -f jenkins_api

    if [[ -z "$result" ]]; then
        pass "get_build_info returns empty string on API failure"
    else
        fail "get_build_info should return empty string on failure (got: $result)"
    fi
}
test_get_build_info_failure

echo ""

# =============================================================================
# Test get_console_output function
# =============================================================================
echo "--- Testing get_console_output ---"

# Test 5: get_console_output function is defined
if declare -f get_console_output &>/dev/null; then
    pass "get_console_output function is defined"
else
    fail "get_console_output function should be defined"
fi

# Test 6: get_console_output returns console text
test_get_console_output() {
    jenkins_api() {
        cat <<'EOF'
Started by user buildtriggerdude
Running on build-agent-01 in /var/jenkins/workspace/my-project
[Pipeline] Start of Pipeline
[Pipeline] node
[Pipeline] { (Build)
Building...
[Pipeline] }
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_console_output "my-project" "142")

    unset -f jenkins_api

    if [[ "$result" == *"Started by user"* ]] && [[ "$result" == *"Pipeline"* ]]; then
        pass "get_console_output returns console text"
    else
        fail "get_console_output should return console text"
    fi
}
test_get_console_output

# Test 7: get_console_output returns empty string on failure
test_get_console_output_failure() {
    jenkins_api() {
        return 1
    }
    export -f jenkins_api

    local result
    result=$(get_console_output "my-project" "999")

    unset -f jenkins_api

    if [[ -z "$result" ]]; then
        pass "get_console_output returns empty string on failure"
    else
        fail "get_console_output should return empty on failure"
    fi
}
test_get_console_output_failure

echo ""

# =============================================================================
# Test get_current_stage function
# =============================================================================
echo "--- Testing get_current_stage ---"

# Test 8: get_current_stage function is defined
if declare -f get_current_stage &>/dev/null; then
    pass "get_current_stage function is defined"
else
    fail "get_current_stage function should be defined"
fi

# Test 9: get_current_stage returns stage name for IN_PROGRESS stage
test_get_current_stage() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"IN_PROGRESS"},{"name":"Deploy","status":"NOT_EXECUTED"}]}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_current_stage "my-project" "143")

    unset -f jenkins_api

    if [[ "$result" == "Test" ]]; then
        pass "get_current_stage returns current stage name (Test)"
    else
        fail "get_current_stage should return 'Test' (got: $result)"
    fi
}
test_get_current_stage

# Test 10: get_current_stage returns empty when no stage is in progress
test_get_current_stage_none() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"SUCCESS"}]}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_current_stage "my-project" "142")

    unset -f jenkins_api

    if [[ -z "$result" ]]; then
        pass "get_current_stage returns empty when no stage in progress"
    else
        fail "get_current_stage should return empty when no stage in progress (got: $result)"
    fi
}
test_get_current_stage_none

echo ""

# =============================================================================
# Test get_failed_stage function
# =============================================================================
echo "--- Testing get_failed_stage ---"

# Test 11: get_failed_stage function is defined
if declare -f get_failed_stage &>/dev/null; then
    pass "get_failed_stage function is defined"
else
    fail "get_failed_stage function should be defined"
fi

# Test 12: get_failed_stage returns failed stage name
test_get_failed_stage() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"FAILED"},{"name":"Deploy","status":"NOT_EXECUTED"}]}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_failed_stage "my-project" "143")

    unset -f jenkins_api

    if [[ "$result" == "Test" ]]; then
        pass "get_failed_stage returns failed stage name (Test)"
    else
        fail "get_failed_stage should return 'Test' (got: $result)"
    fi
}
test_get_failed_stage

# Test 13: get_failed_stage returns UNSTABLE stage name
test_get_failed_stage_unstable() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"UNSTABLE"}]}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_failed_stage "my-project" "143")

    unset -f jenkins_api

    if [[ "$result" == "Test" ]]; then
        pass "get_failed_stage returns UNSTABLE stage name"
    else
        fail "get_failed_stage should return UNSTABLE stage (got: $result)"
    fi
}
test_get_failed_stage_unstable

# Test 14: get_failed_stage returns empty when all stages succeed
test_get_failed_stage_none() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"SUCCESS"}]}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_failed_stage "my-project" "142")

    unset -f jenkins_api

    if [[ -z "$result" ]]; then
        pass "get_failed_stage returns empty when all stages succeed"
    else
        fail "get_failed_stage should return empty when no failures (got: $result)"
    fi
}
test_get_failed_stage_none

echo ""

# =============================================================================
# Test get_last_build_number function
# =============================================================================
echo "--- Testing get_last_build_number ---"

# Test 15: get_last_build_number function is defined
if declare -f get_last_build_number &>/dev/null; then
    pass "get_last_build_number function is defined"
else
    fail "get_last_build_number function should be defined"
fi

# Test 16: get_last_build_number returns numeric build number
test_get_last_build_number() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowJob","lastBuild":{"number":142}}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_last_build_number "my-project")

    unset -f jenkins_api

    if [[ "$result" == "142" ]]; then
        pass "get_last_build_number returns numeric build number"
    else
        fail "get_last_build_number should return 142 (got: $result)"
    fi
}
test_get_last_build_number

# Test 17: get_last_build_number returns 0 when no builds exist
test_get_last_build_number_no_builds() {
    jenkins_api() {
        cat <<'EOF'
{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowJob","lastBuild":null}
EOF
    }
    export -f jenkins_api

    local result
    result=$(get_last_build_number "my-project")

    unset -f jenkins_api

    if [[ "$result" == "0" ]]; then
        pass "get_last_build_number returns 0 when no builds exist"
    else
        fail "get_last_build_number should return 0 when no builds (got: $result)"
    fi
}
test_get_last_build_number_no_builds

# Test 18: get_last_build_number returns 0 on API failure
test_get_last_build_number_failure() {
    jenkins_api() {
        return 1
    }
    export -f jenkins_api

    local result
    result=$(get_last_build_number "nonexistent-job")

    unset -f jenkins_api

    if [[ "$result" == "0" ]]; then
        pass "get_last_build_number returns 0 on API failure"
    else
        fail "get_last_build_number should return 0 on failure (got: $result)"
    fi
}
test_get_last_build_number_failure

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
