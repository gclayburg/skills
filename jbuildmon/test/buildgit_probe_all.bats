#!/usr/bin/env bats

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
    echo "seed" > README.md
    git add README.md
    git commit --quiet -m "seed"
    git checkout -qb "main"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

run_probe_all_monitor_helper() {
    local helper_name="$1"
    shift

    cat > "${TEST_TEMP_DIR}/probe_all_monitor_helper.sh" <<EOF
#!/usr/bin/env bash
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/job_helpers.sh"
source "${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/monitor_helpers.sh"
export TEST_TEMP_DIR="${TEST_TEMP_DIR}"
export PROJECT_DIR="${PROJECT_DIR}"
export POLL_INTERVAL=0
poll_count_file="\$TEST_TEMP_DIR/poll_count"
echo 0 > "\$poll_count_file"
jenkins_api() {
    local count
    count=\$(cat "\$poll_count_file")
    count=\$((count + 1))
    echo "\$count" > "\$poll_count_file"
    if [[ \$count -eq 1 ]]; then
        cat "\$PROJECT_DIR/test/fixtures/multibranch_jobs_baseline.json"
    else
        cat "\$PROJECT_DIR/test/fixtures/${PROBE_FIXTURE}"
    fi
}
"\$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/probe_all_monitor_helper.sh"

    run "${TEST_TEMP_DIR}/probe_all_monitor_helper.sh" "$helper_name" "$@" 3>&- 2>&1
}

create_probe_all_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/probe_all_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

validate_dependencies() { return 0; }
validate_environment() { return 0; }
verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
get_jenkins_job_type() {
    echo "${MOCK_JOB_TYPE:-multibranch}"
}
multibranch_branch_exists() {
    return 0
}
_cmd_status_follow() {
    echo "FOLLOW_JOB=$1"
    echo "FOLLOW_PROBE_ALL=${8:-false}"
    return 0
}

JOB_NAME="${MOCK_JOB_NAME:-ralph1}"
cmd_status "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/probe_all_wrapper.sh"
}

create_probe_all_follow_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/probe_all_follow_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

export POLL_INTERVAL=0
export MAX_BUILD_TIME=10

validate_dependencies() { return 0; }
validate_environment() { return 0; }
verify_jenkins_connection() { return 0; }
verify_job_exists() {
    JOB_URL="${JENKINS_URL}/job/$1"
    return 0
}
get_jenkins_job_type() {
    echo "${MOCK_JOB_TYPE:-multibranch}"
}
multibranch_branch_exists() {
    return 0
}
discover_job_name() {
    echo "ralph1"
}
get_last_build_number() {
    case "$1" in
        ralph1/feature-x)
            echo "13"
            ;;
        ralph1/main)
            echo "86"
            ;;
        *)
            echo "0"
            ;;
    esac
}
get_build_info() {
    local key="${1}#${2}"
    local state_file="${TEST_TEMP_DIR}/$(echo "${key}" | tr '/#' '__').count"
    local count=0
    if [[ -f "$state_file" ]]; then
        count=$(cat "$state_file")
    fi
    count=$((count + 1))
    echo "$count" > "$state_file"

    if [[ "${MOCK_JSON_ONCE:-false}" == "true" ]]; then
        if [[ "$count" -eq 1 ]]; then
            echo "{\"number\":${2},\"result\":null,\"building\":true,\"timestamp\":1706700000000,\"duration\":0,\"url\":\"http://jenkins.example.com/job/${1}/${2}/\"}"
        else
            echo "{\"number\":${2},\"result\":\"SUCCESS\",\"building\":false,\"timestamp\":1706700000000,\"duration\":120000,\"url\":\"http://jenkins.example.com/job/${1}/${2}/\"}"
        fi
        return 0
    fi

    if [[ "${MOCK_BUILDING_FIRST:-true}" == "true" && "$count" -eq 1 ]]; then
        echo "{\"number\":${2},\"result\":null,\"building\":true,\"timestamp\":1706700000000,\"duration\":0,\"url\":\"http://jenkins.example.com/job/${1}/${2}/\"}"
    else
        echo "{\"number\":${2},\"result\":\"SUCCESS\",\"building\":false,\"timestamp\":1706700000000,\"duration\":120000,\"url\":\"http://jenkins.example.com/job/${1}/${2}/\"}"
    fi
}
_display_monitoring_preamble() {
    echo "PREAMBLE job=$1 prior=$2 no_tests=$3 max=${4:-}"
}
_display_build_in_progress_banner() {
    echo "BANNER job=$1 build=$2"
}
_monitor_build() {
    echo "MONITOR job=$1 build=$2"
    return 0
}
_monitor_build_line_mode() {
    echo "LINE job=$1 build=$2"
    return 0
}
_handle_build_completion() {
    echo "COMPLETE job=$1 build=$2"
    return 0
}
_display_completed_build() {
    local count_file="${TEST_TEMP_DIR}/completed_display_count"
    local count=0
    if [[ -f "$count_file" ]]; then
        count=$(cat "$count_file")
    fi
    count=$((count + 1))
    echo "$count" > "$count_file"
    echo "DISPLAY job=$1 build=$2"
    if [[ "${STOP_AFTER_COMPLETIONS:-0}" -gt 0 && "$count" -ge "${STOP_AFTER_COMPLETIONS:-0}" ]]; then
        exit 0
    fi
    return 0
}
_status_line_for_build_json() {
    echo "LINE-STATUS job=$1 build=$2 result=$(echo "$3" | jq -r '.result // "UNKNOWN"')"
    return 0
}
_jenkins_status_check() {
    echo "{\"job\":\"$1\",\"build\":$3,\"result\":\"SUCCESS\"}"
    return 0
}
_follow_wait_probe_all() {
    local count_file="${TEST_TEMP_DIR}/probe_wait_count"
    local count=0
    if [[ -f "$count_file" ]]; then
        count=$(cat "$count_file")
    fi
    count=$((count + 1))
    echo "$count" > "$count_file"
    echo "[00:00:00] INFO Waiting for Jenkins build ralph1 (any branch) to start..."
    if [[ "$count" -eq 1 ]]; then
        echo "[00:00:00] INFO Build detected on branch 'feature-x' — following ralph1/feature-x #13"
        echo "feature-x 13"
    else
        echo "[00:00:00] INFO Build detected on branch 'main' — following ralph1/main #86"
        echo "main 86"
    fi
}
_follow_wait_probe_all_timeout() {
    echo "[00:00:00] INFO Waiting for Jenkins build ralph1 (any branch) to start..."
    if [[ "${MOCK_PROBE_TIMEOUT_FAIL:-false}" == "true" ]]; then
        return 1
    fi
    echo "[00:00:00] INFO Build detected on branch 'feature-x' — following ralph1/feature-x #13"
    echo "feature-x 13"
}

