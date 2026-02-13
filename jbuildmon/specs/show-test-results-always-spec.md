# Show Test Results for All Completed Builds
Date: 2026-02-13T15:04:27-07:00
References: specs/done-reports/features-show-test-results-always.md
Supersedes: none

## Overview

Test results are currently only displayed when a build fails (FAILURE/UNSTABLE). This spec extends the `=== Test Results ===` section to appear for all completed builds — including SUCCESS — across all output modes: snapshot (`buildgit status`), monitoring (`buildgit push`, `buildgit build`, `buildgit status -f`), and JSON (`buildgit status --json`).

## Problem Statement

### Current Behavior

- **FAILURE/UNSTABLE builds:** `_display_failure_diagnostics()` fetches the test report and calls `display_test_results()`, showing the summary and any failed test details.
- **SUCCESS builds:** No test results are shown in any mode. `display_success_output()` and `_handle_build_completion()` (for `result == "SUCCESS"`) skip test results entirely.
- **JSON output:** `test_results` is only added when `is_failed == "true"` (line ~2784 of `jenkins-common.sh`).
- **No test report:** When the Jenkins test report API returns 404, the section is silently omitted.

### Desired Behavior

After any build completes, the Test Results section should appear:

```
=== Test Results ===
  Total: 407 | Passed: 407 | Failed: 0 | Skipped: 30
====================
```

- Green when all tests pass, yellow when there are failures.
- When no test report is available, show a placeholder instead of omitting entirely.

## Specification

### 1. Test Results for SUCCESS Builds

#### 1.1 Snapshot Mode (`buildgit status`)

`display_success_output()` must fetch and display test results after the stages list and before the `Finished: SUCCESS` line.

Current flow in `display_success_output()`:
```
stages → Finished: SUCCESS → Duration
```

New flow:
```
stages → Test Results → Finished: SUCCESS → Duration
```

#### 1.2 Monitoring Mode (`buildgit push`, `buildgit build`, `buildgit status -f`)

`_handle_build_completion()` currently only calls `_display_failure_diagnostics()` for non-SUCCESS results. For SUCCESS results, test results must be fetched and displayed before the `Finished:` line.

Current flow for SUCCESS in `_handle_build_completion()`:
```
(nothing) → Finished: SUCCESS → Duration
```

New flow:
```
Test Results → Finished: SUCCESS → Duration
```

#### 1.3 JSON Mode (`buildgit status --json`)

`output_json()` must add the `test_results` field for all completed builds, not just failed ones. The `test_results` field moves from inside the `if is_failed` block to a standalone block that runs for any completed build.

### 2. Color Changes

#### 2.1 Green for All-Pass

When there are zero test failures, the entire Test Results section (header, summary line, and closing bar) must be green:

```
=== Test Results ===          ← green
  Total: 407 | Passed: 407 | Failed: 0 | Skipped: 30   ← green
====================          ← green
```

#### 2.2 Yellow for Failures (Unchanged)

When there are test failures, the existing yellow color is preserved:

```
=== Test Results ===          ← yellow
  Total: 407 | Passed: 376 | Failed: 1 | Skipped: 30   ← yellow

  FAILED TESTS:               ← red
  ✗ test_helper.bats::...     ← (existing format unchanged)
====================          ← yellow
```

#### 2.3 Implementation

Modify `display_test_results()` to select color based on `failCount`:
- `failCount == 0` → use `COLOR_GREEN` for header, summary, and closing bar
- `failCount > 0` → use `COLOR_YELLOW` (current behavior)

### 3. No Test Report Placeholder

When `fetch_test_results()` returns empty (API 404 — no junit results published), display a placeholder section instead of omitting the section entirely.

#### 3.1 Human-Readable Output

```
=== Test Results ===
  (no test results available)
====================
```

Use dim/default color (no green or yellow) for this placeholder.

#### 3.2 JSON Output

When no test report is available, include the field with a sentinel value:

```json
{
  "test_results": null
}
```

This distinguishes "no test report" (`null`) from the field being absent (which would indicate the build is still running or the feature is unavailable).

### 4. Closing Bar

The `====================` closing bar must always be present to visually delimit the section. This applies to all cases:
- All tests pass (green bar)
- Test failures (yellow bar, already present)
- No test report placeholder (default color bar)

### 5. Failed Test Details (No Change)

The `FAILED TESTS:` detail section (individual test names, errors, stack traces) continues to appear only when `failCount > 0`. No changes to the detail display logic, truncation rules, or `age` indicator.

### 6. Output Ordering

#### 6.1 SUCCESS Snapshot (`buildgit status`)

```
╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝
Job/Build/Status/Trigger/Commit/Started
=== Build Info ===
  ...
==================
Console: ...

[stages list]

=== Test Results ===                 ← NEW
  Total: N | Passed: N | ...
====================

Finished: SUCCESS
Duration: Xm Ys
```

