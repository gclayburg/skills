# Feature: Prior Jobs Display for Snapshot Status

- **Date:** `2026-02-27T00:00:00-0700`
- **References:** `specs/done-reports/add-prior-jobs-display-to-snapshot-status.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Overview

Extend the `--prior-jobs <N>` option (introduced in `2026-02-27_estimated-build-time-and-old-jobs-spec.md` for monitoring commands) to also work with snapshot `buildgit status`. The prior-jobs block appears near the top of the status output, before the full status of the target build. Default is N=3 (same as monitoring). No estimate line is shown for snapshot status.

## Problem Statement

Snapshot `buildgit status` shows the full details of one build but gives no context on recent build history. Adding a default prior-jobs block surfaces pass/fail trends at a glance without requiring a separate `-n` invocation.

## Reference Examples

```
./buildgit status --prior-jobs 5 201
./buildgit status --prior-jobs 4
./buildgit status -n 5 --prior-jobs 3
```

## Specification

### 1. Output Format

The prior-jobs block for snapshot status is identical in format to the monitoring command preamble (from `2026-02-27_estimated-build-time-and-old-jobs-spec.md`):

```
[HH:MM:SS] ℹ Prior N Jobs
<one-line build>           ← oldest first
<one-line build>
...
```

- Header via `log_info`: `Prior N Jobs` — uses the requested N regardless of builds available.
- No footer line.
- Build lines are plain stdout (no timestamp prefix), one-line format.
- **No estimate line** — the estimate is only shown for monitoring commands where a new build is about to run.
- Builds are displayed **oldest first**.
- In-progress builds are excluded and do not count toward N.
- If fewer than N completed builds exist before the target, show all available.
- If zero completed builds exist before the target, omit the prior-jobs block entirely (no header either).

### 2. Placement in Snapshot Output Flow

The prior-jobs block appears **before** the full status output of the target build.

#### Simple snapshot: `buildgit status [--prior-jobs N] [build#]`

```
[HH:MM:SS] ℹ Prior 3 Jobs
SUCCESS     #53 id=abc1234 Tests=19/0/0 Took 5m 38s on 2026-02-22T22:37:21-0700 (4 days ago)
SUCCESS     #54 id=def5678 Tests=19/0/0 Took 5m 40s on 2026-02-23T00:10:00-0700 (4 days ago)
SUCCESS     #55 id=6685a31 Tests=19/0/0 Took 6m 39s on 2026-02-24T10:14:10-0700 (3 days ago)
──────────────────────────────────────────
 Build     ralph1 #56
 ...
[full status output for build #56]
```

#### Specific build number: `buildgit status --prior-jobs 5 201`

Prior jobs are the 5 most recently completed builds with build number **less than** 201 (i.e., #196–#200, oldest first):

```
[HH:MM:SS] ℹ Prior 5 Jobs
SUCCESS     #196 ...
SUCCESS     #197 ...
FAILURE     #198 ...
SUCCESS     #199 ...
SUCCESS     #200 ...
[full status output for build #201]
```

#### With `-n`: `buildgit status -n 5 --prior-jobs 3`

`-n` and `--prior-jobs` are independent. `-n 5` shows full output for the 5 most recent completed builds, oldest first. `--prior-jobs 3` attaches a prior-jobs block to the **most recent** build only (the last one printed), appearing immediately before that build's full output:

```
[full output for build #52 (oldest of the 5)]
[full output for build #53]
[full output for build #54]
[full output for build #55]
[HH:MM:SS] ℹ Prior 3 Jobs
SUCCESS     #53 ...
SUCCESS     #54 ...
SUCCESS     #55 ...
[full output for build #56 (most recent)]
```

Note: builds #53–#55 appear both in the `-n` full output above and as one-line entries in the prior-jobs block. This duplication is intentional — the two options are independent.

#### With `--line`: `buildgit status --line --prior-jobs 3`

Prior-jobs block appears before the one-line status output:

```
[HH:MM:SS] ℹ Prior 3 Jobs
SUCCESS     #53 ...
SUCCESS     #54 ...
SUCCESS     #55 ...
SUCCESS     #56 id=6685a31 Tests=19/0/0 Took 6m 39s on ...    ← main status line
```

#### With `--json`

`--prior-jobs` is silently ignored when `--json` is active. JSON output is not mixed with plain-text prior-jobs lines.

### 3. Which Builds Are "Prior"

"Prior N builds" means the N most recently completed builds with a build number strictly less than the target build number. In-progress builds are excluded. If the target build is the latest, this is equivalent to the N most recently completed builds before it.

For `status` with no explicit build number (latest build): prior jobs are the N most recently completed builds before the latest.

For `status -n 5 --prior-jobs 3`: the target build is the most recent of the 5 (`-n` builds), and prior jobs are the 3 most recently completed builds before that most-recent build.

### 4. Default Behavior Change

`buildgit status` (no flags) now shows the prior-jobs block (N=3) before the full status output. This is an intentional change to the default output.

To suppress: `buildgit status --prior-jobs 0`.

### 5. `--prior-jobs <N>` for Snapshot Status

`--prior-jobs <N>` is now valid on snapshot `buildgit status` (previously it was silently ignored).

**Default:** `3`

**Validation:** same rules as monitoring commands:
- `N = 0`: valid — no prior-jobs block shown.
- Negative or non-integer → error: `"--prior-jobs value must be a non-negative integer"`, exit 1.
- Missing value → error: `"--prior-jobs requires a value"`, exit 1.

### 6. `--no-tests` Interaction

`--no-tests` suppresses test API calls for prior-jobs lines (same as monitoring). Prior-job lines show `?/?/?` for the test count.

### 7. `--format` Interaction

`--format <fmt>` applies to prior-jobs lines in snapshot status (same as monitoring). The format string controls both the main `--line` output and the prior-jobs lines.

### 8. Non-TTY Behavior

Prior-jobs block appears on both TTY and non-TTY, as plain text.

### 9. Option Parsing Changes

**`_parse_status_options()`:** `--prior-jobs <N>` is now active in **all** status modes (snapshot and follow), not just follow mode. Remove the "silently ignored for snapshot" restriction from `2026-02-27_estimated-build-time-and-old-jobs-spec.md`.

### 10. Implementation Approach

Snapshot status flows through `cmd_status()`. The prior-jobs display is injected before `_display_completed_build()` or the equivalent snapshot display call:

1. For simple snapshot (`status` / `status <build#>`): call `_display_monitoring_preamble_snapshot()` (or reuse `_display_monitoring_preamble()` without the estimate step) before the main status display.
2. For `-n` snapshot: call the prior-jobs display only for the last (most recent) build in the `-n` loop, before printing that build's full output.

The prior-jobs block for snapshot reuses `_display_n_prior_builds()` in line mode, constrained to build numbers less than the target build number.

Consider adding a parameter to `_display_n_prior_builds()` (or a wrapper) that accepts a `max_build_number` to limit which builds are fetched, so it correctly shows only builds before the target.

### 11. Help Text Updates

Update the applicable commands table in `2026-02-27_estimated-build-time-and-old-jobs-spec.md`:

| Command | Shows estimate | Shows prior jobs | Supports `--prior-jobs` |
|---------|---------------|-----------------|------------------------|
| `buildgit status` (snapshot) | No | Yes (default 3) | Yes |
| `buildgit status <build#>` | No | Yes (default 3) | Yes |
| `buildgit status -n <N>` | No | Yes (default 3, attached to most recent build) | Yes |
| `buildgit status --json` | No | No | Silently ignored |

Update `show_usage()`:

```text
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests] [--format <fmt>] [--prior-jobs <N>]
                      Display Jenkins build status (latest or specific build)
                      Default: full output on TTY, one-line on pipe/redirect
```

Add examples:

```text
  buildgit status --prior-jobs 5      # Latest build + 5 prior one-line builds
  buildgit status --prior-jobs 5 201  # Build #201 + 5 prior one-line builds
  buildgit status --prior-jobs 0      # Latest build, suppress prior-jobs display
```

## Acceptance Criteria

1. `buildgit status` (no flags) shows prior-jobs block (N=3) before full status output.
2. `buildgit status --prior-jobs 5` shows 5 prior one-line builds before status output.
3. `buildgit status --prior-jobs 5 201` shows builds #196–#200 as prior-jobs before build #201 full output.
4. `buildgit status -n 5 --prior-jobs 3` shows prior-jobs block only before the most recent build's full output; other 4 builds show no prior-jobs block.
5. `buildgit status --line --prior-jobs 3` shows prior-jobs block before the one-line status.
6. `buildgit status --json --prior-jobs 3` silently ignores `--prior-jobs`; JSON output is unaffected.
7. `buildgit status --prior-jobs 0` suppresses prior-jobs block.
8. Prior-jobs builds are strictly before the target build number.
9. In-progress builds are excluded from prior-jobs count.
10. Header `[timestamp] ℹ Prior N Jobs` uses the requested N.
11. If zero completed prior builds exist, block is omitted entirely (no header).
12. `--no-tests` suppresses test fetches for prior-jobs lines.
13. `--format` applies to prior-jobs lines.
14. `--prior-jobs -1` exits 1 with error.
15. `--prior-jobs foo` exits 1 with error.
16. `--prior-jobs` with no value exits 1 with error.
17. Help text updated.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `snapshot_default_prior_jobs` | `status` default shows 3 prior builds before full output |
| `snapshot_prior_jobs_five` | `--prior-jobs 5` shows 5 prior builds |
| `snapshot_prior_jobs_zero` | `--prior-jobs 0` suppresses prior-jobs block |
| `snapshot_prior_jobs_specific_build` | `status --prior-jobs 5 201` shows builds #196–#200 |
| `snapshot_prior_jobs_before_target` | Prior builds are strictly less than target build number |
| `snapshot_n_and_prior_jobs_independent` | `-n 5 --prior-jobs 3` shows prior-jobs only before most recent build |
| `snapshot_line_with_prior_jobs` | `--line --prior-jobs 3` shows prior-jobs block then one-liner |
| `snapshot_json_ignores_prior_jobs` | `--json --prior-jobs 3` ignores prior-jobs, JSON unchanged |
| `snapshot_prior_jobs_header_format` | Header is `log_info` format `Prior N Jobs` |
| `snapshot_prior_jobs_oldest_first` | Prior-jobs lines are oldest-first |
| `snapshot_prior_jobs_skip_in_progress` | In-progress builds excluded from prior-jobs |
| `snapshot_prior_jobs_fewer_than_n` | Fewer than N prior builds: shows all, header says N |
| `snapshot_prior_jobs_zero_builds` | No prior builds: block omitted entirely including header |
| `snapshot_prior_jobs_no_tests` | `--no-tests` skips test fetch for prior-jobs lines |
| `snapshot_prior_jobs_format` | `--format` applies to prior-jobs lines |
| `snapshot_prior_jobs_validation_negative` | `--prior-jobs -1` exits 1 with error |
| `snapshot_prior_jobs_validation_non_integer` | `--prior-jobs foo` exits 1 with error |
| `snapshot_prior_jobs_validation_no_value` | `--prior-jobs` with no value exits 1 with error |
| `snapshot_no_estimate_line` | No `Estimated build time` line in snapshot output |

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
