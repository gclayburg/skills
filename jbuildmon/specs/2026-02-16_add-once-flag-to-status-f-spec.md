# Feature: `--once` Flag for `buildgit status -f`

- **Date:** `2026-02-16T10:47:22-07:00`
- **References:** `specs/done-reports/add-once-flag-to-status-f.md`, `specs/done-reports/status-follow-once-wait-for-new-build.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Overview

Add a `--once` option to `buildgit status -f` that follows the current (or next) build to completion and then exits, rather than looping indefinitely. This makes follow mode safe for AI agents and scripts that need to monitor a single build without hanging forever.

Additionally, follow mode behavior is clarified: `-f` by default does **not** replay prior completed builds — it only monitors builds that are running at or start after the command is invoked. The `-n <count>` flag (introduced in `2026-02-19_line-n-flag-oldest-first-spec.md`) is extended to work with `-f`, allowing N prior completed builds to be printed before entering follow mode. This **overrides** the incompatibility declared in that spec.

## Problem Statement

`buildgit status -f` monitors the current build and then waits indefinitely for subsequent builds. The `push` and `build` commands already follow one build and exit, but there is no equivalent for `status -f`. AI agents using `status -f` get stuck because the command never terminates.

Additionally, when no build is currently running, the old behavior was to display the most recently completed build (which may be hours or days stale) before waiting for the next one. This is misleading for agents and scripts.

## Specification

### 1. New `--once` Flag on `status`

`buildgit status` gains a new option:

```text
--once[=N]    Exit after the first build completes (requires -f/--follow).
              N = seconds to wait for a new build to start (default: 10).
