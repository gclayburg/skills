# buildgit Monitoring Fixes and Enhancements
Date: 2026-02-01

## Overview

This spec addresses three related issues with `buildgit` build monitoring functionality:

1. `buildgit status -f` does not display build information when following an in-progress build
2. `buildgit --verbose push` causes garbled output and API failures
3. `buildgit push` and `buildgit status -f` do not show real-time progress during builds

## Issue 1: Missing Build Information in Follow Mode

### Current Behavior

When running `buildgit status -f` and a build is already in progress, the command:
1. Shows git status
2. Shows Jenkins connectivity messages
3. Immediately enters silent monitoring (no build details displayed)

### Expected Behavior

When `buildgit status -f` detects an in-progress build, it should display the build information banner before entering the monitoring loop:

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #53
Status:     BUILDING
Stage:      Unit Tests
Trigger:    Automated (git push)
Commit:     6157e1a - "test build without verbose flag5"
            ✓ Your commit (HEAD)
Started:    2026-02-01 10:11:24
```

**Note**: The `Elapsed` field is intentionally omitted from this initial banner because real-time tracking begins immediately afterward.

### Implementation Details

The `_cmd_status_follow()` function in `buildgit` must call a display function to show current build details before entering the `_follow_monitor_build()` loop.

## Issue 2: Verbose Mode Causes Output Corruption

### Current Behavior

When using `--verbose` with `buildgit push`, the output becomes garbled:
```
[10:21:39] ℹ Monitoring build #[10:21:34] ℹ Waiting for Jenkins build to start...
[10:21:34] ℹ Job is queued, waiting for executor...
[10:21:39] ✓ Build #55 started
55...
[10:21:39] ⚠ API request failed, retrying... (1/5)
```

This leads to cascading API failures and script termination.

### Root Cause

Functions like `_push_wait_for_build_start()` return values via stdout using `echo`. The `bg_log_info()` and `bg_log_success()` wrappers call `log_info()` and `log_success()` from `jenkins-common.sh`, which also write to stdout.

When these functions are called within command substitution (e.g., `build_number=$(_push_wait_for_build_start ...)`), the log messages are captured along with the return value, corrupting it.

**Example of the problem:**
```bash
# In _push_wait_for_build_start:
bg_log_info "Waiting for Jenkins build to start..."  # writes to stdout
bg_log_success "Build #${current} started"           # writes to stdout
echo "$current"                                       # return value to stdout

# All three lines get captured by command substitution, corrupting $build_number
```

### Expected Behavior

Verbose logging should not interfere with function return values. All log messages from `bg_log_info()` and `bg_log_success()` must go to stderr.

### Implementation Details

Modify the `bg_log_*` wrapper functions in `buildgit` to redirect output to stderr:

```bash
bg_log_info() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_info "$@" >&2
    fi
}

bg_log_success() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_success "$@" >&2
    fi
}
```

**Scope**: Only modify `buildgit`'s wrapper functions. Do not change `jenkins-common.sh` to avoid impacting `checkbuild.sh` and `pushmon.sh`.

This approach follows the pattern already used in `scripts/jenkins-build-monitor.sh` where log messages in value-returning functions are explicitly redirected to stderr.

## Issue 3: No Real-Time Progress Display

### Current Behavior

When `buildgit push` or `buildgit status -f` monitors a build, no progress is shown to the user. The script waits silently until the entire build completes, then displays the final result.

Stage changes and elapsed time updates are only visible when `--verbose` is used, but verbose mode is currently broken (Issue 2).

### Expected Behavior

During build monitoring, the following should be displayed to the user regardless of verbose mode:

1. **Stage completions**: A line printed each time a pipeline stage completes successfully
2. **Elapsed time updates**: Periodic updates every 30 seconds showing build progress

Example output during monitoring:
```
[10:13:30] ✓ Stage completed: Checkout
[10:13:45] ✓ Stage completed: Build
[10:14:00] ℹ Build in progress... (30s elapsed)
[10:14:15] ✓ Stage completed: Unit Tests
[10:14:30] ℹ Build in progress... (60s elapsed)
[10:14:40] ✓ Stage completed: Integration Tests
```

### Implementation Details

The monitoring functions (`_follow_monitor_build`, `_push_monitor_build`, `_build_monitor`) currently use `bg_log_info()` for stage and elapsed time updates, which are suppressed in non-verbose mode.

These updates should use `bg_log_essential()` or a new logging function that always outputs regardless of verbose setting.

**Changes required:**

1. Track completed stages (not just current stage) to detect stage transitions
2. Output stage completion messages using essential logging
3. Output elapsed time updates every 30 seconds using essential logging

## Behavior Specifications

### `buildgit push` Follow Behavior

After pushing and triggering a build:
- Monitor the build until completion
- Display real-time progress (stage completions, elapsed time)
- Display final build result
- Exit (do not wait for subsequent builds)

### `buildgit status -f` Follow Behavior

When following builds:
- Display git status once at startup
- If a build is in progress, display build info banner then monitor until completion
- Display final build result when build completes
- Display "Waiting for next build of <job>..." message
- Wait indefinitely for subsequent builds
- Exit only when user presses Ctrl+C

### Verbose Mode Behavior

When `--verbose` is enabled:
- Show all internal operations including redundant ones (e.g., multiple "Verifying Jenkins connectivity..." messages are acceptable)
- All verbose messages go to stderr to avoid corrupting command substitution
- Real-time progress (stages, elapsed time) is shown regardless of verbose mode

## Files to Modify

| File | Changes |
|------|---------|
| `buildgit` | Fix `bg_log_info()` and `bg_log_success()` to write to stderr |
| `buildgit` | Update `_cmd_status_follow()` to display build info before monitoring |
| `buildgit` | Update `_follow_monitor_build()` to show stage completions as essential output |
| `buildgit` | Update `_push_monitor_build()` to show stage completions as essential output |
| `buildgit` | Update `_build_monitor()` to show stage completions as essential output |

## References

- `specs/buildgit-spec.md` - Original buildgit specification
- `specs/jenkins-build-monitor-spec.md` - pushmon.sh specification (real-time monitoring behavior)
- `specs/followfull.md` - Raw bug report with example output
