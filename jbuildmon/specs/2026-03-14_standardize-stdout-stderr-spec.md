## Standardize stdout/stderr output streams for buildgit

- **Date:** `2026-03-14T11:04:28-06:00`
- **References:** `specs/done-reports/standardize-stdout-stderr.md`
- **Supersedes:** none
- **Plan:** `none`
- **State:** `IMPLEMENTED`

## Problem Statement

buildgit currently sends normal build-monitoring output to stderr, which means redirecting stdout to a file (`buildgit build > /tmp/out.log`) leaves progress messages visible on the console instead of captured in the log file. The user expects `> file` to capture all normal output silently.

Example of broken behavior:
```
$ ./buildgit build > /tmp/outb.log
[10:38:56] ℹ Waiting for Jenkins build ralph1/main to start...
[10:38:56] ℹ Build #79 is QUEUED — In the quiet period. Expires in 4.9 sec
[10:39:01] ℹ Build #79 is QUEUED — Finished waiting
[10:39:14] ℹ   Stage: [agent6 guthrie] Build (4s)
...
```

All of those `[HH:MM:SS] ℹ` messages should have gone into `/tmp/outb.log`, not the terminal.

The same problem affects `buildgit push > file` and `buildgit status -f > file`.

## Root Cause Analysis

The core logging functions in `jenkins-common.sh` route output as follows:

| Function | Current stream | Should be |
|---|---|---|
| `log_info()` | stdout | stdout (correct) |
| `log_success()` | stdout | stdout (correct) |
| `log_warning()` | stdout | stdout (correct) |
| `log_error()` | stderr | stderr (correct) |
| `bg_log_progress()` | stderr (via `log_info >&2`) | **stdout** |
| `bg_log_progress_success()` | stderr (via `log_success >&2`) | **stdout** |
| `bg_log_info()` | stderr (when VERBOSE_MODE=true) | **stdout** |
| `bg_log_success()` | stderr (when VERBOSE_MODE=true) | **stdout** |
| `bg_log_warning()` | stdout | stdout (correct) |
| `bg_log_error()` | stderr | stderr (correct) |
| `bg_log_essential()` | stdout | stdout (correct) |

The `bg_log_progress()` and `bg_log_progress_success()` functions were intentionally sent to stderr per `bug2026-02-01-buildgit-monitoring-spec.md, Issue 3` to avoid corrupting command substitution return values. However, the correct fix for command substitution safety is to not call logging functions inside `$(...)` — not to redirect all monitoring output to stderr.

Additionally, several call sites in `stage_display.sh`, `monitor_helpers.sh`, and `job_helpers.sh` explicitly append `>&2` to output calls.

## Specification

### Output stream rules

**stdout** — all normal program output:
- Build status information (snapshot, monitoring, JSON, line mode)
- Stage progress messages (`[HH:MM:SS] ℹ Stage: ...`)
- Queue wait messages (`Build #N is QUEUED — ...`)
- Build completion output (success, failure, unstable)
- Test results display
- Verbose mode diagnostic messages (`bg_log_info`, `bg_log_success`)
- Warnings about build state (e.g., `Tests=!err!` status in line mode)
- Banner messages
- Help/usage output (when explicitly requested via `--help`)

**stderr** — only actual errors unrelated to the build being monitored:
- Communication failures (HTTP errors, DNS failures, timeouts connecting to Jenkins)
- Invalid command syntax / unknown options
- Permission problems
- `log_error()` messages
- Usage text when triggered by invalid input (existing behavior, correct)

**stderr** — transient TTY control artifacts:
- Cursor repositioning sequences (`\r\033[K`, cursor-up for `--threads`)
- These are already suppressed when stdout is not a TTY, so no change needed

### Key principle

A failed build is NOT an error condition for stderr. Build failure messages (failed stages, failed tests, error logs from Jenkins) are normal program output and go to stdout.

### Communication failure dual-output pattern

When a communication failure occurs during an operation that also produces status output (e.g., test results fetch fails), two messages are needed:
1. **stdout**: status update showing the result (e.g., `Tests=!err!` in line mode)
2. **stderr**: the communication error itself (e.g., `"Could not retrieve test results (communication error)"`)

### Logging function changes in `jenkins-common.sh`

```bash
# CHANGE: bg_log_progress — remove >&2
bg_log_progress() {
    log_info "$@"
}

# CHANGE: bg_log_progress_success — remove >&2
bg_log_progress_success() {
    log_success "$@"
}

# CHANGE: bg_log_info — remove >&2
bg_log_info() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_info "$@"
    fi
}

# CHANGE: bg_log_success — remove >&2
bg_log_success() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_success "$@"
    fi
}
```

### Call-site `>&2` removal

All explicit `>&2` redirections on normal output calls must be removed from:

1. **`stage_display.sh`** — `print_stage_line` calls that append `>&2` (lines ~352, 359, 783, 807, 809, 930, 937, 961, 968)
2. **`monitor_helpers.sh`** — `printf '%s\n' "$stage_output" >&2` calls (lines ~167, 190, 216, 233, 270) and `bg_log_progress` calls
3. **`job_helpers.sh`** — queue wait `printf '%b' "$payload" >&2` calls (lines ~422, 446) and `log_info "Build #... is QUEUED" >&2` calls (lines ~559, 562)
4. **`api_test_results.sh`** — communication error warnings that mix status and error:
   - Status line update (TTY cursor overwrite): keep on stderr (it's a transient TTY artifact)
   - `log_warning "Could not retrieve test results (communication error)"`: change to stderr via `log_error` or explicit `>&2` (this IS a communication failure)
   - The status output showing `Tests=!err!` in line mode stays on stdout (correct)

### Command substitution safety

Any caller that currently relies on `bg_log_progress` or `bg_log_progress_success` writing to stderr to avoid corrupting a `$(...)` return value must be audited. These calls must be moved outside the command substitution, or the function must not be called inside `$(...)`.

### TTY progress bar and `--threads` rows

- The `_status_stdout_is_tty()` function checks `[[ -t 1 ]]` (stdout fd). When stdout is redirected to a file, this returns false and TTY control sequences are already suppressed. No change needed for this detection.
- Transient cursor-control writes (`\r\033[K`, cursor-up sequences for `--threads`) should remain on stderr since they are display artifacts, not program output. They are only emitted when `_status_stdout_is_tty()` is true (i.e., stdout IS a TTY), so they don't appear in redirected output anyway.

## Test Strategy

### Existing tests
- All existing tests must continue to pass. Many tests capture stdout and assert on it — these should still work since the change moves MORE output to stdout, not less.
- Tests that assert on stderr content for monitoring messages will need updating.

### New tests

1. **`test/buildgit_output_streams.bats`** — new test file for output stream validation:
   - `build_monitoring_stage_output_goes_to_stdout`: Mock a build with stage progress, verify stage lines appear on stdout (fd 1), not stderr (fd 2).
   - `build_monitoring_queue_output_goes_to_stdout`: Mock a queued build, verify queue wait messages appear on stdout.
   - `communication_error_goes_to_stderr`: Mock a curl failure, verify the error message appears on stderr.
   - `invalid_option_error_goes_to_stderr`: Run with invalid option, verify usage error on stderr.
   - `build_failure_output_goes_to_stdout`: Mock a failed build, verify failure details appear on stdout, not stderr.
   - `verbose_output_goes_to_stdout`: Run with `-v`, verify verbose messages appear on stdout.

2. **Update existing tests** that capture stderr and assert monitoring messages are present — change assertions to check stdout instead.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
