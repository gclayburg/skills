## Hierarchical Test Results with Downstream Aggregation

- **Date:** `2026-03-16T14:44:03-0600`
- **References:** `specs/done-reports/test-fail-need-results-still.md`
- **Supersedes:** none
- **Plan:** `specs/2026-03-16_test-fail-need-results-still-plan.md`
- **Chunked:** `true`
- **State:** `IMPLEMENTED`

## Overview

When a build has downstream component builds, buildgit should display a hierarchical test results breakdown showing the parent job and each child job's test results individually, with a Totals summary row. This replaces the current single-line test results display for multi-component pipelines. For jobs without downstream builds, the current single-line format is preserved unchanged.

This also fixes the bug where failed builds show `Tests=?/?/?` because the parent testReport API returns 404 when test-reporting stages were skipped due to earlier failures.

## Problem Statement

### Current Behavior

- **Build #75 (SUCCESS):** Parent-level test results only → `Tests=19/0/0`. Downstream builds (phandlemono-handle: 64 pass, phandlemono-signalboot: 15 pass) are not shown.
- **Build #73 (FAILURE):** Parent testReport returns 404 → `Tests=?/?/?` and `(no test results available)`. Downstream builds have results (handle: 83 pass, signalboot: 14 pass/1 fail) but are never queried.

### Root Cause

`fetch_test_results()` only queries the parent job's `testReport` endpoint. It never queries downstream builds. When the parent testReport returns 404 (because test-aggregating stages were skipped on failure), no test data is shown at all.

### Desired Behavior

For builds with downstream jobs, show a hierarchical breakdown:

