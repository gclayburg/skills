# Bug Fix: NOT_BUILT and Non-SUCCESS Results Missing Error Display in Monitoring Mode
Date: 2026-02-12T18:15:00-07:00
References: specs/todo/bug-phandlemono-no-logs.shown.md
Supersedes: none

## Overview

When a Jenkins build completes with result `NOT_BUILT` (or any non-SUCCESS result not explicitly handled), `buildgit push`, `buildgit build`, and `buildgit status -f` show no error diagnostic output — the user sees only "Finished: NOT_BUILT" with no color and no explanation of why the build failed. In contrast, `buildgit status` (snapshot mode) correctly shows error logs, failed jobs tree, and test results for the same build.

Additionally, monitoring mode (`push`/`build`/`status -f`) never shows error logs by default for *any* failure type — even FAILURE and UNSTABLE without test results produce no error context unless `--console` is specified. This makes monitoring mode inconsistent with snapshot mode, which shows error logs by default when no test failures explain the result.

## Problem Statement

### Observed Behavior (`buildgit push`)

```
[17:40:17] ℹ   Stage: Declarative: Checkout SCM (<1s)
[17:40:22] ℹ   Stage: Checkout (<1s)
[17:40:22] ℹ   Stage: Analyze Component Changes (<1s)
[17:40:22] ℹ   Stage: Trigger Component Builds (<1s)
[17:40:22] ℹ   Stage: Build SignalBoot (unknown)
[17:40:38] ℹ   Stage: Build Handle (14s)    ← FAILED


Finished: NOT_BUILT
```

The user can see that "Build Handle" failed but has no information about *why*. The "Finished: NOT_BUILT" line has no color.

### Expected Behavior (`buildgit push`)

```
[17:40:17] ℹ   Stage: Declarative: Checkout SCM (<1s)
[17:40:22] ℹ   Stage: Checkout (<1s)
[17:40:22] ℹ   Stage: Analyze Component Changes (<1s)
[17:40:22] ℹ   Stage: Trigger Component Builds (<1s)
[17:40:22] ℹ   Stage: Build SignalBoot (unknown)
[17:40:38] ℹ   Stage: Build Handle (14s)    ← FAILED

=== Error Logs ===
Build failed. Please check the logs for more information.
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: ...
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking...Bind for 0.0.0.0:9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Finished: NOT_BUILT
```

Error logs are shown (extracted from the downstream job), and the status line is colored red.

### Current Snapshot Mode Behavior (Correct)

`buildgit status` already shows the correct output for this same build — including error logs with downstream extraction. This is the reference behavior that monitoring mode should match for error log display.

## Root Cause

Five code locations explicitly list failure statuses (FAILURE, UNSTABLE, and sometimes ABORTED) rather than using a non-SUCCESS check. `NOT_BUILT` is not included in any of these conditions.

Additionally, `_handle_build_completion()` (monitoring mode) does not display error logs by default — it only shows them when `--console` is specified. This is inconsistent with `display_failure_output()` (snapshot mode), which shows error logs by default when no test failures are present.

## Affected Code Locations

| # | Function | File | Line | Current Condition | Issue |
|---|----------|------|------|-------------------|-------|
| 1 | `_handle_build_completion()` | `buildgit` | 760 | `UNSTABLE \|\| FAILURE` | NOT_BUILT gets no error display |
| 2 | `print_finished_line()` | `lib/jenkins-common.sh` | 211 | case: SUCCESS/FAILURE/UNSTABLE/ABORTED | NOT_BUILT has no color |
| 3 | `check_build_failed()` | `lib/jenkins-common.sh` | 1073 | `FAILURE \|\| UNSTABLE \|\| ABORTED` | NOT_BUILT downstream builds not detected as failed |
| 4 | `output_json()` | `lib/jenkins-common.sh` | 2315 | `FAILURE \|\| UNSTABLE \|\| ABORTED` | JSON missing failure/test data for NOT_BUILT |
| 5 | `_handle_build_completion()` | `buildgit` | 776+ | Error logs only with `--console` | No error context in monitoring mode by default |

## Technical Requirements

### 1. Change gating conditions to non-SUCCESS logic

Instead of listing specific failure statuses, check for non-SUCCESS. This future-proofs against any other Jenkins result statuses.

**`_handle_build_completion()`** (buildgit:760):
```bash
# Before:
if [[ "$result" == "UNSTABLE" || "$result" == "FAILURE" ]]; then
# After:
if [[ "$result" != "SUCCESS" ]]; then
```

**`check_build_failed()`** (jenkins-common.sh:1073):
```bash
# Before:
if [[ "$result" == "FAILURE" || "$result" == "UNSTABLE" || "$result" == "ABORTED" ]]; then
# After:
if [[ -n "$result" && "$result" != "SUCCESS" ]]; then
```

**`output_json()`** (jenkins-common.sh:2315):
```bash
# Before:
if [[ "$result" == "FAILURE" || "$result" == "UNSTABLE" || "$result" == "ABORTED" ]]; then
# After:
if [[ "$result" != "SUCCESS" && "$result" != "null" && -n "$result" ]]; then
```

Note: Guard against empty/null results to avoid treating in-progress builds as failures.

### 2. Add NOT_BUILT to color mapping

