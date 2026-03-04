#!/usr/bin/env bash
#
# implement-spec.sh - Implement a DRAFT spec in an isolated worktree using codex docker sandbox
#
# Usage:
#   ./jbuildmon/implement-spec.sh [--model <model>] <spec-file>
#
# Creates a git worktree with a branch named from the spec title,
# then runs the codex docker sandbox to implement the spec.
#
# Requires auth credentials at ~/.cache/codex-sandbox-auth/auth.json
# (copy from ~/.codex/auth.json after running: codex login --device-auth)
#
# Options:
#   --model <model>   Model to use (default: gpt-5.3-codex)
#
# Examples:
#   ./jbuildmon/implement-spec.sh jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --model gpt-5.1-codex-mini jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md

set -euo pipefail

MODEL="gpt-5.3-codex"
SPEC=""
AUTH_CACHE_DIR="${HOME}/.cache/codex-sandbox-auth"
# auth file created like this from an alredy authenticated docker sandbox:
# docker sandbox exec  codex-phandlemono cat /home/agent/.codex/auth.json > ~/.cache/codex-sandbox-auth/auth.json

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            MODEL="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,/^$/s/^# //p' "$0"
            exit 0
            ;;
        *)
            if [[ -z "$SPEC" ]]; then
                SPEC="$1"
            else
                echo "Error: unexpected argument '$1'" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$SPEC" ]]; then
    echo "Usage: $0 [--model <model>] <spec-file>" >&2
    exit 1
fi

if [[ ! -f "$SPEC" ]]; then
    echo "Error: spec file not found: $SPEC" >&2
    exit 1
fi

# =============================================================================
# Credential check
# =============================================================================
AUTH_FILE="$AUTH_CACHE_DIR/auth.json"
if [[ ! -f "$AUTH_FILE" ]]; then
    echo "Error: credentials not found at $AUTH_FILE" >&2
    echo "Create it by copying from ~/.codex/auth.json after running:" >&2
    echo "  codex login --device-auth" >&2
    exit 1
fi
echo "Using codex credentials from $AUTH_FILE"

inject_auth() {
    local sandbox_name="$1"
    # Codex sandbox runs as 'agent' user with home at /home/agent
    # stdin redirection doesn't work with docker sandbox exec, so use base64
    local auth_b64
    auth_b64=$(base64 < "$AUTH_FILE")
    docker sandbox exec "$sandbox_name" mkdir -p /home/agent/.codex
    docker sandbox exec "$sandbox_name" sh -c "echo '$auth_b64' | base64 -d > /home/agent/.codex/auth.json"
    echo "Credentials injected into sandbox '$sandbox_name'"
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

# =============================================================================
# Worktree setup
# =============================================================================

# Extract title from spec (first ## heading)
TITLE=$(grep -m1 '^## ' "$SPEC" | sed 's/^## //')
if [[ -z "$TITLE" ]]; then
    echo "Error: could not find ## title in $SPEC" >&2
    exit 1
fi

# Slugify title for branch name (keep short to avoid Docker socket path length limit)
BRANCH=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-30)

# Get repo root
REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR="$REPO_ROOT/.claude/worktrees/$BRANCH"
SANDBOX_NAME="codex-${BRANCH}"

# Resolve spec path to absolute, then make relative to repo root
SPEC_ABS=$(realpath "$SPEC")
SPEC_REL="${SPEC_ABS#$REPO_ROOT/}"

echo
echo "Spec:      $SPEC_REL"
echo "Title:     $TITLE"
echo "Branch:    $BRANCH"
echo "Model:     $MODEL"
echo "Worktree:  $WORKTREE_DIR"
echo "Sandbox:   $SANDBOX_NAME"

# Collect referenced files from the spec's References: header
REF_FILES=()
ref_line=$(grep -m1 '^\- \*\*References:\*\*' "$SPEC" | sed 's/^- \*\*References:\*\* //' || true)
if [[ -n "$ref_line" ]] && [[ "$ref_line" != "none" ]]; then
    # Extract backtick-quoted paths
    while IFS= read -r ref_path; do
        # References are relative to specs dir; resolve to repo root
        full_path="$REPO_ROOT/jbuildmon/$ref_path"
        if [[ -f "$full_path" ]]; then
            REF_FILES+=("${full_path#$REPO_ROOT/}")
        fi
    done < <(echo "$ref_line" | grep -oE '`[^`]+`' | tr -d '`')
fi

if [[ ${#REF_FILES[@]} -gt 0 ]]; then
    echo "Refs:      ${REF_FILES[*]}"
fi
echo

# Create worktree
if [[ -d "$WORKTREE_DIR" ]]; then
    echo "Worktree already exists at $WORKTREE_DIR"
else
    echo "Creating worktree..."
    git worktree add -b "$BRANCH" "$WORKTREE_DIR" HEAD
    echo "Initializing submodules in worktree..."
    # Use main repo's submodules as reference to avoid network clones
    git -C "$WORKTREE_DIR" submodule update --init --recursive --reference "$REPO_ROOT"
fi

# =============================================================================
# Commit spec and referenced files on the branch
# =============================================================================
echo
echo "Committing spec to branch '$BRANCH'..."

# Copy spec file into worktree if not already tracked
cp "$SPEC_ABS" "$WORKTREE_DIR/$SPEC_REL"
git -C "$WORKTREE_DIR" add "$SPEC_REL"

# Copy and add referenced files
for ref in "${REF_FILES[@]}"; do
    ref_src="$REPO_ROOT/$ref"
    ref_dst="$WORKTREE_DIR/$ref"
    mkdir -p "$(dirname "$ref_dst")"
    cp "$ref_src" "$ref_dst"
    git -C "$WORKTREE_DIR" add "$ref"
done

# Only commit if there are staged changes
if ! git -C "$WORKTREE_DIR" diff --cached --quiet; then
    git -C "$WORKTREE_DIR" commit -m "add DRAFT spec: $TITLE"
    echo "Committed spec and references to branch '$BRANCH'"
else
    echo "Spec already committed on branch '$BRANCH'"
fi

# =============================================================================
# Create sandbox, inject auth, then run codex
# =============================================================================
echo
echo "Creating sandbox..."
# Mount the parent repo's .git dir so worktree git metadata resolves correctly
GIT_DIR="$REPO_ROOT/.git"
docker sandbox create --name "$SANDBOX_NAME" codex "$WORKTREE_DIR" "$GIT_DIR"

echo "Injecting credentials..."
inject_auth "$SANDBOX_NAME"

echo "Injecting environment..."
inject_env "$SANDBOX_NAME"

echo "Configuring network..."
configure_network "$SANDBOX_NAME"

echo
echo "Starting codex..."
echo
PROMPT="implement the DRAFT spec $SPEC . After implementation is complete and all tests pass, run 'buildgit push jenkins' to push your changes and verify the Jenkins CI build succeeds with no test failures. If the build fails, fix the issues and push again."
#PROMPT="add a blank line to a file named nonsensebuidltrigger.md, commit it, and then push it using 'buildgit push jenkins'.  After the build is complete, verify the build was successful and the test results are displayed."
docker sandbox run "$SANDBOX_NAME" -- exec --model "$MODEL" -c model_reasoning_effort="medium" "$PROMPT"
