#!/usr/bin/env bash
#
# implement-spec.sh - Implement a DRAFT spec in an isolated worktree using codex docker sandbox
#
# Usage:
#   ./jbuildmon/implement-spec.sh [--model <model>] [--prompt <file>] <spec-file>
#   ./jbuildmon/implement-spec.sh --merge [--squash] <spec-file>
#   ./jbuildmon/implement-spec.sh --delete-all <spec-file>
#   ./jbuildmon/implement-spec.sh --redo <spec-file>
#   ./jbuildmon/implement-spec.sh --bugfix "description" <spec-file>
#   ./jbuildmon/implement-spec.sh --ralph-loop [--max-chunks <N>] [--prompt <file>] <plan-file>
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
# With --ralph-loop, implements all chunks in a '*-plan.md' file one at a time.
# The plan file (not a spec file) is passed as the argument. Codex runs once per
# chunk in the same sandbox/worktree/branch, with each run implementing one chunk,
# pushing to Jenkins, and exiting with "REMAINING_CHUNKS=n" on the last line.
# The loop stops when REMAINING_CHUNKS=0 or codex exits non-zero.
# Incompatible with --merge, --delete-all, --redo, --bugfix.
#
# Requires auth credentials at ~/.cache/codex-sandbox-auth/auth.json
# (copy from ~/.codex/auth.json after running: codex login --device-auth)
#
# Options:
#   --model <model>   Model to use (default: gpt-5.3-codex)
#   --merge           Merge the spec branch and clean up artifacts
#   --squash          With --merge, squash all branch commits into one
#   --delete-all      Delete sandbox, worktree, and branch without merging
#   --redo [text]     Re-run codex in an existing sandbox (inject fresh creds)
#                     Optional text is appended to the prompt
#   --bugfix <text>   Fix a bug in an already-implemented spec
#                     Text can be inline or piped from stdin
#   --ralph-loop      Implement all chunks in a plan file, one per codex run
#   --max-chunks <N>  Max chunk iterations for --ralph-loop (default: 20)
#   --branch <name>   Override the branch (and worktree/sandbox) name
#                     Useful for re-implementing with a fresh setup
#   --prompt <file>   Use a custom prompt file (replaces hardcoded prompt)
#                     %SPEC% in the file is replaced with the spec/plan path
#                     Without --prompt, looks for a companion .prompt file
#                     next to the spec/plan (e.g. myfeature-plan.prompt)
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
#   ./jbuildmon/implement-spec.sh --ralph-loop jbuildmon/specs/todo/build-optimization-apis-plan.md
#   ./jbuildmon/implement-spec.sh --ralph-loop --max-chunks 10 jbuildmon/specs/todo/myfeature-plan.md
#   ./jbuildmon/implement-spec.sh --branch my-retry-v2 --ralph-loop jbuildmon/specs/myfeature-plan.md

set -euo pipefail

MODE="run"
# MODEL="gpt-5.3-codex"
MODEL="gpt-5.4"
SPEC=""
REDO_EXTRA=""
BUGFIX_TEXT=""
SQUASH=false
RALPH_LOOP=false
MAX_CHUNKS=20
PROMPT_FILE=""
BRANCH_OVERRIDE=""
AUTH_CACHE_DIR="${HOME}/.cache/codex-sandbox-auth"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# auth file created like this from an already authenticated docker sandbox:
# docker sandbox exec codex-phandlemono cat /home/agent/.codex/auth.json > ~/.cache/codex-sandbox-auth/auth.json

# shellcheck source=sandbox-common.sh
source "$SCRIPT_DIR/sandbox-common.sh"

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
        --squash)
            SQUASH=true
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
        --ralph-loop)
            if [[ "$MODE" != "run" ]]; then
                echo "Error: --ralph-loop cannot be combined with --${MODE}" >&2
                exit 1
            fi
            RALPH_LOOP=true
            shift
            ;;
        --max-chunks)
            MAX_CHUNKS="$2"
            shift 2
            ;;
        --branch)
            BRANCH_OVERRIDE="$2"
            shift 2
            ;;
        --prompt)
            PROMPT_FILE="$2"
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

