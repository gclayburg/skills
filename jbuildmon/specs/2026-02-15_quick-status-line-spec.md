# Feature: Quick One-Line Status with TTY-Aware Default

- **Date:** `2026-02-15T14:52:46-07:00`
- **References:** `specs/done-reports/quick-status-line.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Overview

Add a compact one-line output mode to `buildgit status` that summarizes the latest (or specified) build in a single line, or multiple recent builds as one line each. This becomes the **default** when stdout is not a TTY (piped or redirected), making `buildgit status` scripting-friendly out of the box. The current full output becomes available via an explicit `--all` / `-a` flag.

## Syntax

```bash
buildgit status --line                  # One-line summary (explicit)
buildgit status --line=10               # Last 10 builds, newest to oldest
buildgit status --line=2                # Last 2 builds
buildgit status -l                      # Short form
buildgit status --all                   # Full output (explicit)
buildgit status -a                      # Short form
buildgit status                         # TTY -> full output; non-TTY -> one-line
buildgit status 41 --line               # One-line for specific build
buildgit status 41 --line=3             # Builds #41, #40, #39
buildgit --job <name> status --line     # One-line for specific job
```

### Example Output

Completed build:
```text
SUCCESS Job ralph1 #41 completed in 6m 41s on 2026-02-13 (2 days ago)
```

In-progress build:
```text
IN_PROGRESS Job ralph1 #42 running for 3m 12s (started 2026-02-15 14:30)
```

## Specification

### 1. New `--line` / `-l` Flag on `status` (with optional count)

`buildgit status` gains a new option:

```text
-l, --line[=N]    Print one-line summary (default when stdout is not a TTY)
```

This option applies only to `status`.

Count rules:
- `--line` means one build (equivalent to `--line=1`)
- `--line=N` means print `N` builds, newest to oldest
- `N` must be a positive integer (`1, 2, 3, ...`)
- `-l` is equivalent to `--line=1`

### 2. New `--all` / `-a` Flag on `status`

`buildgit status` gains a complementary option:

```text
-a, --all     Print full status output (default when stdout is a TTY)
```

This allows users to force full output even when piped (e.g., `buildgit status --all | less`).

### 3. TTY-Aware Default Behavior

When neither `--line` nor `--all` is specified:

| stdout is a TTY | Default mode |
|-----------------|--------------|
| Yes (interactive terminal) | Full output (current behavior) |
| No (pipe, redirect, subshell) | One-line output |

Detection uses the standard `[ -t 1 ]` test on file descriptor 1.

When `--line` or `--all` is explicitly specified, that choice overrides the TTY detection regardless of context.

### 4. Output Format — Completed Build

```text
<RESULT> Job <job_name> #<build_number> completed in <duration> on <date> (<relative_time>)
```

Field rules:
- `<RESULT>`: Jenkins result string (`SUCCESS`, `FAILURE`, `UNSTABLE`, `ABORTED`, `NOT_BUILT`)
- `<job_name>`: effective Jenkins job name
- `<build_number>`: build number
- `<duration>`: formatted elapsed duration (reuse existing `format_duration` helper)
- `<date>`: build completion date in `YYYY-MM-DD` format, local time
- `<relative_time>`: human-readable age (e.g., `2 days ago`, `3 hours ago`, `just now`)

### 5. Output Format — In-Progress Build

When the target build has no `result` (still running):

```text
IN_PROGRESS Job <job_name> #<build_number> running for <elapsed> (started <date> <time>)
```

Field rules:
- `<elapsed>`: time since build started, formatted with existing duration helper
- `<date> <time>`: build start timestamp in `YYYY-MM-DD HH:MM` format, local time

### 5.1 Multi-Build Line Mode (`--line=N`)

When `N > 1`, output consists of exactly `N` lines (or fewer if insufficient history), one build per line, in descending build number order:

1. latest build
2. latest-1
3. latest-2

Example for `--line=3`:

```text
SUCCESS Job ralph1 #42 completed in 4m 10s on 2026-02-15 (just now)
FAILURE Job ralph1 #41 completed in 3m 55s on 2026-02-15 (15 minutes ago)
SUCCESS Job ralph1 #40 completed in 6m 41s on 2026-02-13 (2 days ago)
```

If the job has fewer than `N` builds, print all available builds and do not error.

### 6. Fast Path

Line mode skips all expensive display work:
- No stage tree rendering
- No failed jobs tree rendering
- No console log fetching or extraction
- No test results display
- No verbose section output

The only Jenkins API calls required are:
- Fetching `lastBuild` number (or using provided build number)
- Fetching build info JSON for each build to print

Line mode must not fetch console logs, stage data, failed jobs trees, or test reports.

### 7. Option Compatibility

| Option | Compatible with `--line` | Behavior |
|--------|--------------------------|----------|
| `-a, --all` | No | Mutually exclusive — error |
| `--job <name>` | Yes | Use specified job |
| `--json` | No | Error (mutually exclusive modes) |
| `-f` / `--follow` | No | Error (line mode is snapshot only) |
| `[build#]` positional | Yes | Anchor at that build number; with `--line=N`, show that build and previous `N-1` |

| Option | Compatible with `--all` | Behavior |
|--------|--------------------------|----------|
| `-l, --line` | No | Mutually exclusive — error |
| `--job <name>` | Yes | Use specified job |
| `--json` | Yes | Unchanged behavior |
| `-f` / `--follow` | Yes | Unchanged behavior |
| `[build#]` positional | Yes | Unchanged behavior |

### 8. Error Handling

Incompatible option combinations:
- `Error: Cannot use --line with --all`
- `Error: Cannot use --line with --json`
- `Error: Cannot use --line with --follow`

Then print status usage to stderr and exit non-zero (consistent with usage-help-spec.md).

If `--line` count is invalid:
- `Error: Invalid --line value: <value> (must be a positive integer)`
- Exit non-zero

If no builds exist for the job:
- `Error: No builds found for job '<job_name>'`
- Exit non-zero

If build info cannot be fetched:
- `Error: Failed to fetch build information`
- Exit non-zero

### 9. Relative Time Calculation

Implement a `_format_relative_time()` helper that takes a Unix epoch timestamp and returns a human-readable relative time string:

| Age | Output |
|-----|--------|
| < 60 seconds | `just now` |
| < 60 minutes | `N minutes ago` (singular: `1 minute ago`) |
| < 24 hours | `N hours ago` (singular: `1 hour ago`) |
| < 30 days | `N days ago` (singular: `1 day ago`) |
| >= 30 days | `N weeks ago` or `N months ago` as appropriate |

### 10. Exit Code

Line mode follows the same exit code convention as full status:
- `--line` / `--line=1`: Exit 0 for `SUCCESS`, otherwise exit 1
- `--line=N` where `N > 1`: Exit code is based only on the newest/anchor build (first output line). Older lines do not affect exit code.
- For anchored mode (`status <build#> --line=N`), exit code is based only on `<build#>` (the first output line).

### 11. Help Text Update

Update `show_usage()`:

```text
Commands:
  status [build#] [-f|--follow] [--json] [--line[=N]] [--all]
                      Display Jenkins build status (latest or specific build)
                      Default: full output on TTY, one-line on pipe/redirect
```

Add examples:

```text
  buildgit status --line         # One-line status of latest build
  buildgit status --line=10      # One-line status for last 10 builds
  buildgit status --all | less   # Full status piped to pager
```

### 12. Consistency Rule

Per `CLAUDE.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must be consistent. This feature maintains that:
- `--line` and `--all` only affect the non-follow, non-JSON snapshot path
- `--json` and `-f` are explicitly incompatible with `--line`
- `--all` is compatible with `--json` and `-f` (no behavioral change; it just forces the full output path which is already what those modes use)

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Parse `--line`/`-l` with optional count (`--line=N`) and `--all`/`-a` in `_parse_status_options()`. Add TTY detection for default mode. Add `_format_relative_time()` helper. Implement one-line output path in `cmd_status()` for one or multiple builds. Validate incompatible option combinations and invalid count values. Update `show_usage()`. |
| `skill/buildgit/scripts/lib/jenkins-common.sh` | Possibly add or expose a helper to extract completion timestamp from build JSON (if not already available) |
| `test/buildgit_status.bats` | Add tests for `--line` success/in-progress output, `--line=N`, `--all` flag, TTY vs non-TTY default, option compatibility errors, build number with `--line`/`--line=N`, invalid line count, and output ordering validation |

## Acceptance Criteria

1. `buildgit status --line` prints exactly one summary line for the latest build.
2. `buildgit status -l` is equivalent to `--line`.
3. `buildgit status --line=10` prints up to 10 lines, newest build first.
4. `buildgit status --line=2` prints up to 2 lines, newest build first.
5. Output includes result, job name, build number, duration, date, and relative age for completed builds.
6. In-progress builds show `IN_PROGRESS` with elapsed time and start timestamp.
7. When stdout is not a TTY and no explicit mode flag is given, one-line output is the default (`--line=1` behavior).
8. When stdout is a TTY and no explicit mode flag is given, full output is shown (current behavior).
9. `buildgit status --all` forces full output regardless of TTY state.
10. `buildgit status -a` is equivalent to `--all`.
11. `--line` is rejected with `--json`, `--follow`, and `--all`.
12. `--job <name>` works with `--line` and `--line=N`.
13. `buildgit status 41 --line` shows one-line summary for build #41.
14. `buildgit status 41 --line=3` shows builds #41, #40, #39 (if available).
15. Invalid values like `--line=0` or `--line=abc` fail with usage and non-zero exit.
16. Help output documents `--line[=N]`, `--all`, and the TTY-aware default.
17. Exit code for line mode is determined only by the newest/anchor build (first output line): 0 for `SUCCESS`, non-zero otherwise.
18. Line mode does not fetch console logs or render stage trees.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `status_line_completed` | `--line` prints one line matching completed format for a finished build |
| `status_line_in_progress` | `--line` prints one line with IN_PROGRESS format for a running build |
| `status_line_short_flag` | `-l` is equivalent to `--line` |
| `status_line_count_2` | `--line=2` prints two builds in descending order |
| `status_line_count_10` | `--line=10` prints up to 10 builds in descending order |
| `status_line_with_job` | `--job` works with `--line` |
| `status_line_with_build_number` | `status 41 --line` shows one-line for specific build |
| `status_line_with_build_number_and_count` | `status 41 --line=3` shows 41, 40, 39 |
| `status_line_invalid_count_zero` | `--line=0` returns usage error and non-zero |
| `status_line_invalid_count_text` | `--line=abc` returns usage error and non-zero |
| `status_line_rejects_json` | `--line --json` returns error and non-zero |
| `status_line_rejects_follow` | `--line -f` returns error and non-zero |
| `status_line_rejects_all` | `--line --all` returns error and non-zero |
| `status_all_flag` | `--all` forces full output |
| `status_all_short_flag` | `-a` is equivalent to `--all` |
| `status_default_tty` | When stdout is a TTY with no flags, full output is shown |
| `status_default_pipe` | When stdout is not a TTY with no flags, one-line output is shown |
| `status_line_no_builds` | No builds returns clear error and non-zero |
| `status_line_relative_time` | Relative time formatting is correct for various ages |
