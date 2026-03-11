#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
    TEST_TEMP_DIR="$(mktemp -d)"

    export JENKINS_URL="http://jenkins.example.com"
    export JENKINS_USER_ID="testuser"
    export JENKINS_API_TOKEN="testtoken"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

@test "jenkins_api_disables_curl_globbing_for_tree_queries" {
    mkdir -p "${TEST_TEMP_DIR}/bin"
    cat > "${TEST_TEMP_DIR}/bin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${TEST_TEMP_DIR}/curl_args.txt"
printf '{"computer":[]}'
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/curl"

    run bash -c "export PATH=\"${TEST_TEMP_DIR}/bin:\$PATH\"; source \"${PROJECT_DIR}/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh\"; jenkins_api '/computer/api/json?tree=computer[displayName,assignedLabels[name]]'"

    assert_success
    assert_output '{"computer":[]}'
    run cat "${TEST_TEMP_DIR}/curl_args.txt"
    assert_success
    assert_output --partial "-g"
    assert_output --partial "/computer/api/json?tree=computer[displayName,assignedLabels[name]]"
}