# --squash only valid with --merge
if [[ "$SQUASH" == "true" && "$MODE" != "merge" ]]; then
    echo "Error: --squash can only be used with --merge" >&2
    exit 1
fi

if [[ -z "$SPEC" ]]; then
    echo "Usage: $0 [--model <model>] <spec-file>" >&2
    exit 1
fi

if [[ ! -f "$SPEC" ]]; then
    echo "Error: spec file not found: $SPEC" >&2
    exit 1
fi

# --ralph-loop requires a *-plan.md file
if [[ "$RALPH_LOOP" == "true" && ! "$SPEC" =~ -plan\.md$ ]]; then
    echo "Error: --ralph-loop requires a '*-plan.md' file, got: $(basename "$SPEC")" >&2
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

run_codex() {
    # run_codex <sandbox> <model> <prompt> [output_file]
    # Runs codex, optionally tee-ing to a file.
    local sandbox="$1" model="$2" prompt="$3" outfile="${4:-}"
    if [[ -n "$outfile" ]]; then
        docker sandbox run "$sandbox" -- exec --model "$model" -c model_reasoning_effort="medium" "$prompt" </dev/tty \
            | tee "$outfile"
        return "${PIPESTATUS[0]}"
    else
        docker sandbox run "$sandbox" -- exec --model "$model" -c model_reasoning_effort="medium" "$prompt" </dev/tty
    fi
}

resolve_prompt() {
    # resolve_prompt <default-prompt-text>
    # If --prompt was given, use that file.
    # Else if a companion .prompt file exists next to the spec/plan, use it.
    # Else use the default text.
    # In all cases, replace %SPEC% with $SPEC_REL.
    local default_text="$1"
    local raw_prompt=""

    if [[ -n "$PROMPT_FILE" ]]; then
        if [[ ! -f "$PROMPT_FILE" ]]; then
            echo "Error: prompt file not found: $PROMPT_FILE" >&2
            exit 1
        fi
        raw_prompt=$(<"$PROMPT_FILE")
        echo "Using prompt file: $PROMPT_FILE" >&2
    else
        # Look for companion .prompt file (e.g. myfeature-plan.prompt)
        local companion="${SPEC_ABS%.md}.prompt"
        if [[ -f "$companion" ]]; then
            raw_prompt=$(<"$companion")
            echo "Using prompt file: $companion" >&2
        fi
    fi

    if [[ -z "$raw_prompt" ]]; then
        raw_prompt="$default_text"
    fi

    # Substitute placeholders
    printf '%s' "${raw_prompt//'%SPEC%'/$SPEC_REL}"
}

# =============================================================================
# Worktree setup
# =============================================================================

# Derive title and branch name.
# Plan files (*-plan.md) always use the filename so that --ralph-loop, --merge,
# --delete-all, and --redo all resolve to the same branch regardless of which
# flags are present.
if [[ "$SPEC" =~ -plan\.md$ ]]; then
    # For plan files, derive branch from filename (strip -plan.md suffix)
    TITLE=$(basename "$SPEC" -plan.md)
    BRANCH=$(echo "$TITLE" | cut -c1-30)
else
    # Extract title from spec (first ## heading)
    TITLE=$(grep -m1 '^## ' "$SPEC" | sed 's/^## //')
    if [[ -z "$TITLE" ]]; then
        echo "Error: could not find ## title in $SPEC" >&2
        exit 1
    fi
    # Slugify title for branch name (keep short to avoid Docker socket path length limit)
    BRANCH=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-30)
fi

# Apply --branch override if provided
if [[ -n "$BRANCH_OVERRIDE" ]]; then
    BRANCH="$BRANCH_OVERRIDE"
