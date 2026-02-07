# Bats Background Processes Hanging on Linux CI

## Problem

The `buildgit_status_follow.bats` tests ran fine on macOS but hung indefinitely on the Linux CI server (Docker container), causing the Jenkins pipeline to hit its 15-minute timeout. The tests never produced any output for the follow mode test file - bats blocked before even reporting the first test result.

## Root Cause

Two issues combined to cause the hang:

### 1. Bats fd 3 inheritance (the actual cause of the hang)

Bats-core uses **file descriptor 3** internally for test output capture. When a test launches a background process:

```bash
bash wrapper.sh > output.txt 2>&1 &
```

The background process inherits fd 3 from bats, even though stdout and stderr are redirected to a file. When the test later kills the background process, **orphaned grandchild processes** (spawned by command substitution subshells inside the wrapper) survive and keep fd 3 open. Bats blocks waiting for fd 3's pipe to close, which never happens because those orphaned processes are still alive.

On macOS this didn't manifest because `pkill` successfully killed all child processes before they could orphan. On Linux in Docker, the process cleanup was less reliable (see issue 2), so orphans survived and held fd 3.

### 2. SIGTERM deferred during command substitution (secondary issue)

The wrapper scripts enter an infinite polling loop inside a command substitution:

```bash
new_build_number=$(_follow_wait_for_new_build "$job_name" "$build_number")
```

On Linux, **SIGTERM is deferred during bash command substitution**. The signal is queued but not delivered until the subshell exits. Since the subshell runs an infinite loop, it never exits, and the parent never processes the signal. This made both the self-destruct timer (`kill $$`) and the test cleanup (`_kill_process_tree`) ineffective at stopping the wrapper.

## What Did NOT Work

### Attempt 1: SIGKILL in kill and self-destruct (build #100 - FAILED)

Changed `_kill_process_tree` and self-destruct timers to use `kill -9` (SIGKILL) instead of default SIGTERM:

```bash
# _kill_process_tree
pkill -9 -P "$pid" 2>/dev/null || true
kill -9 "$pid" 2>/dev/null || true

# Self-destruct in wrapper
( sleep 8 && kill -9 $$ 2>/dev/null ) &
```

**Why it failed:** SIGKILL correctly kills the wrapper and its direct children. However, the grandchild processes (e.g., `sleep 1` inside the command substitution subshell) become orphans reparented to PID 1. These orphans still hold bats' fd 3 open. Bats continued to hang waiting for fd 3.

The SIGKILL fix was necessary but not sufficient on its own.

### Attempt 2: Close fd 3 + SIGKILL (build #101 - SUCCESS)

Added `3>&-` when launching background wrappers, combined with the SIGKILL fix:

```bash
bash wrapper.sh > output.txt 2>&1 3>&- &
```

**Why it worked:** Closing fd 3 at the point where the background process is created means the wrapper and ALL of its descendants (children, grandchildren, etc.) never have fd 3. Even if orphaned grandchildren survive process cleanup, they can't hold fd 3 open because they never had it. Bats can detect test completion immediately.

## The Fix (two parts)

### Part 1: Close bats internal fds on background process launch

```bash
# BEFORE (hangs on Linux):
bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 &

# AFTER (works everywhere):
bash "${TEST_TEMP_DIR}/buildgit_wrapper.sh" > "${TEST_TEMP_DIR}/output.txt" 2>&1 3>&- &
```

This is the critical fix. Without `3>&-`, any orphaned descendant process keeps bats' output pipe open.

### Part 2: Use SIGKILL for process cleanup

```bash
_kill_process_tree() {
    local pid="$1"
    pkill -9 -P "$pid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}
```

SIGKILL cannot be trapped or deferred, so it works even when processes are stuck in command substitution. This is a defense-in-depth measure.

## Key Takeaways

1. **Always use `3>&-` when launching background processes in bats tests.** This is the single most important rule. Without it, any orphaned descendant can hang bats indefinitely.

2. **SIGTERM is unreliable for killing processes in command substitution on Linux.** Use SIGKILL (`kill -9`) when you need guaranteed termination in test cleanup.

3. **macOS and Linux handle process signals differently.** Tests that pass locally on macOS can hang on Linux CI. Always consider cross-platform signal handling behavior.

4. **`pkill -P` only kills direct children.** Grandchildren are not affected. If direct children are killed, grandchildren become orphans reparented to PID 1. They continue running until they exit naturally.

5. **Self-destruct timers are a safety net, not a solution.** The `( sleep 8 && kill -9 $$ ) &` pattern helps prevent total hangs, but the real fix is preventing fd leaks in the first place.

## Process Tree Visualization

```
bats test subprocess (owns fd 3 pipe)
  |
  +-- bash wrapper.sh (FOLLOW_PID) [stdout/stderr -> file, fd 3 inherited!]
        |
        +-- ( sleep 8 && kill -9 $$ ) &    [self-destruct timer, has fd 3]
        |     +-- sleep 8                   [has fd 3]
        |
        +-- $(_follow_wait_for_new_build)   [command substitution subshell, has fd 3]
              +-- sleep 1                   [has fd 3, infinite loop]

After _kill_process_tree kills wrapper + direct children:
- sleep 1 (and possibly sleep 8) survive as orphans
- They still hold fd 3 open
- bats hangs waiting for fd 3 pipe to close

With 3>&- on the wrapper launch:
- No descendant ever has fd 3
- Orphans don't affect bats
- bats completes immediately after test function returns
```

## Related Files

- `test/buildgit_status_follow.bats` - The fixed test file
- `buildgit` lines 494-509 - `_follow_wait_for_new_build()` infinite polling loop
- `buildgit` lines 514-572 - `_cmd_status_follow()` main follow mode logic