```

`--once` accepts an optional integer value via `=`:
- `--once` → 10-second timeout
- `--once=20` → 20-second timeout
- `--once=0` → no wait; exit immediately if no build is currently running

This option is only meaningful with follow mode.

### 2. Behavior of `-f` (Follow Mode) — Default

By default, `-f` (with or without `--once`) does **not** replay prior completed builds. It only monitors builds that are running at or after the time the command is invoked:

1. **Build currently in progress**: enter follow mode and monitor it to completion
2. **No build currently in progress**: wait for the next build to start (see section 3 for timeout behavior with `--once`)

After a build completes in plain `-f` (no `--once`), the loop continues and waits for the next new build — same as before, but without replaying stale completed builds on entry.

### 3. No Build In Progress

When `-f` is invoked and no build is currently running:

#### With `--once` (timeout mode)
- Wait up to N seconds (default 10) for a new build to start
- If a new build starts within N seconds: follow it to completion and exit
- If no new build starts within N seconds:
  - Print to stderr: `Error: no new build detected for N seconds`
  - Exit with code 2
- Do **not** display the previously completed build

#### Without `--once` (infinite follow mode)
- Wait indefinitely for the next build to start
- When a new build starts, monitor it to completion, then loop and wait for the next one
- Do **not** display previously completed builds

### 4. `-n <count>` with Follow Mode

The `-n <count>` flag from `2026-02-19_line-n-flag-oldest-first-spec.md` is extended to work with `-f`. This **overrides** the incompatibility defined in that spec (which declared `-n` with `--follow` an error).

When `-n <count>` is specified with `-f`:
1. Fetch and display the N most recently **completed** builds (oldest first), before entering follow mode
2. Then enter follow mode (monitor in-progress build, or wait for the next build)

Key rules:
- Only completed builds count toward `-n`; an in-progress build does not count
- The N prior builds are displayed **before** the `--once` timeout begins
- `-n` with `-f --once`: print N prior builds, then wait up to timeout for next build
- `-n` with `-f` (no `--once`): print N prior builds, then wait indefinitely

### 5. Option Compatibility

| Option | Compatible with `--once` | Behavior |
|--------|--------------------------|----------|
| `-f` / `--follow` | Required | `--once` must be used with `-f` |
| `--json` | Yes | Follow one build, output JSON, exit |
| `--line` / `-l` | No | Error (line mode is incompatible with follow) |
| `--all` / `-a` | Yes | Ignored (follow mode already shows full output) |
| `[build#]` positional | No | Error (follow mode already rejects build numbers) |
| `--job <name>` | Yes | Follow specified job |
| `--no-tests` | Yes | Ignored (follow mode uses its own test display) |
| `-n <count>` | Yes | Print N prior completed builds before entering follow mode |

### 6. Error Handling

If `--once` is used without `-f`/`--follow`:
- `Error: --once requires --follow (-f)`
- Print usage to stderr and exit non-zero

If `--once` timeout expires with no new build:
- `Error: no new build detected for N seconds` (to stderr)
- Exit with code 2

If `--once=N` where N is not a non-negative integer:
- `Error: --once value must be a non-negative integer`
- Exit non-zero

### 7. Implementation Detail

`_cmd_status_follow()` currently runs a `while true` loop. Changes:

**Entry behavior change**: On entry, do not display the latest completed build. Instead:
- If a build is in progress: monitor it
- If no build is running: go directly to "wait for next build" logic (with or without timeout)

**With `--once`**: After the build completes and output is displayed:
```
if [[ "$STATUS_ONCE_MODE" == "true" ]]; then
    return $build_exit_code
fi
```

**Timeout for new build (--once, no build running)**:
```
# Deadline-based polling loop:
if [[ "$STATUS_ONCE_MODE" == "true" ]]; then
    if [[ $elapsed -ge $STATUS_ONCE_TIMEOUT ]]; then
        bg_log_error "no new build detected for ${STATUS_ONCE_TIMEOUT} seconds"
        return 2
    fi
fi
```

**`-n` prior builds**: Before entering the wait loop, if `-n` was specified:
```
# Display N most recently completed builds (oldest first)
_display_n_prior_builds "$job_name" "$STATUS_N_COUNT"
# Then start follow mode (and --once timeout if applicable)
```

### 8. Follow Mode Info Message

When `--once` is active, update the initial info message:

**Plain `-f`**:
```text
[HH:MM:SS] ℹ Follow mode enabled - monitoring builds for job 'ralph1'
[HH:MM:SS] ℹ Press Ctrl+C to stop monitoring
```

**With `--once`**:
```text
[HH:MM:SS] ℹ Follow mode enabled (once, timeout=10s) - monitoring builds for job 'ralph1'
```

The "Press Ctrl+C" message is omitted since the command will exit on its own.

### 9. Help Text Update

Update `show_usage()`:

```text
Commands:
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests]
                      Display Jenkins build status (latest or specific build)
                      Default: full output on TTY, one-line on pipe/redirect
```

Add examples:

```text
  buildgit status -f --once        # Follow current/next build, exit when done (10s timeout)
  buildgit status -f --once=20     # Same, but wait up to 20 seconds for build to start
  buildgit status -n 3 -f          # Show 3 prior builds, then follow indefinitely
  buildgit status -n 3 -f --once   # Show 3 prior builds, then follow once with timeout
```

### 10. SKILL.md Update

Add `status -f --once` to the commands table in SKILL.md with description: "Follow current/next build to completion, then exit." Add a recommendation that agents use `status -f --once` instead of `status -f` to avoid indefinite blocking.

### 11. Consistency Rule

Per `CLAUDE.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must be consistent. This feature:
- Does not change the output format of follow mode — only controls when it exits and what is shown on entry
- `--once --json` produces the same JSON output as `--json` follow mode, just for one build
- Existing `status -f` behavior is updated: it no longer replays stale completed builds on entry

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Add `STATUS_ONCE_MODE`, `STATUS_ONCE_TIMEOUT` to `_parse_status_options()`. Parse `--once[=N]` syntax. Add validation (`--once` requires `-f`; N must be non-negative integer). Remove stale-build-replay on entry. Add timeout loop when `--once` and no build running. Allow `-n` with `-f` (remove existing error). Add prior-build display before follow loop. Update info message. Update `show_usage()`. |
| `skill/buildgit/SKILL.md` | Add `status -f --once` to commands table. Add agent recommendation. |
| `test/buildgit_status.bats` | Add/update tests per Test Strategy below. |

## Acceptance Criteria

1. `buildgit status -f --once` monitors the current in-progress build and exits when it completes.
2. Exit code is 0 for SUCCESS, 1 for non-SUCCESS.
3. `--once` without `-f` produces `Error: --once requires --follow (-f)` and exits non-zero.
4. `buildgit status -f` without `--once` no longer replays stale completed builds; it waits silently for the next new build.
5. `buildgit status -f --once --json` outputs JSON for the followed build and exits.
6. When no build is in progress, `--once` waits up to 10 seconds for a new build to start.
7. When no build starts within the timeout, exits with `Error: no new build detected for N seconds` on stderr and exit code 2.
8. `--once=20` waits up to 20 seconds for a new build to start.
9. `--once=N` with a non-integer or negative N is a usage error.
10. Info message shows `(once, timeout=Ns)` when `--once` is active; omits "Press Ctrl+C".
11. `buildgit status -f` without `--once` continues to loop indefinitely after each build completes (no behavioral change to the loop itself).
12. `buildgit status -n 3 -f` displays 3 prior completed builds (oldest first), then follows indefinitely.
13. `buildgit status -n 3 -f --once` displays 3 prior completed builds, then waits for next build with timeout.
14. The `-n` prior builds are displayed before the `--once` timeout begins.
15. In-progress builds do not count toward `-n`.
16. Help text documents `--once[=N]` and `-n` with follow mode.
17. SKILL.md documents `status -f --once` and recommends it for agents.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `status_follow_once_exits` | `status -f --once` exits after the first build completes instead of looping |
| `status_follow_once_exit_code_success` | `--once` exits 0 when build result is SUCCESS |
| `status_follow_once_exit_code_failure` | `--once` exits 1 when build result is FAILURE |
| `status_once_requires_follow` | `status --once` without `-f` produces error and non-zero exit |
| `status_follow_once_timeout` | When no build starts within timeout, exits with error message and code 2 |
| `status_follow_once_custom_timeout` | `--once=20` uses 20-second timeout before exiting |
| `status_follow_once_invalid_timeout` | `--once=abc` and `--once=-1` produce usage error |
| `status_follow_no_stale_replay` | `status -f` with no running build does not display the prior completed build |
| `status_follow_once_no_stale_replay` | `status -f --once` with no running build does not display the prior completed build |
| `status_follow_once_json` | `status -f --once --json` outputs JSON and exits |
| `status_follow_once_info_message` | Info message includes `(once, timeout=10s)` and omits "Press Ctrl+C" |
| `status_follow_n_prior_builds` | `status -n 2 -f` displays 2 prior completed builds then follows |
| `status_follow_n_once_prior_builds` | `status -n 2 -f --once` displays 2 prior builds, then applies timeout |
| `status_follow_n_inprogress_not_counted` | In-progress build does not count toward `-n` prior builds |
| `status_follow_n_prior_before_timeout` | Prior `-n` builds are shown before `--once` timeout countdown begins |