fi

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
if [[ -n "$PROMPT_FILE" ]]; then
    echo "Prompt:    $PROMPT_FILE"
fi
if [[ -n "$BUGFIX_TEXT" ]]; then
    echo "Bugfix:    $BUGFIX_TEXT"
fi
if [[ "$RALPH_LOOP" == "true" ]]; then
    echo "MaxChunks: $MAX_CHUNKS"
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

        if [[ "$SQUASH" == "true" ]]; then
            COMMIT_COUNT=$(git rev-list --count HEAD.."$BRANCH")
            echo "Squash-merging branch '$BRANCH' ($COMMIT_COUNT commits) into $(git rev-parse --abbrev-ref HEAD)..."
            if ! git merge --squash "$BRANCH"; then
                echo "Error: squash merge failed. Resolve conflicts and try again." >&2
                exit 1
            fi
            git commit -m "implement: $TITLE (squashed $COMMIT_COUNT commits)"
            echo "Squash merge successful."
        else
            echo "Merging branch '$BRANCH' into $(git rev-parse --abbrev-ref HEAD)..."
            if ! git merge "$BRANCH"; then
                echo "Error: merge failed. Resolve conflicts and try again." >&2
                exit 1
            fi
            echo "Merge successful."
        fi
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
        if [[ "$MODE" == "delete-all" || "$SQUASH" == "true" ]]; then
            CLEANUP_CMDS+=("git branch -D \"$BRANCH\"")
        else
            CLEANUP_CMDS+=("git branch -d \"$BRANCH\"")
        fi
    fi
    # Delete remote branch if it exists
    remote_ref=$(git ls-remote --heads origin "$BRANCH" 2>/dev/null || true)
    if [[ -n "$remote_ref" ]]; then
        CLEANUP_CMDS+=("git push origin --delete \"$BRANCH\"")
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
    inject_claude_auth "$SANDBOX_NAME"

    echo "Re-injecting environment..."
    inject_env "$SANDBOX_NAME"

    echo
    echo "Starting codex (redo)..."
    echo
    DEFAULT_REDO_PROMPT="implement the DRAFT spec %SPEC% . After implementation is complete and all tests pass, run 'buildgit push jenkins' to push your changes and verify the Jenkins CI build succeeds with no test failures. If the build fails, fix the issues and push again."
    PROMPT=$(resolve_prompt "$DEFAULT_REDO_PROMPT")
    if [[ -n "$REDO_EXTRA" ]]; then
        PROMPT="$PROMPT $REDO_EXTRA"
    fi
    run_codex "$SANDBOX_NAME" "$MODEL" "$PROMPT"
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
    inject_claude_auth "$SANDBOX_NAME"

    echo "Re-injecting environment..."
    inject_env "$SANDBOX_NAME"

    echo
    echo "Starting codex (bugfix)..."
    echo
    DEFAULT_BUGFIX_PROMPT="The spec %SPEC% was just implemented. There is an issue you need to fix. Fix the code for this issue. Make sure you test your fix by adding tests where necessary. After the fix is complete and all tests pass, run 'buildgit push jenkins' to push your changes and verify the Jenkins CI build succeeds with no test failures. If the build fails, fix the issues and push again."
    PROMPT=$(resolve_prompt "$DEFAULT_BUGFIX_PROMPT")
    PROMPT="$PROMPT Bug: $BUGFIX_TEXT"
    run_codex "$SANDBOX_NAME" "$MODEL" "$PROMPT"
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
# Mount the parent repo's .git dir so worktree git metadata resolves correctly
GIT_DIR="$REPO_ROOT/.git"
if docker sandbox list 2>&1 | grep -q "$SANDBOX_NAME"; then
    echo "Reusing existing sandbox '$SANDBOX_NAME'"
