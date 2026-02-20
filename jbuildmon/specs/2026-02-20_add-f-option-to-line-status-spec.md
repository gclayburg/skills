# Feature: Follow Mode with Line Output (`-f --line`) and In-Progress Bar

- **Date:** `2026-02-20T10:58:39-0700`
- **References:** `specs/done-reports/add-f-option-to--line-status.md`
- **Supersedes:** `2026-02-15_quick-status-line-spec.md` (partially — removes `--line` / `--follow` incompatibility), `2026-02-19_line-n-flag-oldest-first-spec.md` (partially — removes `-n` / `--follow` / `--line` incompatibility)
- **State:** `IMPLEMENTED`

## Overview

Allow `--line` to be combined with `-f` (follow mode). When a build is in progress on a TTY, display an animated single-line progress bar that estimates completion based on the last successful build's duration. When the build finishes, the progress bar is erased and replaced with the standard `--line` output. In continuous follow mode, completed builds accumulate as permanent lines and the next in-progress bar appears on a new line below.

When not on a TTY, the progress bar is suppressed — in-progress builds produce no output until they complete, at which point the standard `--line` output is printed.

## Problem Statement

Currently `buildgit status --line` and `buildgit status -f` are mutually exclusive. Users who want compact, follow-mode output must choose between the verbose follow output or the compact snapshot. This feature bridges the gap by providing a compact, real-time, single-line follow experience with a visual progress indicator for in-progress builds.

## Specification

### 1. Remove `--line` / `--follow` Incompatibility

Remove the error: `Cannot use --line with --follow`. The combination `buildgit status -f --line` is now valid.

Also allow `-n <count>` with `-f --line` (currently blocked by `-n` / `--follow` incompatibility from `2026-02-19_line-n-flag-oldest-first-spec.md`). This was already partially lifted by the `--once` spec for `-n` with `-f`, but now extends to `-f --line` as well.

### 2. In-Progress Build Display (TTY Only)

When a build is in progress and stdout is a TTY, display a single animated line that overwrites itself in-place using `\r`:

```text
IN_PROGRESS Job ralph1 #42 [=====>          ] 35% 1m 24s / ~4m 10s
```

Format:
```text
IN_PROGRESS Job <job_name> #<build_number> [<bar>] <pct>% <elapsed> / ~<estimate>
```

Field rules:
- `<bar>`: A bracket-enclosed progress bar, 20 characters wide. Filled portion uses `=` with a `>` head. Unfilled portion uses spaces. Examples: `[===>                ]` (20%), `[===========>        ]` (55%), `[====================]` (100%).
- `<pct>`: Integer percentage (0–100+). Clamped to display between 0 and 100 for the bar, but the text can show values above 100%.
- `<elapsed>`: Time since build started, formatted with existing duration helper (e.g., `1m 24s`).
- `<estimate>`: Estimated total duration prefixed with `~`, based on the last successful build's duration (e.g., `~4m 10s`). If no prior successful build exists, show `~unknown` and use an indeterminate display (no percentage, pulsing bar).

The line is updated on each poll cycle (same interval as follow mode polling).

### 3. Estimate Source

The duration estimate comes from the **last successful build** for the same job:
1. Fetch the most recent build with `result == "SUCCESS"`
2. Use its `duration` field as the estimate
3. If no successful build exists, the estimate is unknown — show `~unknown` and display an indeterminate bar (e.g., `[<===>               ]` bouncing)

No averaging or extra API calls beyond fetching the one prior successful build.

### 4. Over-Estimate Behavior

When the build runs longer than the estimate (elapsed > estimated duration):
- The bar fills completely: `[====================]`
- The percentage shows the actual value (e.g., `115%`)
- Elapsed time continues to tick up
- The estimate remains the original value

Example:
```text
IN_PROGRESS Job ralph1 #42 [====================] 115% 4m 48s / ~4m 10s
```

### 5. Build Completion — Replace Bar with `--line` Output

When the in-progress build completes:
1. Erase the progress bar line (use `\r` + clear-to-end-of-line `\033[K`)
2. Print the standard `--line` format output for that build (same as `buildgit status --line` would show), including test results if available
3. This line is permanent (not overwritten)

Example transition:
```
[during build]
IN_PROGRESS Job ralph1 #42 [============>       ] 60% 2m 30s / ~4m 10s

[after completion]
SUCCESS     Job ralph1 #42 Tests=557/0/0 Took 4m 10s on 2026-02-20 (just now)
```

### 6. Continuous Follow Mode (`-f --line`, No `--once`)

In continuous follow mode, completed builds accumulate as permanent lines. The flow:

1. If a build is in progress: show progress bar, wait for completion, print final `--line`
2. Wait for the next build to start
3. When a new build starts: show progress bar on a new line below the previous completed line
4. Repeat

The result is a growing list of completed `--line` rows, with at most one animated progress bar at the bottom.

### 7. Follow-Once Mode (`-f --once --line`)

Same as continuous mode but exits after the first build completes, consistent with existing `--once` behavior.

### 8. Non-TTY Behavior

When stdout is **not** a TTY:
- Do **not** show the progress bar or any in-progress output
- Wait silently until the build completes
- Print the standard `--line` output once the build finishes
- This matches the existing principle: animated/interactive output is TTY-only

Detection uses the same TTY check as color output (`[ -t 1 ]`).

### 9. `-n <count>` with `-f --line`

When `-n <count>` is combined with `-f --line`:
1. Fetch and display the N most recently **completed** builds as static `--line` rows (oldest first, matching existing `-n` ordering)
2. Then enter follow mode with the progress bar for the current/next build

