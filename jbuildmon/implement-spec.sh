#!/usr/bin/env bash
#
# implement-spec.sh - Implement a DRAFT spec in an isolated worktree using codex docker sandbox
#
# Usage:
#   ./jbuildmon/implement-spec.sh [--model <model>] <spec-file>
#   ./jbuildmon/implement-spec.sh --merge <spec-file>
#   ./jbuildmon/implement-spec.sh --delete-all <spec-file>
#   ./jbuildmon/implement-spec.sh --redo <spec-file>
#   ./jbuildmon/implement-spec.sh --bugfix "description" <spec-file>
#
# Creates a git worktree with a branch named from the spec title,
# then runs the codex docker sandbox to implement the spec.
#
# With --merge, merges the previously created branch back into the current
# branch, then offers to clean up the sandbox, worktree, and branch.
#
# With --delete-all, skips the merge and just cleans up the sandbox, worktree,
# and branch (force-deletes the branch even if unmerged).
#
# With --redo, re-runs the codex prompt in an existing sandbox/worktree/branch
# (e.g. after refreshing credentials). Exits with an error if the environment
# is not already set up.
#
# With --bugfix, re-runs codex in an existing sandbox with a bug-fix prompt
# instead of the implementation prompt. Requires the sandbox/worktree/branch
# to already exist (like --redo).
#
# Requires auth credentials at ~/.cache/codex-sandbox-auth/auth.json
# (copy from ~/.codex/auth.json after running: codex login --device-auth)
#
# Options:
#   --model <model>   Model to use (default: gpt-5.3-codex)
#   --merge           Merge the spec branch and clean up artifacts
#   --delete-all      Delete sandbox, worktree, and branch without merging
#   --redo [text]     Re-run codex in an existing sandbox (inject fresh creds)
#                     Optional text is appended to the prompt
#   --bugfix <text>   Fix a bug in an already-implemented spec
#                     Text can be inline or piped from stdin
#
# Examples:
#   ./jbuildmon/implement-spec.sh jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --model gpt-5.1-codex-mini jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --merge jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --delete-all jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --redo jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --redo "also fix the edge case in parse()" jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --bugfix "substages not shown for --console-text" jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md
#   ./jbuildmon/implement-spec.sh --bugfix jbuildmon/specs/2026-03-03_short-buildgit-status-spec.md < /tmp/bugreport.md

set -euo pipefail

