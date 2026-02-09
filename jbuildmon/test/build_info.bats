#!/usr/bin/env bats

# Unit tests for build information functions
# Migrated from tests/test-build-info.sh

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    # shellcheck source=../lib/jenkins-common.sh
    source "${PROJECT_DIR}/lib/jenkins-common.sh"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# =============================================================================
# get_build_info
# =============================================================================

@test "get_build_info: returns JSON for completed build" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowRun","number":142,"result":"SUCCESS","building":false,"timestamp":1705327925000,"duration":154000,"url":"http://jenkins.example.com:8080/job/my-project/142/"}'
    }

    run get_build_info "my-project" "142"
    assert_success

    # Verify JSON contains expected fields
    [[ $(echo "$output" | jq -r '.number') == "142" ]]
    [[ $(echo "$output" | jq -r '.result') == "SUCCESS" ]]
    [[ $(echo "$output" | jq -r '.building') == "false" ]]
}

@test "get_build_info: returns JSON for in-progress build" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowRun","number":143,"result":null,"building":true,"timestamp":1705328000000,"duration":0,"url":"http://jenkins.example.com:8080/job/my-project/143/"}'
    }

    run get_build_info "my-project" "143"
    assert_success

    [[ $(echo "$output" | jq -r '.building') == "true" ]]
    [[ $(echo "$output" | jq -r '.result') == "null" ]]
}

@test "get_build_info: returns empty on API failure" {
    jenkins_api() { return 1; }

    run get_build_info "my-project" "999"

    [[ -z "$output" ]]
}

# =============================================================================
# get_console_output
# =============================================================================

@test "get_console_output: returns console text" {
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

    run get_console_output "my-project" "142"
    assert_success

    [[ "$output" == *"Started by user"* ]]
    [[ "$output" == *"Pipeline"* ]]
}

@test "get_console_output: returns empty on API failure" {
    jenkins_api() { return 1; }

    run get_console_output "my-project" "999"

    [[ -z "$output" ]]
}

# =============================================================================
# get_current_stage
# =============================================================================

@test "get_current_stage: returns IN_PROGRESS stage name" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"IN_PROGRESS"},{"name":"Deploy","status":"NOT_EXECUTED"}]}'
    }

    run get_current_stage "my-project" "143"
    assert_success
    assert_output "Test"
}

@test "get_current_stage: returns empty when no stage in progress" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"SUCCESS"}]}'
    }

    run get_current_stage "my-project" "142"
    assert_success
    assert_output ""
}

# =============================================================================
# get_failed_stage
# =============================================================================

@test "get_failed_stage: returns FAILED stage name" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"FAILED"},{"name":"Deploy","status":"NOT_EXECUTED"}]}'
    }

    run get_failed_stage "my-project" "143"
    assert_success
    assert_output "Test"
}

@test "get_failed_stage: returns UNSTABLE stage name" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"UNSTABLE"}]}'
    }

    run get_failed_stage "my-project" "143"
    assert_success
    assert_output "Test"
}

@test "get_failed_stage: returns empty when all stages succeed" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.views.FlowGraphAction","stages":[{"name":"Build","status":"SUCCESS"},{"name":"Test","status":"SUCCESS"}]}'
    }

    run get_failed_stage "my-project" "142"
    assert_success
    assert_output ""
}

# =============================================================================
# get_last_build_number
# =============================================================================

@test "get_last_build_number: returns numeric build number" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowJob","lastBuild":{"number":142}}'
    }

    run get_last_build_number "my-project"
    assert_success
    assert_output "142"
}

@test "get_last_build_number: returns 0 when no builds exist" {
    jenkins_api() {
        echo '{"_class":"org.jenkinsci.plugins.workflow.job.WorkflowJob","lastBuild":null}'
    }

    run get_last_build_number "my-project"
    assert_success
    assert_output "0"
}

@test "get_last_build_number: returns 0 on API failure" {
    jenkins_api() { return 1; }

    run get_last_build_number "nonexistent-job"
    assert_success
    assert_output "0"
}
