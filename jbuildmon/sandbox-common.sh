# sandbox-common.sh - Shared sandbox setup functions
#
# Source this file from scripts that create or configure docker sandboxes:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/sandbox-common.sh"
#
# Expected env vars (set by the sourcing script):
#   AUTH_FILE             - path to codex auth.json (required by inject_auth)
#   SANDBOX_ALLOW_HOSTS   - comma-separated hostnames for network proxy (optional)
#   JENKINS_URL, JENKINS_USER_ID, JENKINS_API_TOKEN
#   GIT_HTTPS_USER, GIT_HTTPS_TOKEN

inject_auth() {
    local sandbox_name="$1"
    # Codex sandbox runs as 'agent' user with home at /home/agent
    # stdin redirection doesn't work with docker sandbox exec, so use base64
    local auth_b64
    auth_b64=$(base64 < "$AUTH_FILE")
    docker sandbox exec "$sandbox_name" mkdir -p /home/agent/.codex
    docker sandbox exec "$sandbox_name" sh -c "echo '$auth_b64' | base64 -d > /home/agent/.codex/auth.json"
    echo "Codex credentials injected into sandbox '$sandbox_name'"
}

inject_claude_auth() {
    local sandbox_name="$1"
    # Extract Claude Code OAuth credentials from macOS Keychain and inject into sandbox
    # On Linux, Claude Code reads from /home/agent/.claude/.credentials.json
    local creds
    creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
    if [[ -z "$creds" ]]; then
        echo "Warning: Claude Code credentials not found in macOS Keychain — skipping" >&2
        return 0
    fi
    local creds_b64
    creds_b64=$(printf '%s' "$creds" | base64)
    docker sandbox exec "$sandbox_name" mkdir -p /home/agent/.claude
    docker sandbox exec "$sandbox_name" sh -c "echo '$creds_b64' | base64 -d > /home/agent/.claude/.credentials.json && chmod 600 /home/agent/.claude/.credentials.json"
    echo "Claude Code credentials injected into sandbox '$sandbox_name'"

    # Also inject ~/.claude.json from the host — contains hasCompletedOnboarding,
    # oauthAccount, and other state Claude Code checks before showing the login flow
    local claude_json="${HOME}/.claude.json"
    if [[ -f "$claude_json" ]]; then
        local json_b64
        json_b64=$(base64 < "$claude_json")
        docker sandbox exec "$sandbox_name" sh -c "echo '$json_b64' | base64 -d > /home/agent/.claude.json && chmod 600 /home/agent/.claude.json"
        echo "Claude Code state injected into sandbox '$sandbox_name'"
    fi
}

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
