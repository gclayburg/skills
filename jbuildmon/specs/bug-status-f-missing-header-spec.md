# Bug Fix: buildgit status -f Missing Build Header for Completed Builds
Date: 2026-02-07

## Overview

`buildgit status -f` does not display the build header (job name, build number, trigger, commit, build info, etc.) when a build completes before the follow loop can catch it in progress. This is most visible with early failures (e.g. Jenkinsfile syntax errors) that complete in under a second, but can affect any fast build.

## Problem Statement

### Current Behavior

When `buildgit status -f` detects a new build that has already completed, the output jumps directly to error logs and "Finished: FAILURE" with no build context:

```
Waiting for next build of ralph1...

=== Console Output ===
Started by user buildtriggerdude
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:
...
Finished: FAILURE
======================

Finished: FAILURE

Waiting for next build of ralph1...
```

The user has no idea which build number failed, when it started, who triggered it, or what commit was built.

### Expected Behavior

Every build detected by `status -f` should show the build header, matching the output of `buildgit status` (without `-f`):

```
Waiting for next build of ralph1...

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #111
Status:     FAILURE
Trigger:    Manual (started by Gary Clayburg)
Commit:     unknown
            ✗ Unknown commit
Duration:   0s
Completed:  2026-02-07 13:15:56

=== Build Info ===
  Started by:  Gary Clayburg
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

=== Console Output ===
Started by user Gary Clayburg
...
======================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/111/console

Finished: FAILURE

Waiting for next build of ralph1...
```

### Contrast with Other Commands

| Command | Banner shown? | Why |
|---------|--------------|-----|
| `buildgit push` | Always | Calls `_display_build_in_progress_banner()` unconditionally (line 881) |
| `buildgit build` | Always | Calls `_display_build_in_progress_banner()` unconditionally (line 985) |
| `buildgit status` | Always | Uses `display_failure_output()` / `display_success_output()` which include full header |
| `buildgit status -f` | Only if caught in progress | Banner gated behind `if building == "true"` (line 542) |

## Root Cause

In `buildgit:_cmd_status_follow()` (lines 538-552):

```bash
local building
building=$(echo "$build_json" | jq -r '.building // false')

# If build is in progress, display banner and monitor until completion
if [[ "$building" == "true" ]]; then
    bg_log_info "Build #${build_number} is in progress, monitoring..."
    _display_build_in_progress_banner "$job_name" "$build_number" "(so far)"
    _monitor_build "$job_name" "$build_number"
fi

# Display build completion (test results if applicable + Finished line)
_handle_build_completion "$job_name" "$build_number" || true
```

When a build completes before the poll catches it (e.g. early Jenkinsfile failure taking < 1 second), `building` is `"false"`, the banner is skipped entirely, and `_handle_build_completion()` runs without any header context.

`_handle_build_completion()` only shows test results and "Finished: STATUS" — it was designed to run *after* a banner was already displayed by the caller.

## Technical Requirements

### Fix: Display a completion header when no in-progress banner was shown

When the follow loop finds a build that is already complete (`building == "false"`), it must display the build's full header before calling `_handle_build_completion()`.

The existing `display_failure_output()` and `display_success_output()` functions (used by `buildgit status` snapshot mode) already produce the correct header format for completed builds. These should be reused.

### Approach

Modify `_cmd_status_follow()` to add an `else` branch for completed builds:

```
if building == "true":
    # existing: show in-progress banner, monitor
    _display_build_in_progress_banner(...)
    _monitor_build(...)
else:
    # NEW: build already completed, show completion header
    # Use the same display path as `buildgit status` snapshot mode
    _display_completed_build_header(job_name, build_number)

_handle_build_completion(...)
```

The `else` branch should display:
1. The appropriate banner (BUILD FAILED / BUILD SUCCESS / etc.)
2. Build metadata (Job, Build #, Status, Trigger, Commit, Duration, Completed)
3. Build Info section (Started by, Agent, Pipeline)
4. For failures: Failed Jobs tree and Error Logs (including full console for early failures per `buildgit-early-build-failure-spec.md`)
5. Console URL

This is essentially what `display_failure_output()` / `display_success_output()` already do. The implementation may call these directly, or extract shared logic into a helper that both the snapshot `status` command and the follow loop can use.

### Important: Avoid duplicate output

`_handle_build_completion()` currently shows test results and the "Finished: STATUS" line. When a completed-build header is displayed in the `else` branch, ensure there is no duplication — e.g. don't show test results twice, don't show "Finished: FAILURE" twice. The completion header already contains failure details, so `_handle_build_completion()` may need to be aware that a header was already shown, or the `else` branch should incorporate what `_handle_build_completion()` does and skip calling it separately.

## Affected Components

| File | Function | Change |
|------|----------|--------|
| `buildgit` | `_cmd_status_follow()` | Add `else` branch to display completed build header |
| `buildgit` | `_handle_build_completion()` | May need a flag or parameter to avoid duplicate output |
| `lib/jenkins-common.sh` | `display_failure_output()` / `display_success_output()` | No changes expected — reuse as-is |

## Acceptance Criteria

1. **Fast-completing builds show header**: When `status -f` detects a build that already completed, the full header (banner, job, build #, trigger, commit, build info) is displayed
2. **In-progress builds unchanged**: Builds caught while running still show the in-progress banner followed by stage streaming, same as before
3. **No duplicate output**: Test results, error logs, and "Finished: STATUS" each appear exactly once
4. **Consistent with snapshot**: The header shown for completed builds in follow mode matches the output of `buildgit status` (without `-f`)
5. **Works for all result types**: SUCCESS, FAILURE, UNSTABLE, ABORTED all display appropriate headers

## Testing

### Manual Testing Checklist

- [ ] Introduce a Jenkinsfile syntax error, trigger a build, verify `status -f` shows the full header for the completed build
- [ ] Run a normal build, verify `status -f` catches it in progress and shows the in-progress banner as before
- [ ] Verify no output is duplicated (test results, finished line)
- [ ] Verify a successful fast build also shows the header in follow mode

## Related Specifications

- `unify-follow-log-spec.md` — Unified monitoring output format (Section 5: `buildgit status -f`)
- `buildgit-early-build-failure-spec.md` — Full console log for early failures (complementary fix)
- `bug2026-02-01-buildgit-monitoring-spec.md` — Previous fix for missing build info in follow mode