**All tests passing (build #75):**
```
=== Test Results ===
phandlemono-IT      Total: 19 | Passed: 19 | Failed: 0 | Skipped: 0
  Build SignalBoot  Total: 15 | Passed: 15 | Failed: 0 | Skipped: 0
  Build Handle      Total: 64 | Passed: 64 | Failed: 0 | Skipped: 0
--------------------
Totals                    98 | Passed: 98 | Failed: 0 | Skipped: 0
====================
```

**Build with test failure (build #73):**
```
=== Test Results ===
phandlemono-IT       Total: ? | Passed:  ? | Failed: ? | Skipped: ?
  Build SignalBoot  Total: 15 | Passed: 14 | Failed: 1 | Skipped: 0
  Build Handle      Total: 83 | Passed: 83 | Failed: 0 | Skipped: 0
--------------------
Totals                    98 | Passed: 97 | Failed: 1 | Skipped: 0
====================
```

**One-line mode uses Totals numbers:**
```
SUCCESS     #75 id=c7c0c96 Tests=98/0/0 Took 5m 41s on ...
FAILURE     #73 id=a916068 Tests=97/1/0 Took 4m 9s on ...
```

## Specification

### 1. Downstream Build Detection

#### 1.1 Detect Downstream Builds

Use the existing `detect_all_downstream_builds()` function from `failure_analysis.sh` to identify downstream builds from console output. This parses `Starting building: <job> #<number>` patterns.

#### 1.2 Map Downstream Builds to Stage Names

Each downstream build is triggered from within a pipeline stage. The stage name provides the display label for the hierarchy. Use the existing stage data to map downstream job names to their triggering stage names (e.g., `phandlemono-signalboot` → `Build SignalBoot`, `phandlemono-handle` → `Build Handle`).

#### 1.3 Recursive Detection

If a downstream build itself triggers further downstream builds, recursively detect and include those with additional indentation (2 spaces per level). Follow the same recursion pattern as `_display_nested_downstream()` in `output_render.sh`.

### 2. Test Result Collection

#### 2.1 Always Collect from All Levels

For every build (success or failure), collect test results from:
1. The parent job's `testReport` API
2. Each downstream build's `testReport` API

This applies to ALL builds, not just failures. The hierarchical display shows the full picture.

#### 2.2 Handling Missing Test Reports

When a job's `testReport` API returns 404:
- Display `?` for all counts on that job's line (Total, Passed, Failed, Skipped)
- For Totals computation, treat `?` as 0
- Use white/default color for that line

When a job's `testReport` API returns a communication error (exit code 2):
- Show the communication error warning as today
- Do not attempt to aggregate anything from that job

### 3. Hierarchical Display Format (`--all` mode)

#### 3.1 Layout

```
=== Test Results ===
<parent-job>      Total: <N> | Passed: <N> | Failed: <N> | Skipped: <N>
  <stage-name-1>  Total: <N> | Passed: <N> | Failed: <N> | Skipped: <N>
  <stage-name-2>  Total: <N> | Passed: <N> | Failed: <N> | Skipped: <N>
--------------------
Totals                  <sum> | Passed: <sum> | Failed: <sum> | Skipped: <sum>
====================
```

- Parent job is shown first at indent level 0
- Child builds indented 2 spaces, using the triggering stage name as label
- Nested children (grandchildren) indented 4 spaces, etc.
- Numbers are right-aligned across all lines
- `--------------------` separator before the Totals row
- No line length limit

#### 3.2 No Downstream Builds

When the build has no downstream builds, preserve the current single-line format:
```
=== Test Results ===
  Total: 19 | Passed: 19 | Failed: 0 | Skipped: 0
====================
```

No Totals row is needed for single-job builds.

#### 3.3 Color Rules (per line)

- **Green:** All tests passed on that line (failCount == 0 and test data available)
- **Yellow:** Any test failures on that line (failCount > 0)
- **White/default:** No test data available (all values are `?`)

The `=== Test Results ===` header and `====================` footer color follow the Totals row color (or the single line color if no downstream builds).

#### 3.4 Failed Test Details

The `FAILED TESTS:` detail section continues to appear after the hierarchy when any job has test failures. Failed tests from all jobs (parent + downstream) are shown together, following existing formatting rules (truncation, age indicators, etc.).

### 4. One-Line Mode (`buildgit status`, `buildgit status --line`)

#### 4.1 Use Totals for Test Counts

The `Tests=pass/fail/skip` numbers in one-line mode must reflect the **Totals** row — the sum across the parent and all downstream builds (treating `?` as 0).

**Current (build #75):** `Tests=19/0/0` (parent only)
**New (build #75):** `Tests=98/0/0` (parent 19 + signalboot 15 + handle 64)

**Current (build #73):** `Tests=?/?/?`
**New (build #73):** `Tests=97/1/0` (handle 83 + signalboot 14/1 + parent ?)

#### 4.2 Extra API Calls

One-line mode currently makes one API call for test results (parent testReport). With this change, builds with downstream jobs will require:
1. Console text fetch (to detect downstream builds)
2. One testReport fetch per downstream build

To minimize latency, only fetch downstream test results when the build has downstream builds (detected from console text). For builds without downstream builds, behavior is unchanged (single API call).

### 5. JSON Mode (`buildgit status --json`)

#### 5.1 Hierarchical JSON Structure

When downstream builds exist, the `test_results` field gains a hierarchical structure:

```json
{
  "test_results": {
    "total": 98,
    "passed": 97,
    "failed": 1,
    "skipped": 0,
    "failed_tests": [...],
    "breakdown": [
      {
        "job": "phandlemono-IT",
        "build_number": 73,
        "total": null,
        "passed": null,
        "failed": null,
        "skipped": null
      },
      {
        "job": "phandlemono-signalboot",
        "stage": "Build SignalBoot",
        "build_number": 63,
        "total": 15,
        "passed": 14,
        "failed": 1,
        "skipped": 0,
        "failed_tests": [...]
      },
      {
        "job": "phandlemono-handle",
        "stage": "Build Handle",
        "build_number": 66,
        "total": 83,
        "passed": 83,
        "failed": 0,
        "skipped": 0,
        "failed_tests": []
      }
    ]
  }
}
```

- Top-level `total/passed/failed/skipped` = Totals (sums, `?`→0)
- `breakdown` array contains per-job detail
- `null` values represent `?` (no test data available)
- `failed_tests` at top level = concatenation from all jobs
- `breakdown` field only present when downstream builds exist

#### 5.2 No Downstream Builds

When there are no downstream builds, the `test_results` structure is unchanged from today (no `breakdown` field).

### 6. Monitoring Mode (`buildgit push`, `buildgit build`, `buildgit status -f`)

Apply the same hierarchical display at build completion. The console output is already available in monitoring mode, so downstream detection requires no extra API calls beyond the downstream testReport fetches.

### 7. Consistency Rules

Per `CLAUDE.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must always be consistent:
- All modes collect test results from parent + downstream builds
- Totals match across all modes for the same build
- JSON `breakdown` order matches human-readable line order

### 8. Communication Error Handling

If the parent testReport returns a communication error (exit code 2), show the communication error as today — do not attempt downstream collection. Communication errors indicate infrastructure problems, not missing test data.

If a downstream testReport returns a communication error, treat that downstream build's test data as `?` (same as 404) and continue with remaining builds.

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jenkins-common/api_test_results.sh` | Add `fetch_all_test_results()` function that collects parent + downstream test results. Add `aggregate_test_results()` to compute Totals. Add `display_hierarchical_test_results()` for the multi-line display. |
| `lib/jenkins-common/output_render.sh` | Update `_display_failure_diagnostics()` and `display_success_output()` to call hierarchical test results display when downstream builds exist. |
| `lib/buildgit/status_parsing_and_format.sh` | Update `_status_line_for_build_json()` to use Totals for `Tests=` when downstream builds exist. |
| `skill/buildgit/scripts/buildgit` | Update `_handle_build_completion()` to use hierarchical test results display. |

## Acceptance Criteria

1. `buildgit --job phandlemono-IT status 73` shows `Tests=97/1/0` (aggregated Totals, not `?/?/?`)
2. `buildgit --job phandlemono-IT status 73 --all` shows hierarchical test results with parent (`?` values), Build SignalBoot (14/1/0), Build Handle (83/0/0), and Totals row
3. `buildgit --job phandlemono-IT status 73 --json` includes `test_results` with `breakdown` array and correct Totals
4. `buildgit --job phandlemono-IT status 75` shows `Tests=98/0/0` (aggregated Totals: parent 19 + downstream 79)
5. `buildgit --job phandlemono-IT status 75 --all` shows hierarchical breakdown with all green lines
6. `buildgit status` for `ralph1/main` (no downstream builds) preserves current single-line format unchanged
7. Numbers are right-aligned across all hierarchy lines
8. Color: green for all-pass lines, yellow for failure lines, white for `?` lines
9. One-line mode Totals are consistent with `--all` Totals
10. Communication errors (exit code 2) are not masked by downstream collection
11. All existing tests continue to pass

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| No downstream builds → single-line display | Mock build with no downstream builds; verify current single-line format preserved, no Totals row |
| Hierarchical display with all passing | Mock parent + 2 downstream builds all passing; verify hierarchy format, right-alignment, Totals, green color |
| Hierarchical display with failure | Mock parent 404 + 1 downstream passing + 1 downstream failing; verify `?` on parent line, correct Totals, yellow on failure line, white on parent line |
| Totals math treats `?` as 0 | Mock parent 404 + downstream (10 pass, 1 fail, 2 skip); verify Totals = 10/1/2 |
| One-line mode uses Totals | Mock parent + 2 downstream builds; verify `Tests=` shows sum of all builds |
| JSON breakdown present for multi-job | Mock parent + downstream; verify `breakdown` array in JSON output |
| JSON no breakdown for single job | Mock build without downstream; verify no `breakdown` field |
| Failed test details from downstream | Mock downstream with failed tests; verify `FAILED TESTS:` section includes them |
| Right-alignment of numbers | Mock builds with varying number widths; verify alignment |
| Downstream communication error → `?` | Mock one downstream returning exit code 2; verify that build shown as `?`, other builds still aggregated |
| Nested downstream (3 levels) | Mock parent → child → grandchild; verify 3-level indentation |

### Manual Test Plan

See [2026-03-16_test-fail-need-results-still-test-plan.md](2026-03-16_test-fail-need-results-still-test-plan.md)

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