#### 6.2 SUCCESS Monitoring (`buildgit push`, `buildgit build`)

```
[HH:MM:SS] ℹ   Stage: ... (Xs)
[HH:MM:SS] ℹ   Stage: ... (Xs)

=== Test Results ===                 ← NEW
  Total: N | Passed: N | ...
====================

Finished: SUCCESS
Duration: Xm Ys
```

#### 6.3 FAILURE/UNSTABLE (All Modes — Unchanged Ordering)

Test results continue to appear inside `_display_failure_diagnostics()` between Failed Jobs and Error Logs. No change to failure output ordering.

### 7. JSON Output Structure

#### 7.1 Top-Level `test_results` Field

The `test_results` field becomes a top-level field in the JSON output for all completed builds:

```json
{
  "job": "ralph1",
  "build_number": 85,
  "status": "SUCCESS",
  "test_results": {
    "total": 407,
    "passed": 407,
    "failed": 0,
    "skipped": 30,
    "failed_tests": []
  }
}
```

#### 7.2 No Test Report

```json
{
  "test_results": null
}
```

#### 7.3 Failed Build (Unchanged Structure)

For failed builds, `test_results` continues to appear alongside `failure`:

```json
{
  "status": "FAILURE",
  "failure": { ... },
  "test_results": {
    "total": 407,
    "passed": 376,
    "failed": 1,
    "skipped": 30,
    "failed_tests": [ ... ]
  }
}
```

### 8. Consistency Rule

Per `specs/README.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must always be consistent. This spec ensures:
- All three modes show test results for all completed builds
- JSON `test_results` field is present whenever the human-readable section would appear
- The summary numbers match across all modes

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jenkins-common.sh` | Modify `display_test_results()` to use green color when `failCount == 0`. Add closing bar to all paths. Add placeholder display when test report is empty. Modify `display_success_output()` to fetch and display test results. Move `test_results` JSON population out of the `is_failed` block in `output_json()`. |
| `skill/buildgit/scripts/buildgit` | Modify `_handle_build_completion()` to fetch and display test results for SUCCESS builds. |

## Acceptance Criteria

1. `buildgit status` for a SUCCESS build shows `=== Test Results ===` with summary in green
2. `buildgit push` for a SUCCESS build shows `=== Test Results ===` with summary in green before `Finished: SUCCESS`
3. `buildgit build` for a SUCCESS build shows test results (same as push)
4. `buildgit status -f` for a SUCCESS build shows test results (same as push)
5. `buildgit status --json` for a SUCCESS build includes `test_results` field
6. `buildgit status --json` for a build with no junit results includes `"test_results": null`
7. Test Results section uses green when `failCount == 0`, yellow when `failCount > 0`
8. When no test report exists, placeholder `(no test results available)` is shown
9. Closing `====================` bar is present in all cases
10. Failure output is unchanged — same ordering, same content
11. All existing tests continue to pass

## Testing

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| Success build shows test results in snapshot mode | Mock a SUCCESS build with test report; verify `display_success_output` includes `=== Test Results ===` with green color codes |
| Success build shows test results in monitoring mode | Mock a SUCCESS build; verify `_handle_build_completion` output includes test results |
| Green color for all-pass | Mock test report with `failCount=0`; verify `display_test_results` uses green color codes for header, summary, and closing bar |
| Yellow color for failures | Mock test report with `failCount>0`; verify `display_test_results` uses yellow color codes (existing behavior preserved) |
| No test report shows placeholder | Call `display_test_results` with empty input; verify placeholder text appears |
| Closing bar always present | Verify `====================` appears for all-pass, failures, and placeholder |
| JSON includes test_results for SUCCESS | Mock a SUCCESS build; verify `output_json` includes `test_results` field |
| JSON test_results null when no report | Mock a build without test report; verify `output_json` includes `"test_results": null` |

### Manual Testing Checklist

- [ ] `buildgit push` — SUCCESS build with passing tests shows green test results
- [ ] `buildgit status` — SUCCESS build with passing tests shows green test results
- [ ] `buildgit status -f` — SUCCESS build shows test results before Finished line
- [ ] `buildgit status --json` — SUCCESS build includes `test_results` in JSON
- [ ] `buildgit push` — UNSTABLE build still shows yellow test results with failed test details
- [ ] `buildgit status` — build with no junit results shows placeholder
- [ ] `buildgit status --json` — build with no junit results shows `"test_results": null`

## Related Specifications

- `test-failure-display-spec.md` — Original test results display feature (failure-only)
- `refactor-shared-failure-diagnostics-spec.md` — Shared `_display_failure_diagnostics()` function
- `console-on-unstable-spec.md` — Error log suppression when test failures present
- `unify-follow-log-spec.md` — Unified monitoring output format
- `bug2026-02-13-build-monitoring-header-spec.md` — Build monitoring header format
