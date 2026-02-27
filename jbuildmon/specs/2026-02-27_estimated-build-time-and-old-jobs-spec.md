# Feature: Estimated Build Time and Prior Build History for Monitoring Commands

- **Date:** `2026-02-27T00:00:00-0700`
- **References:** `specs/done-reports/estimated-time-to-complete-build.md`, `specs/done-reports/prior-jobs-display.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Overview

When running any build-monitoring command (`push`, `build`, `status -f`), display two pieces of context immediately after "Waiting for Jenkins build to start…":

1. **Prior build history** — the last N completed builds in one-line format (default N=3), preceded by a `log_info` header line.
2. **Estimated build time** — a single `log_info` line showing how long this build is expected to take, derived from the last successful build's duration.

Both are always shown during monitoring. Neither is shown for snapshot `buildgit status`.

## Problem Statement

A developer starting `buildgit push` has no indication of how long to wait or whether recent builds have been healthy. Showing the last few builds and an upfront time estimate sets expectations and surfaces recent failures at a glance.

## Reference Output

The following is the canonical output template (from `specs/todo/prior-jobs-display.md`):

```
[10:23:48] ℹ Waiting for Jenkins build ralph1 to start...
[10:23:48] ℹ Prior 3 Jobs
SUCCESS     #54 id=6685a31 Tests=19/0/0 Took 5m 38s on 2026-02-22T22:37:21-0700 (4 days ago)
SUCCESS     #55 id=46f85cb Tests=19/0/0 Took 5m 40s on 2026-02-23T00:10:00-0700 (4 days ago)
SUCCESS     #56 id=0046c54 Tests=19/0/0 Took 6m 39s on 2026-02-24T10:14:10-0700 (3 days ago)
[10:23:48] ℹ Estimated build time = 6m 39s
[10:23:58] ℹ Starting

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝
```

## Specification

### 1. Output Format

#### Prior Jobs Block

When the prior-jobs count N > 0, print immediately after "Waiting for Jenkins build to start…":

```
[HH:MM:SS] ℹ Prior N Jobs
<one-line build>           ← oldest first
<one-line build>
...
```

- Header: `[HH:MM:SS] ℹ Prior N Jobs` via `log_info` — uses the requested N value regardless of how many builds are actually available.
- No footer line.
- The one-line build entries are plain stdout (no timestamp prefix).
- One-line format for each build uses the default `--line` format string (`%s #%n id=%c Tests=%t Took %d on %I (%r)`). If `--format` is also specified, it applies to prior-jobs lines as well.
- Builds are displayed **oldest first**.
- In-progress builds are excluded and do not count toward N.
- If fewer than N completed builds exist, show all available; the header still says `Prior N Jobs`.
- If zero completed builds exist and N > 0, omit the prior-jobs block entirely (no header line either).

#### Estimated Build Time Line

Immediately after the prior-jobs block (or immediately after "Waiting for Jenkins build to start…" when N=0), print via `log_info`:

```
[HH:MM:SS] ℹ Estimated build time = 4m 10s
```

- Uses `log_info` format (same timestamp+icon prefix as other informational messages).
- Duration formatted via existing `format_duration()`.
- Data source: `_get_last_successful_build_duration()` (already implemented) — queries `/job/<name>/lastSuccessfulBuild/api/json`.
- If no prior successful build exists (returns empty or `0`): `Estimated build time = unknown`

### 2. Placement in Output Flow

#### `buildgit push [--prior-jobs N]`

```
Pushing to remote...
[git push output]
[HH:MM:SS] ℹ Waiting for Jenkins build ralph1 to start...
[HH:MM:SS] ℹ Prior 3 Jobs
SUCCESS     #54 id=6685a31 Tests=19/0/0 Took 5m 38s on ...
SUCCESS     #55 id=46f85cb Tests=19/0/0 Took 5m 40s on ...
SUCCESS     #56 id=0046c54 Tests=19/0/0 Took 6m 39s on ...
[HH:MM:SS] ℹ Estimated build time = 6m 39s
[HH:MM:SS] ℹ Starting
[normal monitoring output follows]
```

#### `buildgit build [--prior-jobs N]`

```
Triggering build for job 'ralph1'...
Build triggered successfully
[HH:MM:SS] ℹ Waiting for Jenkins build ralph1 to start...
[HH:MM:SS] ℹ Prior 3 Jobs
...
[HH:MM:SS] ℹ Estimated build time = 6m 39s
[HH:MM:SS] ℹ Starting
[normal monitoring output follows]
```

#### `buildgit status -f [--prior-jobs N]`

For `status -f`, the "Waiting for Jenkins build to start…" message already appears in the follow loop when no build is running. The prior-jobs block and estimate appear in the same relative position — after that message and before monitoring begins.

