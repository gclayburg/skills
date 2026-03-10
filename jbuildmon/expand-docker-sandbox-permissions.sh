inject_env() {
    local sandbox_name="$1"
    # Persist Jenkins and git credentials in the sandbox
    local env_b64
    env_b64=$(base64 <<EOF
export JENKINS_URL="${JENKINS_URL:-}"
export JENKINS_USER_ID="${JENKINS_USER_ID:-}"
export JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"
export GIT_HTTPS_USER="${GIT_HTTPS_USER:-}"
export GIT_HTTPS_TOKEN="${GIT_HTTPS_TOKEN:-}"
EOF
)
    docker sandbox exec "$sandbox_name" sh -c "echo '$env_b64' | base64 -d > /etc/sandbox-persistent.sh"
    # Configure git credential helper for HTTPS push
    docker sandbox exec "$sandbox_name" git config --global credential.helper \
        '!f() { echo "username=${GIT_HTTPS_USER}"; echo "password=${GIT_HTTPS_TOKEN}"; }; f'
    echo "Environment variables injected into sandbox '$sandbox_name'"
}

configure_network() {
    local sandbox_name="$1"
SANDBOX_ALLOW_HOSTS="palmer.garyclayburg.com,jenkins.garyclayburg.com,git.garyclayburg.com"
    # SANDBOX_ALLOW_HOSTS is a comma-separated list of hostnames to allow
    # e.g. SANDBOX_ALLOW_HOSTS="palmer.garyclayburg.com,git.garyclayburg.com"
    if [[ -z "${SANDBOX_ALLOW_HOSTS:-}" ]]; then
        echo "Warning: SANDBOX_ALLOW_HOSTS not set — sandbox network will use default policy" >&2
        return 0
    fi
    local allow_args=()
    IFS=',' read -ra hosts <<< "$SANDBOX_ALLOW_HOSTS"
    for host in "${hosts[@]}"; do
        host=$(echo "$host" | xargs)  # trim whitespace
        allow_args+=(--allow-host "$host")
    done
    docker sandbox network proxy "$sandbox_name" --policy allow "${allow_args[@]}"
    echo "Network proxy configured: ${hosts[*]}"
}

