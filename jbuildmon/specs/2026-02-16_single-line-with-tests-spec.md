# Feature: Test Results in Line Mode Output

- **Date:** `2026-02-16T08:56:32-07:00`
- **References:** `specs/todo/single-line-with-tests.md`
- **Supersedes:** none
- **State:** `DRAFT`

## Overview

Add test result counts to `buildgit status --line` output and change the completion wording from `completed in` to `Took`. Test data is fetched by default but can be suppressed with `--no-tests` for speed-sensitive use cases (especially `--line=N` which would otherwise make N extra API calls).

## Current Output

```text
SUCCESS     Job ralph1 #178 completed in 4m 39s on 2026-02-15 (13 hours ago)
```

## New Output

With test data (default):
```text
SUCCESS     Job ralph1 #178 Tests=557/0/0 Took 4m 39s on 2026-02-15 (13 hours ago)
```

With unknown test data (API 404 or `--no-tests`):
```text
SUCCESS     Job ralph1 #178 Tests=?/?/? Took 4m 39s on 2026-02-15 (13 hours ago)
```

In-progress build (no test data available yet):
```text
IN_PROGRESS Job ralph1 #179 Tests=?/?/? running for 2m 10s (started 2026-02-16 08:50)
```

## Specification

### 1. Test Results Field Format

Insert a `Tests=` field after the build number and before the duration/timing section:

```text
Tests=<passed>/<failed>/<skipped>
```

- `<passed>`: number of passing tests
- `<failed>`: number of failing tests
- `<skipped>`: number of skipped tests

When test data is unavailable (no test report, in-progress build, or `--no-tests`):

```text
Tests=?/?/?
```

### 2. Wording Change: `Took` Replaces `completed in`

The completion phrase changes from `completed in` to `Took` for completed builds:

Before:
```text
SUCCESS     Job ralph1 #178 completed in 4m 39s on 2026-02-15 (13 hours ago)
```

After:
```text
SUCCESS     Job ralph1 #178 Tests=557/0/0 Took 4m 39s on 2026-02-15 (13 hours ago)
```

The in-progress format (`running for ... (started ...)`) is unchanged aside from the inserted `Tests=?/?/?` field.

### 3. Test Results Coloring

The `Tests=<passed>/<failed>/<skipped>` field is colored based on the failed count:

| Condition | Color | Example |
|-----------|-------|---------|
| `failed == 0` (all pass) | Green (`COLOR_GREEN`) | `Tests=557/0/0` |
| `failed > 0` (any failures) | Yellow (`COLOR_YELLOW`) | `Tests=376/1/30` |
| Unknown (`?/?/?`) | No color (default text) | `Tests=?/?/?` |

Color wraps only the `Tests=N/N/N` token, not surrounding text. Colors are suppressed when stdout is not a TTY (existing `_init_colors` mechanism).

### 4. New `--no-tests` Flag on `status`

`buildgit status` gains a new option:

```text
--no-tests    Skip fetching test report data (show Tests=?/?/?)
```

This applies only to line mode. When `--no-tests` is specified:
- No `testReport/api/json` calls are made
- All lines show `Tests=?/?/?` with no color
- This is useful for `--line=N` where N extra API calls would slow things down

When `--no-tests` is used with full status mode (`--all` or TTY default), it is ignored — full mode already has its own test display logic.

### 5. Option Compatibility

| Option | Compatible with `--no-tests` | Behavior |
|--------|------------------------------|----------|
| `--line` / `-l` | Yes | Skip test report fetch |
| `--line=N` | Yes | Skip test report fetch for all N builds |
| `--all` / `-a` | Ignored | Full mode not affected |
| `--json` | Ignored | JSON mode not affected |
| `-f` / `--follow` | Ignored | Follow mode not affected |

### 6. API Call Changes

Without `--no-tests`, line mode now requires one additional Jenkins API call per build:
- `testReport/api/json` to get test counts