If a build is already in progress when `status -f` starts (i.e., no waiting phase), the prior-jobs block and estimate are printed before the monitoring output begins.

If `-n <count>` is also specified, the `-n` prior-build display (full or line mode) runs first, then the prior-jobs block and estimate appear before the follow loop.

### 3. `--prior-jobs <N>` Option

Add `--prior-jobs <N>` to `push`, `build`, and `status` (follow mode only).

**Default:** `3` — prior jobs are shown without specifying the option.

**Syntax:** `--prior-jobs <N>` (space-separated value, same style as `-n <count>`).

**Validation:**
- `N` must be a non-negative integer.
- `N = 0`: valid — no prior-jobs block is shown, but the estimate line is still printed.
- Negative values (e.g. `--prior-jobs -1`) → error: `"--prior-jobs value must be a non-negative integer"`, exit 1.
- Non-integer values (e.g. `--prior-jobs foo`) → error: `"--prior-jobs value must be a non-negative integer"`, exit 1.
- Missing value (e.g. `--prior-jobs` at end of args) → error: `"--prior-jobs requires a value"`, exit 1.

**Applicable commands:**

| Command | Shows estimate | Shows prior jobs | Supports `--prior-jobs` |
|---------|---------------|-----------------|------------------------|
| `buildgit push` | Yes (always) | Yes (default 3) | Yes |
| `buildgit build` | Yes (always) | Yes (default 3) | Yes |
| `buildgit status -f` | Yes (always) | Yes (default 3) | Yes |
| `buildgit status -f --line` | Yes (always) | Yes (default 3) | Yes |
| `buildgit push --line` | Yes (always) | Yes (default 3) | Yes |
| `buildgit build --line` | Yes (always) | Yes (default 3) | Yes |
| `buildgit status` (snapshot) | No | Yes (default 3) | Yes — see `2026-02-27_add-prior-jobs-to-snapshot-status-spec.md` |
| `buildgit status --json` | No | No | Silently ignored |

### 4. `--no-tests` Interaction

When `--no-tests` is active, pass `no_tests=true` to `_display_n_prior_builds()` for the prior-jobs block. Prior-job lines show `?/?/?` for the test count instead of making test API calls.

### 5. `--format` Interaction

When `--format <fmt>` is specified, it applies to prior-jobs one-line output as well as the main monitoring output. If `--format` is not specified, prior-jobs lines use the default format string.

### 6. Non-TTY Behavior

The prior-jobs block and estimate line are plain text written to stdout. They appear on both TTY and non-TTY. No animations or ANSI color in the prior-jobs block on non-TTY (existing colorization rules apply).

### 7. Option Parsing Changes

**`_parse_push_options()`:** Add `--prior-jobs <N>` → sets `PUSH_PRIOR_JOBS=<N>` (default `3`).

**`_parse_build_options()`:** Add `--prior-jobs <N>` → sets `BUILD_PRIOR_JOBS=<N>` (default `3`).

**`_parse_status_options()`:** Add `--prior-jobs <N>` → sets `STATUS_PRIOR_JOBS=<N>` (default `3`). Active in all status modes (snapshot and follow); silently ignored only for `--json` mode. See `2026-02-27_add-prior-jobs-to-snapshot-status-spec.md` for snapshot behavior.

### 8. Implementation Approach

Extract a new helper function `_display_monitoring_preamble()`:

```bash
# Display prior jobs block and estimated build time before monitoring begins.
# Arguments: job_name, prior_jobs_count, [no_tests], [fmt]
# Prints prior-jobs block (if count > 0) then estimate line via log_info.
_display_monitoring_preamble() { ... }
```

This function:
1. If `prior_jobs_count > 0`, prints the header via `log_info "Prior N Jobs"` then calls `_display_n_prior_builds()` in line mode.
2. Calls `_get_last_successful_build_duration()` and prints the estimate line via `log_info "Estimated build time = ..."`.
If zero completed builds are returned by `_display_n_prior_builds()`, omits the header line entirely.

Call `_display_monitoring_preamble()` from `cmd_push()`, `cmd_build()`, and the `status -f` code path, after the "Waiting for Jenkins build to start…" message is printed and before entering the monitoring loop.

### 9. Help Text Updates

```text
Commands:
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests] [--format <fmt>] [--prior-jobs <N>]
                      Display Jenkins build status (latest or specific build)
  push [--no-follow] [--line] [--format <fmt>] [--prior-jobs <N>] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] [--line] [--format <fmt>] [--prior-jobs <N>]
                      Trigger and monitor Jenkins build
```

Add examples:

