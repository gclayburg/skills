#!/usr/bin/env bats

# Tests for buildgit stdout/stderr routing

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"

    TEST_REPO="${TEST_TEMP_DIR}/repo"
    mkdir -p "${TEST_REPO}"
    cd "${TEST_REPO}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "Initial content" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    git remote add origin "git@github.com:testorg/test-repo.git"

    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

@test "build_monitoring_stage_output_goes_to_stdout" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR

    cat > "${TEST_TEMP_DIR}/stage_stdout_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

_track_nested_stage_changes() {
    echo "[12:34:56] ℹ   Stage: Deploy (3s)" >&"${BUILDGIT_SIDE_EFFECT_FD:-1}"
    jq -n '{nested: [], printed: {}, parallel_state: {}, tracking_complete: true}'
}

state_file="$(mktemp)"
BUILDGIT_SIDE_EFFECT_FD=3 _track_nested_stage_changes "test-repo" "42" "[]" "false" 3>&1 >"$state_file"
stage_state=$(cat "$state_file")
rm -f "$state_file"
echo "$stage_state" | jq -e '.tracking_complete == true' >/dev/null
EOF
    chmod +x "${TEST_TEMP_DIR}/stage_stdout_wrapper.sh"

    run bash -c "bash '${TEST_TEMP_DIR}/stage_stdout_wrapper.sh' >'${TEST_TEMP_DIR}/stdout.txt' 2>'${TEST_TEMP_DIR}/stderr.txt'"

    assert_success
    run cat "${TEST_TEMP_DIR}/stdout.txt"
    assert_output --partial "Stage: Deploy (3s)"

    run cat "${TEST_TEMP_DIR}/stderr.txt"
    assert_output ""
}

@test "build_monitoring_queue_output_goes_to_stdout" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR

    echo "0" > "${TEST_TEMP_DIR}/build_number_calls"

    cat > "${TEST_TEMP_DIR}/queue_stdout_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

POLL_INTERVAL=1
BUILD_START_TIMEOUT=5

_status_stdout_is_tty() { return 1; }
_get_queue_item_for_job() {
    echo '{"why":"In the quiet period. Expires in 4.9 sec","cancelled":false,"inQueueSince":1706700000000}'
}
get_last_build_number() {
    local count
    count=$(cat "${TEST_TEMP_DIR}/build_number_calls")
    count=$((count + 1))
    echo "$count" > "${TEST_TEMP_DIR}/build_number_calls"
    if [[ $count -le 1 ]]; then
        echo "41"
    else
        echo "42"
    fi
}

_wait_for_build_start "test-repo" "41"
EOF
    chmod +x "${TEST_TEMP_DIR}/queue_stdout_wrapper.sh"

    run bash -c "bash '${TEST_TEMP_DIR}/queue_stdout_wrapper.sh' >'${TEST_TEMP_DIR}/stdout.txt' 2>'${TEST_TEMP_DIR}/stderr.txt'"

    assert_success
    run cat "${TEST_TEMP_DIR}/stdout.txt"
    assert_output --partial "Waiting for Jenkins build test-repo to start"
    assert_output --partial "Build #42 is QUEUED"

    run cat "${TEST_TEMP_DIR}/stderr.txt"
    assert_output ""
}

@test "communication_error_goes_to_stderr" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR

    cat > "${TEST_TEMP_DIR}/comm_error_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() { echo "Started by user testuser"; }
get_current_stage() { echo "Build"; }
fetch_test_results() { return 2; }
get_all_stages() { echo "[]"; }
get_failed_stage() { echo ""; }

cmd_status --prior-jobs 0 --line
EOF
    chmod +x "${TEST_TEMP_DIR}/comm_error_wrapper.sh"

    run bash -c "bash '${TEST_TEMP_DIR}/comm_error_wrapper.sh' >'${TEST_TEMP_DIR}/stdout.txt' 2>'${TEST_TEMP_DIR}/stderr.txt'"

    assert_success
    run cat "${TEST_TEMP_DIR}/stdout.txt"
    assert_output --partial "Tests=!err!"
    refute_output --partial "Could not retrieve test results (communication error)"

    run cat "${TEST_TEMP_DIR}/stderr.txt"
    assert_output --partial "Could not retrieve test results (communication error)"
}

@test "invalid_option_error_goes_to_stderr" {
    cd "${TEST_REPO}"

    run bash -c "bash '${PROJECT_DIR}/buildgit' status --junk >'${TEST_TEMP_DIR}/stdout.txt' 2>'${TEST_TEMP_DIR}/stderr.txt'"

    assert_failure
    run cat "${TEST_TEMP_DIR}/stdout.txt"
    assert_output ""

    run cat "${TEST_TEMP_DIR}/stderr.txt"
    assert_output --partial "Unknown option for status command: --junk"
    assert_output --partial "Usage: buildgit"
}

@test "build_failure_output_goes_to_stdout" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR

    cat > "${TEST_TEMP_DIR}/failure_stdout_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"FAILURE","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() {
    echo "Started by user testuser"
    echo "build failed badly"
}
get_current_stage() { echo ""; }
fetch_test_results() { echo ""; }
get_all_stages() { echo "[]"; }
get_failed_stage() { echo ""; }

cmd_status --prior-jobs 0 --all
EOF
    chmod +x "${TEST_TEMP_DIR}/failure_stdout_wrapper.sh"

    run bash -c "bash '${TEST_TEMP_DIR}/failure_stdout_wrapper.sh' >'${TEST_TEMP_DIR}/stdout.txt' 2>'${TEST_TEMP_DIR}/stderr.txt'"

    assert_failure
    run cat "${TEST_TEMP_DIR}/stdout.txt"
    assert_output --partial "BUILD FAILED"
    assert_output --partial "build failed badly"
    assert_output --partial "Finished: FAILURE"

    run cat "${TEST_TEMP_DIR}/stderr.txt"
    assert_output ""
}

@test "verbose_output_goes_to_stdout" {
    cd "${TEST_REPO}"
    export PROJECT_DIR
    export TEST_TEMP_DIR

    cat > "${TEST_TEMP_DIR}/verbose_stdout_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

VERBOSE_MODE=true

verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
get_last_build_number() { echo "42"; }
get_build_info() {
    echo '{"number":42,"result":"SUCCESS","building":false,"timestamp":1706700000000,"duration":120000,"url":"http://jenkins.example.com/job/test-repo/42/"}'
}
get_console_output() { echo "Started by user testuser"; }
get_current_stage() { echo "Build"; }
fetch_test_results() { echo '{"passCount":120,"failCount":0,"skipCount":0}'; }
get_all_stages() { echo "[]"; }
get_failed_stage() { echo ""; }

cmd_status --prior-jobs 0
EOF
    chmod +x "${TEST_TEMP_DIR}/verbose_stdout_wrapper.sh"

    run bash -c "bash '${TEST_TEMP_DIR}/verbose_stdout_wrapper.sh' >'${TEST_TEMP_DIR}/stdout.txt' 2>'${TEST_TEMP_DIR}/stderr.txt'"

    assert_success
    run cat "${TEST_TEMP_DIR}/stdout.txt"
    assert_output --partial "Discovering Jenkins job name"
    assert_output --partial "Job name: test-repo"
    assert_output --partial "Verifying Jenkins connectivity"

    run cat "${TEST_TEMP_DIR}/stderr.txt"
    assert_output ""
}