**`print_finished_line()`** (jenkins-common.sh:211):
```bash
case "$result" in
    SUCCESS)    color="${COLOR_GREEN}" ;;
    FAILURE)    color="${COLOR_RED}" ;;
    NOT_BUILT)  color="${COLOR_RED}" ;;
    UNSTABLE)   color="${COLOR_YELLOW}" ;;
    ABORTED)    color="${COLOR_DIM}" ;;
    *)          color="${COLOR_RED}" ;;  # Default non-SUCCESS to red
esac
```

The `*` fallback changes from no color to red, treating unknown non-SUCCESS statuses as failures.

### 3. Add default error log display to monitoring mode

`_handle_build_completion()` must show error logs by default when no test failures are present, matching the behavior of `display_failure_output()`. The same `_display_error_logs()` function must be used to ensure consistent output.

The error log display decision logic should follow the same pattern as `display_failure_output()` (lines 1902-1914):

```
if test failures exist AND --console not specified:
    suppress error logs (test results are sufficient)
elif --console <N>:
    show last N lines of console
else:
    show extracted error logs via _display_error_logs()
```

This is the same logic currently in `display_failure_output()`. Consider extracting a shared helper function to avoid duplicating this decision logic between the two code paths.

### 4. Shared error log display logic

To ensure monitoring mode and snapshot mode stay consistent, the error log display decision (suppress for test failures, honor --console, default to extracted logs) should be in a shared function called from both:
- `_handle_build_completion()` (monitoring path)
- `display_failure_output()` (snapshot path)

This shared function takes: job_name, build_number, console_output, test_results_json, CONSOLE_MODE and decides what to display.

## Scope

### In Scope
- Fix all five code locations listed above
- Ensure `buildgit status`, `buildgit status -f`, `buildgit status --json`, `buildgit push`, and `buildgit build` all handle NOT_BUILT (and other non-SUCCESS results) consistently
- Add error log display to monitoring mode for failures without test results
- Share error log display logic between monitoring and snapshot paths

### Out of Scope
- Adding the Failed Jobs tree to monitoring mode (future spec for complex pipelines)
- Changing the stage display during monitoring (e.g. "unknown" duration for parallel stages)

## Acceptance Criteria

1. **`buildgit push` shows error logs for NOT_BUILT**: When a build completes with NOT_BUILT and a failed stage, error logs (including downstream extraction) are displayed before the "Finished:" line
2. **"Finished: NOT_BUILT" is red**: The status line uses red color, matching FAILURE
3. **Monitoring mode shows error logs for all non-SUCCESS results without test failures**: `push`, `build`, and `status -f` all display extracted error logs by default when there are no test failures to explain the result
4. **Error log suppression for test failures preserved**: When test failures exist, error logs are still suppressed by default (unless `--console` is specified)
5. **`--console` still works**: The `--console auto` and `--console <N>` options continue to work in all modes
6. **JSON output includes failure data for NOT_BUILT**: `buildgit status --json` for a NOT_BUILT build includes the `failure` object with error details
7. **`check_build_failed()` detects NOT_BUILT**: Downstream build detection correctly identifies NOT_BUILT builds as failed
8. **Shared code**: Error log display decision logic is shared between monitoring and snapshot paths, not duplicated
9. **Existing behavior preserved**: Builds with result SUCCESS, FAILURE, UNSTABLE, ABORTED continue to behave exactly as before (except FAILURE/UNSTABLE/ABORTED in monitoring mode now show error logs by default when no test failures exist — this is a consistency improvement)

## Testing

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| NOT_BUILT triggers error display in monitoring mode | Mock a completed build with result NOT_BUILT and a failed stage; verify `_handle_build_completion` shows error logs |
| NOT_BUILT shows red in finished line | Verify `print_finished_line "NOT_BUILT"` outputs red-colored text |
| NOT_BUILT detected by check_build_failed | Verify `check_build_failed` returns 0 (true) for NOT_BUILT result |
| NOT_BUILT JSON includes failure object | Mock NOT_BUILT build; verify `output_json` includes failure data |
| Monitoring mode shows error logs for FAILURE without test results | Verify `_handle_build_completion` calls `_display_error_logs` when result is FAILURE and no test results exist |
| Monitoring mode suppresses error logs when test failures exist | Verify error logs are not shown when test results with failures are present |
| Unknown status treated as failure | Mock build with an unrecognized result string; verify it's treated as a failure with red color |

### Manual Testing Checklist

- [ ] `buildgit push` for a build that completes as NOT_BUILT shows error logs and red status
- [ ] `buildgit status` for the same build shows consistent error information
- [ ] `buildgit status --json` for a NOT_BUILT build includes the `failure` object
- [ ] `buildgit push` for a FAILURE build (without test results) now shows error logs by default
- [ ] `buildgit push` for an UNSTABLE build (with test failures) still suppresses error logs by default
- [ ] `buildgit push --console auto` still works for all failure types
- [ ] `buildgit push --console 50` still works for all failure types

## Related Specifications

- `unify-follow-log-spec.md` — Unified monitoring output format (Section 4: Build Completion)
- `console-on-unstable-spec.md` — `--console` option and error log suppression logic
- `buildgit-early-build-failure-spec.md` — Early failure console display
- `bug-status-json-spec.md` — JSON output for failed builds
- `test-failure-display-spec.md` — Test failure output format