```text
  buildgit push --prior-jobs 5     # Push + show last 5 builds before monitoring
  buildgit push --prior-jobs 0     # Push + suppress prior-jobs display
  buildgit status -f --prior-jobs 5  # Follow with last 5 builds shown first
```

### 10. Edge Cases

- **No builds at all:** `_display_n_prior_builds()` returns 0 builds; omit the entire prior-jobs block (header and footer too).
- **`--prior-jobs 0`:** No prior-jobs block. Estimate line is still printed.
- **Current build in-progress at startup (`status -f`):** `_display_n_prior_builds()` skips in-progress builds automatically; they are never shown as prior jobs.
- **`--no-follow` with `--prior-jobs`:** `push --no-follow` and `build --no-follow` skip all monitoring; `--prior-jobs` is ignored (no monitoring preamble runs).

## Acceptance Criteria

1. `buildgit push` (no flags) prints prior-jobs block (3 builds) and estimate before build monitoring begins.
2. `buildgit build` (no flags) prints prior-jobs block (3 builds) and estimate before build monitoring begins.
3. `buildgit status -f` (no flags) prints prior-jobs block (3 builds) and estimate before the follow loop.
4. Prior-jobs block format: `[timestamp] ℹ Prior N Jobs` header via `log_info`, followed by one-line builds oldest-first (plain stdout). No footer line.
5. Estimate line uses `log_info` format: `Estimated build time = Xm Ys`.
6. When no prior successful build exists, estimate shows `Estimated build time = unknown`.
7. `--prior-jobs 5` shows 5 prior builds.
8. `--prior-jobs 0` suppresses the prior-jobs block but still shows the estimate.
9. Default behavior (no `--prior-jobs` flag) shows 3 prior builds.
10. Prior-jobs lines are always one-line format (default or `--format` string).
11. Prior-jobs builds are oldest-first.
12. In-progress builds are excluded from the prior-jobs count.
13. When fewer than N completed builds exist, available builds are shown; header still says `Prior N Jobs`.
14. When zero completed builds exist, the prior-jobs block is omitted entirely.
15. `--prior-jobs -1` exits 1 with error message.
16. `--prior-jobs foo` exits 1 with error message.
17. `--prior-jobs` with no value exits 1 with error message.
18. `buildgit status --json` silently ignores `--prior-jobs`; JSON output is unaffected.
19. `--no-tests` suppresses test API calls for prior-jobs lines.
20. `--format` applies to prior-jobs lines.
21. `push --no-follow` skips the monitoring preamble entirely.
22. Output appears on both TTY and non-TTY.
23. Help text updated for `push`, `build`, and `status` commands.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `preamble_default_three_jobs` | Default `push` shows 3 prior builds in preamble |
| `preamble_estimate_always_shown` | Estimate line appears even with `--prior-jobs 0` |
| `preamble_prior_jobs_header` | Prior-jobs block has correct `log_info` header `Prior N Jobs` and no footer |
| `preamble_oldest_first` | Prior-jobs lines appear oldest-first |
| `preamble_skip_in_progress` | In-progress build excluded from prior-jobs count |
| `preamble_fewer_than_n` | Fewer builds than N available: show all, header says `Prior N Jobs` |
| `preamble_zero_builds_no_block` | No completed builds: prior-jobs block omitted entirely |
| `preamble_estimate_known` | When last successful build exists, estimate shows formatted duration |
| `preamble_estimate_unknown` | When no last successful build, estimate shows `unknown` |
| `preamble_prior_jobs_zero` | `--prior-jobs 0`: no prior-jobs block, estimate still shown |
| `preamble_prior_jobs_five` | `--prior-jobs 5`: shows 5 prior builds |
| `preamble_prior_jobs_default` | No `--prior-jobs` flag defaults to 3 |
| `preamble_no_tests` | `--no-tests` skips test fetches for prior-jobs lines |
| `preamble_format_applied` | `--format` applies to prior-jobs lines |
| `prior_jobs_validation_negative` | `--prior-jobs -1` exits 1 with error |
| `prior_jobs_validation_non_integer` | `--prior-jobs foo` exits 1 with error |
| `prior_jobs_validation_no_value` | `--prior-jobs` with no value exits 1 with error |
| `preamble_build_command` | `buildgit build` shows preamble |
| `preamble_status_f_command` | `buildgit status -f` shows preamble |
| `preamble_push_no_follow_skipped` | `push --no-follow` does not show preamble |
| `preamble_json_ignores_prior_jobs` | `buildgit status --json --prior-jobs 3` ignores prior-jobs, JSON unchanged |
| `preamble_non_tty` | Estimate and prior-jobs appear on non-TTY stdout |

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