else
    echo "Creating sandbox..."
    docker sandbox create --name "$SANDBOX_NAME" codex "$WORKTREE_DIR" "$GIT_DIR"
    echo "Configuring network..."
    configure_network "$SANDBOX_NAME"
fi

echo "Injecting credentials..."
inject_auth "$SANDBOX_NAME"
inject_claude_auth "$SANDBOX_NAME"

echo "Injecting environment..."
inject_env "$SANDBOX_NAME"

echo
if [[ "$RALPH_LOOP" == "true" ]]; then
    # =============================================================================
    # --ralph-loop mode: implement one chunk per codex run until all are done
    # =============================================================================
    TEMP_OUTPUT=$(mktemp)
    trap 'rm -f "$TEMP_OUTPUT"' EXIT

    PROGRESS_DIR="$REPO_ROOT/.claude/ralph-loop"
    mkdir -p "$PROGRESS_DIR"
    PROGRESS_FILE="$PROGRESS_DIR/${BRANCH}.log"

    _progress() {
        local msg="$1"
        local ts
        ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
        echo "${ts} [${BRANCH}] ${msg}" | tee -a "$PROGRESS_FILE"
    }

    echo "Starting ralph-loop (max $MAX_CHUNKS chunks)..."
    echo "Progress log: $PROGRESS_FILE"
    _progress "ralph-loop started — plan: $SPEC_REL  model: $MODEL  max-chunks: $MAX_CHUNKS"

    COMPLETED=false
    for ((iteration=1; iteration<=MAX_CHUNKS; iteration++)); do
        echo
        echo "=== Ralph-loop: chunk $iteration / $MAX_CHUNKS ==="
        echo
        _progress "chunk $iteration/$MAX_CHUNKS starting"

        DEFAULT_RALPH_PROMPT="Study the implementation plan at %SPEC%. Read the '## SPEC Workflow' section in the plan and follow the 'Per-Chunk Workflow' steps exactly.

Pick ONE uncompleted chunk to implement — the highest-priority chunk whose dependencies are all already completed. Implement ONLY that single chunk. Do NOT implement any other chunks.

Follow these steps for the chunk:
1. Run all unit tests FIRST: jbuildmon/test/bats/bin/bats jbuildmon/test/ (do NOT use any bats from \$PATH). Do not proceed if tests are failing.
2. Implement the chunk as described in its Implementation Details.
3. Write or update unit tests as described in the chunk's Test Plan.
4. Run all unit tests again and confirm they pass (both new and existing).
5. Fill in the '#### Implementation Log' section for this chunk in %SPEC% — summarize files changed, key decisions, and anything notable for the finalize step.
6. Count the total chunks (T) and determine this chunk's number (N) based on its position in the Contents list.
7. Commit and push using 'buildgit push jenkins' with a commit message starting with 'chunk N/T: ' followed by a brief description.
8. Verify the Jenkins CI build succeeds with no test failures. If it fails, fix and push again.

When done:
1. Mark ONLY the one chunk you implemented as completed in %SPEC% (change '- [ ]' to '- [x]').
2. Report how many (n) non-completed chunks remain and give a brief one-line summary of each remaining chunk.
3. The final line of your output MUST be exactly: REMAINING_CHUNKS=n