MODE="run"
# MODEL="gpt-5.3-codex"
MODEL="gpt-5.4"
SPEC=""
REDO_EXTRA=""
BUGFIX_TEXT=""
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
        --merge)
            MODE="merge"
            shift
            ;;
        --delete-all)
            MODE="delete-all"
            shift
            ;;
        --redo)
            MODE="redo"
            # Consume optional extra prompt: next arg if it's not a flag and not a file
            if [[ $# -ge 2 && "$2" != -* && ! -f "$2" ]]; then
                REDO_EXTRA="$2"
                shift 2
            else
                shift
            fi
            ;;
        --bugfix)
            MODE="bugfix"
            # Consume optional inline text: next arg if it's not a flag and not a file
            if [[ $# -ge 2 && "$2" != -* && ! -f "$2" ]]; then
                BUGFIX_TEXT="$2"
                shift 2
            else
                shift
            fi
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

# Read bugfix text from stdin if piped and no inline text was given
if [[ "$MODE" == "bugfix" && -z "$BUGFIX_TEXT" ]]; then
    if [[ ! -t 0 ]]; then
        BUGFIX_TEXT=$(cat)
    fi
    if [[ -z "$BUGFIX_TEXT" ]]; then
        echo "Error: --bugfix requires a description string or piped input" >&2
        exit 1
    fi
fi

if [[ -z "$SPEC" ]]; then
    echo "Usage: $0 [--model <model>] <spec-file>" >&2
    exit 1
fi

if [[ ! -f "$SPEC" ]]; then
    echo "Error: spec file not found: $SPEC" >&2
    exit 1
fi

# =============================================================================
# Credential check (only needed for run mode)
# =============================================================================
AUTH_FILE="$AUTH_CACHE_DIR/auth.json"
if [[ "$MODE" != "merge" && "$MODE" != "delete-all" ]]; then
    # run and redo modes need credentials
    if [[ ! -f "$AUTH_FILE" ]]; then
        echo "Error: credentials not found at $AUTH_FILE" >&2
        echo "Create it by copying from ~/.codex/auth.json after running:" >&2
        echo "  codex login --device-auth" >&2
        exit 1
    fi
    echo "Using codex credentials from $AUTH_FILE"
fi

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
echo "Mode:      $MODE"
echo "Model:     $MODEL"
echo "Worktree:  $WORKTREE_DIR"
echo "Sandbox:   $SANDBOX_NAME"
if [[ -n "$BUGFIX_TEXT" ]]; then
    echo "Bugfix:    $BUGFIX_TEXT"
fi

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

# =============================================================================
# --merge / --delete-all mode: optionally merge, then clean up artifacts
# =============================================================================
if [[ "$MODE" == "merge" || "$MODE" == "delete-all" ]]; then
    # Merge first if requested
    if [[ "$MODE" == "merge" ]]; then
        if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
            echo "Error: branch '$BRANCH' does not exist" >&2
            exit 1
        fi

        echo "Merging branch '$BRANCH' into $(git rev-parse --abbrev-ref HEAD)..."
        if ! git merge "$BRANCH"; then
            echo "Error: merge failed. Resolve conflicts and try again." >&2
            exit 1
        fi
        echo "Merge successful."
        echo
    fi

    # Build cleanup plan
    if [[ "$MODE" == "delete-all" ]]; then
        echo "Cleanup plan (no merge):"
    else
        echo "Cleanup plan:"
    fi
    CLEANUP_CMDS=()
    if docker sandbox list 2>&1 | grep -q "$SANDBOX_NAME"; then
        CLEANUP_CMDS+=("docker sandbox remove $SANDBOX_NAME")
    fi
    if [[ -d "$WORKTREE_DIR" ]]; then
        # Deinit submodules first so worktree removal works
        CLEANUP_CMDS+=("git -C \"$WORKTREE_DIR\" submodule deinit --all --force")
        CLEANUP_CMDS+=("git worktree remove --force \"$WORKTREE_DIR\"")
    fi
    if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        if [[ "$MODE" == "delete-all" ]]; then
            CLEANUP_CMDS+=("git branch -D \"$BRANCH\"")
        else
            CLEANUP_CMDS+=("git branch -d \"$BRANCH\"")
        fi
    fi

    if [[ ${#CLEANUP_CMDS[@]} -eq 0 ]]; then
        echo "  (nothing to clean up)"
        exit 0
    fi

    for cmd in "${CLEANUP_CMDS[@]}"; do
        echo "  $cmd"
    done
    echo

    read -rp "Execute cleanup? [y/N] " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Cleanup skipped."
        exit 0
    fi

    echo
    for cmd in "${CLEANUP_CMDS[@]}"; do
        echo "$ $cmd"
        if ! eval "$cmd"; then
            echo "Error: command failed, stopping cleanup." >&2
            exit 1
        fi
    done

    echo
    echo "Cleanup complete."
    exit 0
fi

# =============================================================================
# --redo mode: re-run codex in an existing sandbox/worktree/branch
# =============================================================================
if [[ "$MODE" == "redo" ]]; then
    ERRORS=()
    SANDBOX_FOUND=false
    for attempt in 1 2 3 4 5; do
        echo "Checking for sandbox '$SANDBOX_NAME' (attempt $attempt)..."
        sandbox_output=$(docker sandbox list 2>&1)
        if echo "$sandbox_output" | grep -q "$SANDBOX_NAME"; then
            SANDBOX_FOUND=true
            break
        fi
        if [[ $attempt -lt 5 ]]; then
            echo "  Not found, retrying in 3s..."
            sleep 3
        fi
    done
    if [[ "$SANDBOX_FOUND" == "false" ]]; then
        echo "docker sandbox list output:" >&2
        echo "$sandbox_output" >&2
        ERRORS+=("Sandbox '$SANDBOX_NAME' does not exist (checked 5 times over 12s)")
    fi
    if [[ ! -d "$WORKTREE_DIR" ]]; then
        ERRORS+=("Worktree '$WORKTREE_DIR' does not exist")
    fi
    if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        ERRORS+=("Branch '$BRANCH' does not exist")
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo "Error: cannot redo — environment is not set up:" >&2
        for err in "${ERRORS[@]}"; do
            echo "  - $err" >&2
        done
        echo "Run without --redo first to create the environment." >&2
        exit 1
    fi

    echo "Re-injecting credentials..."
    inject_auth "$SANDBOX_NAME"

    echo "Re-injecting environment..."
    inject_env "$SANDBOX_NAME"

    echo
    echo "Starting codex (redo)..."
    echo
    PROMPT="implement the DRAFT spec $SPEC . After implementation is complete and all tests pass, run 'buildgit push jenkins' to push your changes and verify the Jenkins CI build succeeds with no test failures. If the build fails, fix the issues and push again."
    if [[ -n "$REDO_EXTRA" ]]; then
        PROMPT="$PROMPT $REDO_EXTRA"
    fi
    docker sandbox run "$SANDBOX_NAME" -- exec --model "$MODEL" -c model_reasoning_effort="medium" "$PROMPT" </dev/tty
    exit 0
fi

# =============================================================================
# --bugfix mode: fix a bug in an already-implemented spec
# =============================================================================
if [[ "$MODE" == "bugfix" ]]; then
    ERRORS=()
    SANDBOX_FOUND=false
    for attempt in 1 2 3 4 5; do
        echo "Checking for sandbox '$SANDBOX_NAME' (attempt $attempt)..."
        sandbox_output=$(docker sandbox list 2>&1)
        if echo "$sandbox_output" | grep -q "$SANDBOX_NAME"; then
            SANDBOX_FOUND=true
            break
        fi
        if [[ $attempt -lt 5 ]]; then
            echo "  Not found, retrying in 3s..."
            sleep 3
        fi
    done
    if [[ "$SANDBOX_FOUND" == "false" ]]; then
        echo "docker sandbox list output:" >&2
        echo "$sandbox_output" >&2
        ERRORS+=("Sandbox '$SANDBOX_NAME' does not exist (checked 5 times over 12s)")
    fi
    if [[ ! -d "$WORKTREE_DIR" ]]; then
        ERRORS+=("Worktree '$WORKTREE_DIR' does not exist")
    fi
    if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        ERRORS+=("Branch '$BRANCH' does not exist")
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo "Error: cannot bugfix — environment is not set up:" >&2
        for err in "${ERRORS[@]}"; do
            echo "  - $err" >&2
        done
        echo "Run without --bugfix first to create the environment." >&2
        exit 1
    fi

    echo "Re-injecting credentials..."
    inject_auth "$SANDBOX_NAME"

    echo "Re-injecting environment..."
    inject_env "$SANDBOX_NAME"

    echo
    echo "Starting codex (bugfix)..."
    echo
    PROMPT="The spec $SPEC was just implemented. There is an issue you need to fix. Fix the code for this issue. Make sure you test your fix by adding tests where necessary. After the fix is complete and all tests pass, run 'buildgit push jenkins' to push your changes and verify the Jenkins CI build succeeds with no test failures. If the build fails, fix the issues and push again. Bug: $BUGFIX_TEXT"
    docker sandbox run "$SANDBOX_NAME" -- exec --model "$MODEL" -c model_reasoning_effort="medium" "$PROMPT" </dev/tty </dev/tty
    exit 0
fi

# =============================================================================
# Commit spec and referenced files on the current branch
# =============================================================================
echo
echo "Committing spec to current branch..."

# Stage spec file
git -C "$REPO_ROOT" add "$SPEC_REL"

# Stage referenced files
for ref in "${REF_FILES[@]+"${REF_FILES[@]}"}"; do
    git -C "$REPO_ROOT" add "$ref"
done

# Only commit if there are staged changes
if ! git -C "$REPO_ROOT" diff --cached --quiet; then
    git -C "$REPO_ROOT" commit -m "add DRAFT spec: $TITLE"
    echo "Committed spec and references on current branch"
else
    echo "Spec already committed on current branch"
fi

# =============================================================================
# Create worktree (branching from the commit that includes the spec)
# =============================================================================
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
docker sandbox run "$SANDBOX_NAME" -- exec --model "$MODEL" -c model_reasoning_effort="medium" "$PROMPT" </dev/tty