With `--no-tests`, no additional API calls are made (same as current behavior).

### 7. Output Format — Full Specification

Completed build with tests:
```text
<RESULT_padded> Job <job_name> #<build_number> <tests_field> Took <duration> on <date> (<relative_time>)
```

Completed build without tests:
```text
<RESULT_padded> Job <job_name> #<build_number> Tests=?/?/? Took <duration> on <date> (<relative_time>)
```

In-progress build:
```text
IN_PROGRESS Job <job_name> #<build_number> Tests=?/?/? running for <elapsed> (started <date> <time>)
```

### 8. Extracting Test Counts from Jenkins API

The `testReport/api/json` response includes:
- `totalCount` (or `passCount + failCount + skipCount`)
- `passCount`
- `failCount`
- `skipCount`

Reuse the existing `fetch_test_results` function. Extract counts with jq:
```bash
passed=$(echo "$test_json" | jq -r '.passCount // 0')
failed=$(echo "$test_json" | jq -r '.failCount // 0')
skipped=$(echo "$test_json" | jq -r '.skipCount // 0')
```

### 9. Help Text Update

Update `show_usage()`:

```text
Commands:
  status [build#] [-f|--follow] [--json] [--line[=N]] [--all] [--no-tests]
                      Display Jenkins build status (latest or specific build)
                      Default: full output on TTY, one-line on pipe/redirect
```

Add/update examples:

```text
  buildgit status --line              # One-line status with test results
  buildgit status --line=10 --no-tests  # Last 10 builds, skip test fetch
```

### 10. Consistency Rule

Per `CLAUDE.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must be consistent. This feature only affects the line mode output path. Full status, follow, and JSON modes are unchanged.

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Update `_parse_status_options()` to parse `--no-tests`. Update `_status_line_for_build_json()` to fetch test results (unless `--no-tests`), format the `Tests=` field with color, and change `completed in` to `Took`. Pass `--no-tests` state to `_status_line_check()`. Update `show_usage()`. |
| `test/buildgit_status.bats` | Add tests for test results in line output, `Tests=?/?/?` placeholder, `--no-tests` flag, test color (green vs yellow), wording change to `Took` |

## Acceptance Criteria

1. `buildgit status --line` output includes `Tests=<passed>/<failed>/<skipped>` after the build number.
2. Test counts are extracted from the Jenkins test report API.
3. When no test report exists, `Tests=?/?/?` is shown.
4. In-progress builds show `Tests=?/?/?`.
5. `Tests=N/N/N` is green when failed=0, yellow when failed>0, uncolored when unknown.
6. Colors are suppressed when stdout is not a TTY.
7. Completed builds use `Took` instead of `completed in`.
8. `--no-tests` suppresses test report API calls and shows `Tests=?/?/?`.
9. `--no-tests` is ignored in full status, JSON, and follow modes.
10. `--line=N` with `--no-tests` does not make any testReport API calls.
11. Help text documents `--no-tests`.
12. All existing tests continue to pass.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `status_line_shows_test_results` | `--line` output includes `Tests=N/N/N` with correct counts from mock test report |
| `status_line_tests_unknown` | When test report API returns 404, output shows `Tests=?/?/?` |
| `status_line_tests_in_progress` | In-progress build shows `Tests=?/?/?` |
| `status_line_tests_green` | When failed=0, `Tests=` field uses green color codes |
| `status_line_tests_yellow` | When failed>0, `Tests=` field uses yellow color codes |
| `status_line_tests_unknown_no_color` | `Tests=?/?/?` has no color codes |
| `status_line_took_wording` | Completed build output contains `Took` instead of `completed in` |
| `status_line_no_tests_flag` | `--no-tests` shows `Tests=?/?/?` without making testReport API call |
| `status_line_no_tests_with_count` | `--line=3 --no-tests` shows placeholder for all 3 lines |