The N prior builds are printed before any progress bar or `--once` timeout begins.

Example: `buildgit status -n 3 -f --line`
```text
SUCCESS     Job ralph1 #40 Tests=557/0/0 Took 6m 41s on 2026-02-18 (2 days ago)
FAILURE     Job ralph1 #41 Tests=376/1/30 Took 3m 55s on 2026-02-19 (1 day ago)
SUCCESS     Job ralph1 #42 Tests=557/0/0 Took 4m 10s on 2026-02-20 (15 minutes ago)
IN_PROGRESS Job ralph1 #43 [===>                ] 18% 0m 45s / ~4m 10s
```

### 10. Option Compatibility (Updated)

| Option | Compatible with `-f --line` | Behavior |
|--------|----------------------------|----------|
| `--once[=N]` | Yes | Follow one build in line mode with progress bar, then exit |
| `-n <count>` | Yes | Print N prior completed builds as `--line` rows before following |
| `--json` | No | Error: `Cannot use --line with --json` (unchanged) |
| `--all` | No | Error: `Cannot use --line with --all` (unchanged) |
| `[build#]` | No | Error (follow mode rejects build numbers, unchanged) |
| `--job <name>` | Yes | Use specified job |
| `--no-tests` | Yes | Skip test API calls in final `--line` output |

### 11. TTY Check

Use the same TTY detection already used for color output. The progress bar requires:
- stdout is a TTY (`[ -t 1 ]`)
- `--line` is active
- `-f` (follow mode) is active
- A build is currently in progress

If any of these conditions is false, fall back to the non-TTY behavior (silent wait, then print `--line` on completion).

### 12. Help Text Update

Update `show_usage()` to reflect that `--line` and `-f` are now compatible:

```text
Commands:
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests]
                      Display Jenkins build status (latest or specific build)
                      Default: full output on TTY, one-line on pipe/redirect
```

Add/update examples:

```text
  buildgit status -f --line          # Follow builds with compact one-line output + progress bar
  buildgit status -f --once --line   # Follow one build with progress bar, then exit
  buildgit status -n 5 -f --line    # Show 5 prior builds, then follow with progress bar
```

### 13. Consistency Rule

Per `CLAUDE.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must be consistent. This feature:
- Adds a new output mode for `-f` when combined with `--line` — it does not change the default `-f` behavior
- The final `--line` output for completed builds is identical to `buildgit status --line` snapshot mode
- `--json` remains incompatible with `--line` (unchanged)
- Non-follow `--line` snapshot behavior is unchanged

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Remove `--line` / `--follow` incompatibility error. Add `_display_follow_line_progress()` function for animated progress bar. Add `_get_last_successful_build_duration()` to fetch estimate. Modify `_cmd_status_follow()` to use line-mode output path when `STATUS_LINE_MODE` is true. Handle TTY vs non-TTY in follow-line mode. Support `-n` prior builds before follow-line mode. Update `show_usage()`. |
| `test/buildgit_status.bats` | Add tests per Test Strategy below. |
| `skill/buildgit/SKILL.md` | Document `status -f --line` option. |

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)

## Acceptance Criteria

1. `buildgit status -f --line` no longer produces an error.
2. On a TTY, an in-progress build shows an animated `[=====>    ]` progress bar that updates in-place.
3. The progress bar estimate is based on the last successful build's duration.
4. When no prior successful build exists, the bar shows `~unknown` with an indeterminate animation.
5. When the build takes longer than estimated, the bar shows `[====================]` with percentage > 100%.
6. When the build completes, the progress bar is replaced with standard `--line` output (including test results).
7. In continuous follow mode (`-f --line`), completed lines accumulate and the progress bar appears on a new line for each subsequent build.
8. `buildgit status -f --once --line` follows one build with progress bar and exits.
9. On a non-TTY, no progress bar is shown; output waits until the build completes, then prints `--line` output.
10. `-n <count>` works with `-f --line`: N prior completed builds are printed as `--line` rows before the progress bar.
11. `--line` remains incompatible with `--json` and `--all`.
12. Help text is updated with new examples.
13. Exit codes follow existing conventions (0 for SUCCESS, 1 for non-SUCCESS, 2 for `--once` timeout).
14. all `specs/CLAUDE.md` rules are followed for implementing this DRAFT spec

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `status_follow_line_no_error` | `status -f --line` is accepted without error |
| `status_follow_line_completed_output` | After a build completes in follow-line mode, output matches standard `--line` format |
| `status_follow_line_once_exits` | `status -f --once --line` exits after the first build completes |
| `status_follow_line_once_exit_code` | Exit code is 0 for SUCCESS, 1 for FAILURE in follow-line-once mode |
| `status_follow_line_non_tty` | On non-TTY, no progress bar is shown; only final `--line` output after completion |
| `status_follow_line_n_prior_builds` | `-n 3 -f --line` prints 3 prior completed builds as `--line` rows before following |
| `status_follow_line_rejects_json` | `-f --line --json` still produces an error |
| `status_follow_line_rejects_all` | `-f --line --all` still produces an error |
| `status_follow_line_progress_bar_format` | Progress bar output matches expected `[=====>    ]` format (TTY mock) |
| `status_follow_line_estimate_from_last_success` | Estimate duration is fetched from the last successful build |
| `status_follow_line_no_prior_success` | When no prior successful build exists, bar shows `~unknown` |
| `status_follow_line_over_estimate` | When elapsed exceeds estimate, percentage shows >100% and bar is full |
| `status_follow_line_once_timeout` | `--once` timeout still works in line mode — exits code 2 if no build starts |
