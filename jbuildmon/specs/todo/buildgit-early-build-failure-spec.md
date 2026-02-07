# Bug Fix: Show Full Console Log for Early Build Failures
Date: 2026-02-07

## Overview

When a Jenkins build fails before any pipeline stage executes (e.g. Jenkinsfile syntax error, agent allocation failure), buildgit shows only "Finished: FAILURE" with no useful context. The full console log — which is typically short for these early failures — should be displayed so the user can see *why* it failed.

## Problem Statement

### Current Behavior

When a build fails before any stages run:

- `buildgit push`, `buildgit build`, `buildgit status -f`: The monitoring loop (`_monitor_build`) polls for stage changes but finds none. When the build completes, `_handle_build_completion()` shows test results (none) and prints "Finished: FAILURE" — no error context at all.
- `buildgit status`: The snapshot path calls `display_failure_output()` → `_display_error_logs()`, which calls `extract_error_lines()`. This only greps for lines matching `ERROR|Exception|FAILURE|failed|FATAL`, showing disconnected fragments rather than the coherent error message.

Example — `buildgit push` output for a Jenkinsfile syntax error:

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #103
Status:     BUILDING
...
Console:    http://palmer.garyclayburg.com:18080/job/ralph1/103/console



Finished: FAILURE
```

The user sees no indication of *why* the build failed.

### Expected Behavior

For early failures (no stages executed), the full console log should be shown:

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #103
Status:     BUILDING
...
Console:    http://palmer.garyclayburg.com:18080/job/ralph1/103/console

=== Console Output ===
Started by user buildtriggerdude
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:
WorkflowScript: 3: Too many arguments for map key "node" @ line 3, column 9.
           node('fastnode') {
           ^

1 error

	at org.codehaus.groovy.control.ErrorCollector.failIfErrors(ErrorCollector.java:309)
	...
[Checks API] No suitable checks publisher found.
======================

Finished: FAILURE
```

For builds that *did* execute stages, the existing behavior is unchanged (stage-specific error extraction, test results, etc.).

## Detection: "No Stages Ran"

The existing `get_all_stages()` function calls the Jenkins `wfapi/describe` API and returns a JSON array of stages. When this returns `[]` (empty array), no pipeline stages executed. This is the condition that triggers full console log display.

## Scope

This fix applies to all commands that display build failures:

| Command | Code Path | Currently Shows |
|---------|-----------|----------------|
| `buildgit push` | `_handle_build_completion()` | "Finished: FAILURE" only |
| `buildgit build` | `_handle_build_completion()` | "Finished: FAILURE" only |
| `buildgit status -f` | `_handle_build_completion()` | "Finished: FAILURE" only |
| `buildgit status` | `display_failure_output()` → `_display_error_logs()` | Grep-filtered fragments |

## Technical Requirements

### 1. Single shared function for early-failure console display

Create a function (or extend an existing one) that:
1. Calls `get_all_stages()` to check whether any stages ran
2. If stages is `[]`, fetches full console output via `get_console_output()` and displays it entirely
3. If stages is non-empty, falls through to existing error extraction logic

This function must be called from both code paths:
- `_handle_build_completion()` (monitoring commands)
- `_display_error_logs()` (snapshot `status` command)

### 2. Modify `_handle_build_completion()`

Currently this function only shows test results and "Finished: STATUS" for failed builds. For the early-failure case it must also display the console log.

Pseudocode:
```
_handle_build_completion(job_name, build_number):
    result = get build result

    if result is FAILURE or UNSTABLE:
        stages = get_all_stages(job_name, build_number)

        if stages is empty:
            console = get_console_output(job_name, build_number)
            display full console output with "=== Console Output ===" wrapper
        else:
            # existing behavior: test results if available
            show test results

    print "Finished: STATUS"
```

### 3. Modify `_display_error_logs()`

Add the same early-failure check at the top of this function:

```
_display_error_logs(job_name, build_number, console_output):
    stages = get_all_stages(job_name, build_number)

    if stages is empty:
        # Early failure - show full console
        display full console_output
        return

    # ... existing logic (downstream check, stage extraction, error grep) ...
```

### 4. Console output display format

When showing full console for early failures, use this format:

```
=== Console Output ===
<full console text>
======================
```

Use `COLOR_YELLOW` for the delimiter lines, consistent with other log sections.

## Affected Components

| File | Function | Change |
|------|----------|--------|
| `buildgit` | `_handle_build_completion()` | Add early-failure console display before "Finished" line |
| `lib/jenkins-common.sh` | `_display_error_logs()` | Add early-failure check at top, show full console |
| `lib/jenkins-common.sh` | New or extracted helper | Shared "is early failure" + "display full console" logic |

## Acceptance Criteria

1. **`buildgit push` shows console for early failure**: When a build fails before stages run, the full console log is displayed between the build header and the "Finished: FAILURE" line
2. **`buildgit build` shows console for early failure**: Same behavior as push
3. **`buildgit status -f` shows console for early failure**: Same behavior as push
4. **`buildgit status` shows console for early failure**: Full console log is shown instead of grep-filtered fragments
5. **Normal failures unchanged**: Builds that fail during/after stages continue to use existing stage-specific error extraction
6. **Shared code**: One place detects "no stages" and displays full console — not duplicated across entrypoints

## Testing

### Manual Testing Checklist

- [ ] Introduce a Jenkinsfile syntax error, push, verify `buildgit push` shows full console log
- [ ] Run `buildgit status` on the same failed build, verify full console log is shown
- [ ] Run `buildgit status -f` while the broken build runs, verify console log shown on completion
- [ ] Fix the Jenkinsfile, push a build that fails in a stage (e.g. failing test), verify existing stage-based error display still works
- [ ] Verify a successful build is unaffected

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| Early failure via push monitor | Mock a build with no stages + FAILURE result; verify console output is displayed |
| Early failure via status snapshot | Mock a completed failed build with no stages; verify full console shown |
| Normal stage failure unchanged | Mock a build with stages where one failed; verify stage extraction logic runs, not full console |
| Early failure detection | Verify `get_all_stages()` returning `[]` triggers full console display |

## Related Specifications

- `unify-follow-log-spec.md` — Unified monitoring output format (Section 4: Build Completion)
- `bug2026-01-27-jenkins-log-truncated-spec.md` — Stage log extraction and fallback behavior
- `test-failure-display-spec.md` — Test failure output format