STOP after completing the single chunk. Do not continue to the next chunk."
        PROMPT=$(resolve_prompt "$DEFAULT_RALPH_PROMPT")

        run_codex "$SANDBOX_NAME" "$MODEL" "$PROMPT" "$TEMP_OUTPUT"
        exit_code=${PIPESTATUS[0]}

        if [[ $exit_code -ne 0 ]]; then
            _progress "chunk $iteration/$MAX_CHUNKS FAILED — codex exit code $exit_code"
            echo >&2
            echo "Error: codex exited with code $exit_code on chunk $iteration. Stopping." >&2
            exit $exit_code
        fi

        remaining=$(grep -o 'REMAINING_CHUNKS=[0-9]*' "$TEMP_OUTPUT" | tail -1 | cut -d= -f2)

        if [[ -z "$remaining" ]]; then
            _progress "chunk $iteration/$MAX_CHUNKS FAILED — REMAINING_CHUNKS sentinel not found in output"
            echo >&2
            echo "Warning: REMAINING_CHUNKS sentinel not found in output on chunk $iteration. Stopping." >&2
            exit 1
        fi

        _progress "chunk $iteration/$MAX_CHUNKS complete — $remaining chunks remaining"
        echo
        echo "Chunk $iteration complete. $remaining chunks remaining."

        if [[ "$remaining" == "0" ]]; then
            COMPLETED=true
            _progress "ralph-loop finished successfully after $iteration chunks"
            echo
            echo "All chunks complete! Starting finalize step..."
            break
        fi
    done

    if [[ "$COMPLETED" != "true" ]]; then
        _progress "ralph-loop stopped — reached max chunks limit ($MAX_CHUNKS)"
        echo >&2
        echo "Error: reached max chunks limit ($MAX_CHUNKS) without completing all chunks." >&2
        exit 1
    fi

    # =============================================================================
    # Finalize step: update docs, metadata, spec state after all chunks are done
    # =============================================================================
    echo
    echo "=== Ralph-loop: finalize step ==="
    echo
    _progress "finalize step starting"

    DEFAULT_FINALIZE_PROMPT="All chunks in the implementation plan at %SPEC% have been completed. Read the entire plan file, including all '#### Implementation Log' entries filled in by each chunk.

Now perform the Finalize Workflow from the plan's '## SPEC Workflow' section. Specifically:

1. Update CHANGELOG.md (at the repository root) with all changes from this plan.
2. Update README.md (at the repository root) if CLI options or usage changed.
3. Update jbuildmon/skill/buildgit/SKILL.md if the changes affect the buildgit skill.
4. Update jbuildmon/skill/buildgit/references/reference.md if output format or available options changed.
5. Update the spec file: change its State: field to IMPLEMENTED and add it to the spec index in specs/README.md.
6. Handle referenced files: if the spec lists files in its References: header, move those files to specs/done-reports/ and update the reference paths in the spec.
7. Update CLAUDE.md AND README.md (at the repository root) if the output of 'buildgit --help' changes in any way.
8. Commit and push using 'buildgit push jenkins' and verify CI passes.

Use the Implementation Log entries from each chunk to write accurate, complete documentation updates."
    FINALIZE_PROMPT=$(resolve_prompt "$DEFAULT_FINALIZE_PROMPT")

    run_codex "$SANDBOX_NAME" "$MODEL" "$FINALIZE_PROMPT" "$TEMP_OUTPUT"
    finalize_exit=${PIPESTATUS[0]}

    if [[ $finalize_exit -ne 0 ]]; then
        _progress "finalize step FAILED — codex exit code $finalize_exit"
        echo >&2
        echo "Error: finalize step exited with code $finalize_exit." >&2
        exit $finalize_exit
    fi

    _progress "finalize step complete — ralph-loop fully done"
    echo
    echo "Finalize step complete. Ralph-loop fully done."
else
    # =============================================================================
    # Normal run mode: implement the full spec in a single codex run
    # =============================================================================
    echo "Starting codex..."
    echo
    DEFAULT_RUN_PROMPT="implement the DRAFT spec %SPEC% . After implementation is complete and all tests pass, run 'buildgit push jenkins' to push your changes and verify the Jenkins CI build succeeds with no test failures. If the build fails, fix the issues and push again."
    PROMPT=$(resolve_prompt "$DEFAULT_RUN_PROMPT")
    #PROMPT="add a blank line to a file named nonsensebuidltrigger.md, commit it, and then push it using 'buildgit push jenkins'.  After the build is complete, verify the build was successful and the test results are displayed."
    run_codex "$SANDBOX_NAME" "$MODEL" "$PROMPT"
fi
