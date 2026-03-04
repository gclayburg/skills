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
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

create_multibranch_wrapper() {
    sed -e '/^main "\$@"$/d' \
        -e 's|source "\${SCRIPT_DIR}/lib/jenkins-common.sh"|source "'"${PROJECT_DIR}"'/lib/jenkins-common.sh"|g' \
        "${PROJECT_DIR}/buildgit" > "${TEST_TEMP_DIR}/buildgit_no_main.sh"

    cat > "${TEST_TEMP_DIR}/mb_wrapper.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

_BUILDGIT_TESTING=1
source "${TEST_TEMP_DIR}/buildgit_no_main.sh"

_get_current_git_branch() {
    if [[ -n "${MOCK_CURRENT_BRANCH:-}" ]]; then
        echo "${MOCK_CURRENT_BRANCH}"
        return 0
    fi

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    if [[ -z "$current_branch" || "$current_branch" == "HEAD" ]]; then
        return 1
    fi
    echo "$current_branch"
}

validate_dependencies() { return 0; }
validate_environment() { return 0; }
verify_jenkins_connection() { return 0; }
verify_job_exists() {
    echo "VERIFY_JOB=$1"
    return 0
}

get_jenkins_job_type() {
    if [[ "${MOCK_JOB_TYPE:-pipeline}" == "multibranch" ]]; then
        echo "multibranch"
    else
        echo "pipeline"
    fi
}

multibranch_branch_exists() {
    local expected="${EXPECTED_BRANCH:-}"
    [[ "$2" == "$expected" ]]
}

JOB_NAME="${MOCK_JOB_NAME:-ralph1}"
if [[ "${MOCK_PUSH_ARGS_SET_EMPTY:-false}" == "true" ]]; then
    PUSH_GIT_ARGS=()
elif [[ -n "${MOCK_PUSH_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    PUSH_GIT_ARGS=(${MOCK_PUSH_ARGS})
fi

if [[ "${MOCK_INFER_ONLY:-false}" == "true" ]]; then
    _infer_push_branch_from_args
    exit $?
fi

if _validate_jenkins_setup "test context" "${MOCK_MODE:-status}"; then
    echo "RESOLVED_JOB=${_VALIDATED_JOB_NAME}"
else
    exit 1
fi
EOF
    chmod +x "${TEST_TEMP_DIR}/mb_wrapper.sh"
}

@test "jenkins_job_path encodes multibranch branch segment" {
    run bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        echo \"\$(jenkins_job_path 'ralph1')\"
        echo \"\$(jenkins_job_path 'ralph1/feature/new-api')\"
    "

    assert_success
    assert_line --index 0 "/job/ralph1"
    assert_line --index 1 "/job/ralph1/job/feature%2Fnew-api"
}

@test "get_jenkins_job_type maps Jenkins class names" {
    run bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        jenkins_api() { echo '{\"_class\":\"org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject\"}'; }
        get_jenkins_job_type 'ralph1'
    "
    assert_success
    assert_output "multibranch"

    run bash -c "
        source '${PROJECT_DIR}/lib/jenkins-common.sh'
        jenkins_api() { echo '{\"_class\":\"org.jenkinsci.plugins.workflow.job.WorkflowJob\"}'; }
        get_jenkins_job_type 'ralph1'
    "
    assert_success
    assert_output "pipeline"
}

@test "status resolves multibranch job to current branch" {
    cd "${TEST_REPO}"
    git checkout -qb "feature/multi-status"

    export PROJECT_DIR TEST_TEMP_DIR
    create_multibranch_wrapper

    run env \
        MOCK_JOB_TYPE="multibranch" \
        MOCK_MODE="status" \
        EXPECTED_BRANCH="feature/multi-status" \
        bash "${TEST_TEMP_DIR}/mb_wrapper.sh" 2>&1

    assert_success
    assert_output --partial "RESOLVED_JOB=ralph1/feature/multi-status"
    assert_output --partial "VERIFY_JOB=ralph1/feature/multi-status"
}

@test "push resolves multibranch job to branch from push args" {
    cd "${TEST_REPO}"
    git checkout -qb "feature/local-only"

    export PROJECT_DIR TEST_TEMP_DIR
    create_multibranch_wrapper

    run env \
        MOCK_JOB_TYPE="multibranch" \
        MOCK_MODE="push" \
        MOCK_PUSH_ARGS="jenkins feature/from-push-args" \
        EXPECTED_BRANCH="feature/from-push-args" \
        bash "${TEST_TEMP_DIR}/mb_wrapper.sh" 2>&1

    assert_success
    assert_output --partial "RESOLVED_JOB=ralph1/feature/from-push-args"
    assert_output --partial "VERIFY_JOB=ralph1/feature/from-push-args"
}

@test "_infer_push_branch_from_args uses current branch when push args empty" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_multibranch_wrapper

    run env \
        MOCK_INFER_ONLY="true" \
        MOCK_PUSH_ARGS_SET_EMPTY="true" \
        MOCK_CURRENT_BRANCH="main" \
        bash "${TEST_TEMP_DIR}/mb_wrapper.sh" 2>&1

    assert_success
    assert_output "main"
}

@test "_infer_push_branch_from_args returns positional branch when provided" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_multibranch_wrapper

    run env \
        MOCK_INFER_ONLY="true" \
        MOCK_PUSH_ARGS="origin feature-x" \
        bash "${TEST_TEMP_DIR}/mb_wrapper.sh" 2>&1

    assert_success
    assert_output "feature-x"
}

@test "_infer_push_branch_from_args uses current branch when only remote is provided" {
    export PROJECT_DIR TEST_TEMP_DIR
    create_multibranch_wrapper

    run env \
        MOCK_INFER_ONLY="true" \
        MOCK_PUSH_ARGS="origin" \
        MOCK_CURRENT_BRANCH="main" \
        bash "${TEST_TEMP_DIR}/mb_wrapper.sh" 2>&1

    assert_success
    assert_output "main"
}

@test "explicit job/branch fails for pipeline jobs" {
    cd "${TEST_REPO}"
    git checkout -qb "feature/unused"

    export PROJECT_DIR TEST_TEMP_DIR
    create_multibranch_wrapper

    run env \
        MOCK_JOB_TYPE="pipeline" \
        MOCK_MODE="status" \
        MOCK_JOB_NAME="ralph1/main" \
        bash "${TEST_TEMP_DIR}/mb_wrapper.sh" 2>&1

    assert_failure
    assert_output --partial "Jenkins job 'ralph1/main' not found"
}

@test "missing multibranch branch prints actionable error" {
    cd "${TEST_REPO}"
    git checkout -qb "feature/not-scanned"

    export PROJECT_DIR TEST_TEMP_DIR
    create_multibranch_wrapper

    run env \
        MOCK_JOB_TYPE="multibranch" \
        MOCK_MODE="status" \
        EXPECTED_BRANCH="feature/other-branch" \
        bash "${TEST_TEMP_DIR}/mb_wrapper.sh" 2>&1

    assert_failure
    assert_output --partial "Branch 'feature/not-scanned' not found in multibranch job 'ralph1'. Push the branch and wait for Jenkins to scan."
}