JOB_NAME="${MOCK_JOB_NAME:-ralph1}"
cmd_status "$@"
EOF
    chmod +x "${TEST_TEMP_DIR}/probe_all_follow_wrapper.sh"
}

# Spec: status-follow-probe-all-branches-spec.md, Flag validation
@test "probe_all_requires_follow_flag" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_wrapper

    run bash "${TEST_TEMP_DIR}/probe_all_wrapper.sh" --probe-all 2>&1

    assert_failure
    assert_output --partial "Error: --probe-all requires --follow (-f)"
}

# Spec: status-follow-probe-all-branches-spec.md, Flag validation
@test "probe_all_rejects_explicit_branch_job" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_wrapper

    run env MOCK_JOB_NAME="ralph1/main" bash "${TEST_TEMP_DIR}/probe_all_wrapper.sh" -f --probe-all 2>&1

    assert_failure
    assert_output --partial "Error: --probe-all requires a top-level multibranch job name, not an explicit branch job"
}

# Spec: status-follow-probe-all-branches-spec.md, Flag validation
@test "probe_all_allows_top_level_job" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_wrapper

    run env MOCK_JOB_TYPE="multibranch" bash "${TEST_TEMP_DIR}/probe_all_wrapper.sh" -f --probe-all 2>&1

    assert_success
    assert_output --partial "FOLLOW_PROBE_ALL=true"
}

# Spec: status-follow-probe-all-branches-spec.md, Flag validation
@test "probe_all_non_multibranch_warns_and_falls_back" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_wrapper

    run env MOCK_JOB_TYPE="pipeline" bash "${TEST_TEMP_DIR}/probe_all_wrapper.sh" -f --probe-all 2>&1

    assert_success
    assert_output --partial "--probe-all is only supported for multibranch pipeline jobs; falling back to normal follow mode"
    assert_output --partial "FOLLOW_PROBE_ALL=false"
}

# Spec: status-follow-probe-all-branches-spec.md, Jenkins API for multibranch branch listing
@test "fetch_multibranch_baselines_returns_branch_map" {
    run bash -c "
        source '${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh'
        source '${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/job_helpers.sh'
        jenkins_api() { cat '${PROJECT_DIR}/test/fixtures/multibranch_jobs_baseline.json'; }
        _fetch_multibranch_baselines 'ralph1'
    "

    assert_success
    assert_equal "$(echo "$output" | jq -r '.main')" "85"
    assert_equal "$(echo "$output" | jq -r '."feature-x"')" "12"
}

# Spec: status-follow-probe-all-branches-spec.md, Jenkins API for multibranch branch listing
@test "fetch_multibranch_baselines_handles_no_builds" {
    run bash -c "
        source '${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh'
        source '${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/job_helpers.sh'
        jenkins_api() { cat '${PROJECT_DIR}/test/fixtures/multibranch_jobs_baseline.json'; }
        _fetch_multibranch_baselines 'ralph1'
    "

    assert_success
    assert_equal "$(echo "$output" | jq -r '."new-empty-branch"')" "0"
}

