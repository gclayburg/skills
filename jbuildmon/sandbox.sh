#!/usr/bin/env bash
#
# sandbox.sh - Create or reuse a docker sandbox for claude or codex
#
# Usage:
#   ./jbuildmon/sandbox.sh [--agent <claude|codex>] [--name <name>] [--template <image>] [<directory>]
#
# Creates a docker sandbox for the given directory (default: current directory),
# injects credentials and environment variables, then starts the agent.
# If a sandbox for the same name already exists, reuses it.
#
# Options:
#   --agent <claude|codex>   Agent to run (default: claude)
#   --name <name>            Override sandbox name (default: <agent>-<dirname>)
#   --template <image>       Container image to use (default: registry:5000/docker-sandbox-buildgit:latest)
#   <directory>              Workspace directory to mount (default: current directory)
#
# Examples:
#   ./jbuildmon/sandbox.sh
#   ./jbuildmon/sandbox.sh /path/to/project
#   ./jbuildmon/sandbox.sh --agent codex /path/to/project
#   ./jbuildmon/sandbox.sh --name my-sandbox --agent claude /path/to/project

set -euo pipefail

AGENT="claude"
DEFAULT_TEMPLATE="registry:5000/docker-sandbox-buildgit:latest"
TEMPLATE="$DEFAULT_TEMPLATE"
NAME_OVERRIDE=""
DIR=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sandbox-common.sh
source "$SCRIPT_DIR/sandbox-common.sh"

AUTH_CACHE_DIR="${HOME}/.cache/codex-sandbox-auth"
AUTH_FILE="$AUTH_CACHE_DIR/auth.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)
            AGENT="$2"
            if [[ "$AGENT" != "claude" && "$AGENT" != "codex" ]]; then
                echo "Error: --agent must be 'claude' or 'codex', got: $AGENT" >&2
                exit 1
            fi
            shift 2
            ;;
        --name)
            NAME_OVERRIDE="$2"
            shift 2
            ;;
        --template)
            TEMPLATE="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,/^$/s/^# //p' "$0"
            exit 0
            ;;
        -*)
            echo "Error: unknown option '$1'" >&2
            exit 1
            ;;
        *)
            if [[ -z "$DIR" ]]; then
                DIR="$1"
            else
                echo "Error: unexpected argument '$1'" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Default directory to current working directory
if [[ -z "$DIR" ]]; then
    DIR="$PWD"
fi

# Resolve to absolute path
DIR="$(cd "$DIR" && pwd)"

if [[ ! -d "$DIR" ]]; then
    echo "Error: directory not found: $DIR" >&2
    exit 1
fi

# Derive sandbox name: <agent>-<basename(dir)>, matching docker's own default
DIRNAME=$(basename "$DIR")
SANDBOX_NAME="${AGENT}-${DIRNAME}"
if [[ -n "$NAME_OVERRIDE" ]]; then
    SANDBOX_NAME="$NAME_OVERRIDE"
fi

# If the workspace is a git worktree, also mount the main .git directory
# so that git commands inside the sandbox resolve worktree metadata correctly
GIT_DIR=""
if git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_common_dir=$(git -C "$DIR" rev-parse --git-common-dir 2>/dev/null || true)
    if [[ "$git_common_dir" == /* && -d "$git_common_dir" ]]; then
        GIT_DIR="$git_common_dir"
    fi
fi

echo
echo "Agent:     $AGENT"
echo "Directory: $DIR"
echo "Sandbox:   $SANDBOX_NAME"
echo "Template:  $TEMPLATE"
if [[ -n "$GIT_DIR" ]]; then
    echo "Git dir:   $GIT_DIR (worktree)"
fi
echo

# Check credentials for codex agent
if [[ "$AGENT" == "codex" ]]; then
    if [[ ! -f "$AUTH_FILE" ]]; then
        echo "Error: codex credentials not found at $AUTH_FILE" >&2
        echo "Create it by copying from ~/.codex/auth.json after running:" >&2
        echo "  codex login --device-auth" >&2
        exit 1
    fi
fi

# Create sandbox if it doesn't exist; treat "already exists" as success
echo "Creating sandbox..."
create_exit=0
if [[ -n "$GIT_DIR" ]]; then
    create_output=$(docker sandbox create --name "$SANDBOX_NAME" --template "$TEMPLATE" "$AGENT" "$DIR" "$GIT_DIR" 2>&1) || create_exit=$?
else
    create_output=$(docker sandbox create --name "$SANDBOX_NAME" --template "$TEMPLATE" "$AGENT" "$DIR" 2>&1) || create_exit=$?
fi
if [[ $create_exit -eq 0 ]]; then
    echo "Configuring network..."
    configure_network "$SANDBOX_NAME"
elif echo "$create_output" | grep -q "already exists"; then
    echo "Reusing existing sandbox '$SANDBOX_NAME'"
else
    echo "$create_output" >&2
    exit $create_exit
fi

echo "Injecting credentials..."
inject_claude_auth "$SANDBOX_NAME"
if [[ "$AGENT" == "codex" ]]; then
    inject_auth "$SANDBOX_NAME"
fi

echo "Injecting environment..."
inject_env "$SANDBOX_NAME"

echo
echo "Starting $AGENT in sandbox '$SANDBOX_NAME'..."
echo
docker sandbox run "$SANDBOX_NAME"