# Spec: status-follow-probe-all-branches-spec.md, Polling behavior
@test "probe_all_detects_new_build_on_existing_branch" {
    export PROBE_FIXTURE="multibranch_jobs_new_build.json"

    run_probe_all_monitor_helper "_follow_wait_probe_all" "ralph1"

    assert_success
    assert_line --index 2 "feature-x 13"
}

# Spec: status-follow-probe-all-branches-spec.md, Polling behavior
@test "probe_all_detects_new_branch" {
    export PROBE_FIXTURE="multibranch_jobs_new_branch.json"

    run_probe_all_monitor_helper "_follow_wait_probe_all" "ralph1"

    assert_success
    assert_line --index 2 "feature-y 1"
}

# Spec: status-follow-probe-all-branches-spec.md, Output messages
@test "probe_all_waiting_message" {
    export PROBE_FIXTURE="multibranch_jobs_new_build.json"

    run_probe_all_monitor_helper "_follow_wait_probe_all" "ralph1"

    assert_success
    assert_line --index 0 --partial "Waiting for Jenkins build ralph1 (any branch) to start..."
}

# Spec: status-follow-probe-all-branches-spec.md, Output messages
@test "probe_all_shows_branch_detection_message" {
    export PROBE_FIXTURE="multibranch_jobs_new_build.json"

    run_probe_all_monitor_helper "_follow_wait_probe_all" "ralph1"

    assert_success
    assert_output --partial "Build detected on branch 'feature-x'"
}

# Spec: status-follow-probe-all-branches-spec.md, Polling behavior
@test "probe_all_timeout_returns_failure" {
    export PROBE_FIXTURE="multibranch_jobs_baseline.json"

    run_probe_all_monitor_helper "_follow_wait_probe_all_timeout" "ralph1" "0"

    assert_failure
    assert_line --index 0 --partial "Waiting for Jenkins build ralph1 (any branch) to start..."
}

# Spec: status-follow-probe-all-branches-spec.md, Interaction with existing flags
@test "probe_all_with_once_exits_after_build" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_follow_wrapper

    run bash "${TEST_TEMP_DIR}/probe_all_follow_wrapper.sh" -f --probe-all --once 3>&- 2>&1

    assert_success
    assert_output --partial "BANNER job=ralph1/feature-x build=13"
    assert_output --partial "MONITOR job=ralph1/feature-x build=13"
    assert_output --partial "COMPLETE job=ralph1/feature-x build=13"
}

# Spec: status-follow-probe-all-branches-spec.md, Interaction with existing flags
@test "probe_all_with_once_timeout_exits_on_timeout" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_follow_wrapper

    run env MOCK_PROBE_TIMEOUT_FAIL="true" bash "${TEST_TEMP_DIR}/probe_all_follow_wrapper.sh" -f --probe-all --once=2 3>&- 2>&1

    assert_failure
    assert_equal "$status" "2"
    assert_output --partial "no new build detected for 2 seconds"
}

# Spec: status-follow-probe-all-branches-spec.md, Polling behavior
@test "probe_all_continuous_rebaselines_after_build" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_follow_wrapper

    run env MOCK_BUILDING_FIRST="false" STOP_AFTER_COMPLETIONS="2" bash "${TEST_TEMP_DIR}/probe_all_follow_wrapper.sh" -f --probe-all 3>&- 2>&1

    assert_success
    assert_output --partial "DISPLAY job=ralph1/feature-x build=13"
    assert_output --partial "DISPLAY job=ralph1/main build=86"
    assert_equal "$(grep -c "Waiting for Jenkins build ralph1 (any branch) to start..." <<< "$output")" "2"
}

# Spec: status-follow-probe-all-branches-spec.md, Interaction with existing flags
@test "probe_all_line_mode_works" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_follow_wrapper

    run bash "${TEST_TEMP_DIR}/probe_all_follow_wrapper.sh" -f --probe-all --line --once 3>&- 2>&1

    assert_success
    assert_output --partial "LINE job=ralph1/feature-x build=13"
}

# Spec: status-follow-probe-all-branches-spec.md, Interaction with existing flags
@test "probe_all_json_mode_works" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_probe_all_follow_wrapper

    run env MOCK_JSON_ONCE="true" bash "${TEST_TEMP_DIR}/probe_all_follow_wrapper.sh" -f --probe-all --json --once 3>&- 2>&1

    assert_success
    assert_output --partial "\"job\":\"ralph1/feature-x\""
    assert_output --partial "\"build\":13"
}

# Spec: status-follow-probe-all-branches-spec.md, Commands affected
@test "probe_all_push_command_unaffected" {
    run bash -c "
        set -euo pipefail
        trap '' PIPE
        source '${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common.sh'
        source '${PROJECT_DIR}/skill/buildgit/scripts/lib/buildgit/job_helpers.sh'
        _DEFAULT_LINE_FORMAT='%s #%n'
        _parse_push_options --probe-all
        printf '%s\n' \"\${PUSH_GIT_ARGS[*]}\"
    " 3>&- 2>&1

    assert_success
    assert_equal "$output" "--probe-all"
}
