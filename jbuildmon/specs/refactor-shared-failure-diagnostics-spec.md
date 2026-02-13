# Refactoring: Shared Failure Diagnostics Across All Entry Points
Date: 2026-02-12T19:05:00-07:00
References: specs/todo/bug-nofailed-jobs-section.md, specs/todo/bug-phandlemono-no-logs.shown.md
Supersedes: none

## Overview

The failure diagnostic logic (early failure detection, failed jobs tree, downstream build tracking, test results, error extraction) is duplicated across three separate code paths: snapshot mode, monitoring mode, and JSON output. This duplication causes recurring bugs where one path shows information that another doesn't — most recently, the Failed Jobs tree is missing from monitoring mode (`buildgit build`, `buildgit push`, `buildgit status -f`).

This spec extracts shared functions so all entry points produce consistent failure output and future changes only need to be made in one place.

## Problem Statement

### Current Bug

`buildgit build` shows error logs but NOT the Failed Jobs section:

```
[18:47:00] ℹ   Stage: Build Handle (9s)    ← FAILED
...

=== Error Logs ===
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'...
==================

Finished: FAILURE
```

`buildgit status` for the same build shows BOTH:

```
=== Failed Jobs ===
  → phandlemono-IT (stage: Build Handle)
    → phandlemono-handle  ← FAILED
    → phandlemono-signalboot  ✓
====================

=== Error Logs ===
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'...
==================
```

### Root Cause: Duplicated Logic

The failure diagnostic logic exists in three independent implementations:

| Logic | Snapshot (`display_failure_output`) | Monitoring (`_handle_build_completion`) | JSON (`_build_failure_json` / `output_json`) |
|-------|-------------------------------------|----------------------------------------|----------------------------------------------|
| Early failure check | Inside `_display_error_logs()` | Direct call to `_display_early_failure_console()` | Own implementation (L2485) |
| Failed jobs tree | `_display_failed_jobs_tree()` | **MISSING** | Own downstream loop (L2498-2534) |
| Downstream detection | `_display_error_logs()` via `find_failed_downstream_build()` | Via shared `_display_error_log_section()` | Own downstream loop (same logic, duplicated) |
| Test results fetch | `fetch_test_results()` + `display_test_results()` | Same functions (duplicated call) | `fetch_test_results()` + `format_test_results_json()` |
| Error extraction | `_display_error_logs()` with stage-aware extraction | Via shared `_display_error_log_section()` | Own `extract_error_lines()` calls (L2538-2558) |

When a new diagnostic section is added to one path, it must be manually replicated in the other two. This is the pattern that caused the original NOT_BUILT bug and the current Failed Jobs bug.

## Solution

### 1. Extract `_display_failure_diagnostics()` for Human-Readable Output

Create a single function in `lib/jenkins-common.sh` that handles the complete failure diagnostics block for human-readable output:

```bash
# Display all failure diagnostic sections for human-readable output
# Usage: _display_failure_diagnostics "job_name" "build_number" "console_output"
_display_failure_diagnostics() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"

    # 1. Early failure (no stages ran) → show full console, return
    if _display_early_failure_console "$job_name" "$build_number" "$console_output"; then
        return 0
    fi

    # 2. Failed jobs tree (with downstream detection)
    _display_failed_jobs_tree "$job_name" "$build_number" "$console_output"

    # 3. Test results
    local test_results_json
    test_results_json=$(fetch_test_results "$job_name" "$build_number")
    if [[ -n "$test_results_json" ]]; then
        display_test_results "$test_results_json"
    fi

    # 4. Error log section (respects --console and test failure suppression)
    _display_error_log_section "$job_name" "$build_number" "$console_output" "$test_results_json"
}
```

### 2. Simplify Both Human-Readable Callers

**`display_failure_output()`** (snapshot path) becomes:

```bash
display_failure_output() {
    # ... banner, stages, build details, metadata (unchanged) ...

    # Failure diagnostics (shared)
    _display_failure_diagnostics "$job_name" "$build_number" "$console_output"

    echo ""
    echo "Console:    ${url}console"
}
```

Removes: direct calls to `_display_failed_jobs_tree()`, `fetch_test_results()`, `display_test_results()`, and `_display_error_log_section()`.

**`_handle_build_completion()`** (monitoring path) becomes:

```bash
_handle_build_completion() {
    local job_name="$1"
    local build_number="$2"

    local build_json result
    build_json=$(get_build_info "$job_name" "$build_number")
    result=$(echo "$build_json" | jq -r '.result // "UNKNOWN"')

    if [[ "$result" != "SUCCESS" ]]; then
        local console_output
        console_output=$(get_console_output "$job_name" "$build_number" 2>/dev/null) || true

        # Failure diagnostics (shared)
        _display_failure_diagnostics "$job_name" "$build_number" "$console_output"
    fi

    echo ""
    print_finished_line "$result"

    [[ "$result" == "SUCCESS" ]]
}
```

Removes: direct calls to `_display_early_failure_console()`, `fetch_test_results()`, `display_test_results()`, and `_display_error_log_section()`.

### 3. Verify JSON Path Consistency

The JSON path (`_build_failure_json()` in `output_json()`) has its own implementation of:
- Early failure detection (stage count check)
- Downstream build traversal (while loop tracking deepest failed job)
- Error extraction (stage-aware extraction with fallback)

These parallel the human-readable logic but produce JSON instead of terminal output. Since JSON output is structurally different (building a data object vs printing sections), it cannot directly call the display functions. However, the **detection logic** (early failure check, downstream traversal, error extraction) should be verified to handle the same cases.

**Verification checklist for `_build_failure_json()`:**
- [ ] Handles NOT_BUILT result (already fixed by previous spec)
- [ ] Downstream detection uses the same `detect_all_downstream_builds()` + `find_failed_downstream_build()` functions as `_display_failed_jobs_tree()`
- [ ] Error extraction mirrors `_display_error_logs()` fallback logic (stage extraction → fallback to last N lines)
- [ ] Early failure detection uses the same `get_all_stages()` check

If any of these are inconsistent, fix them as part of this spec. If all are consistent, no JSON changes needed — the refactoring here prevents future drift by consolidating the human-readable paths, and the JSON path's parallel implementation is documented.

### 4. Consolidate `_display_error_log_section()` into `_display_failure_diagnostics()`

The `_display_error_log_section()` function was extracted in the previous spec. It remains useful as a sub-component within `_display_failure_diagnostics()`, but should no longer be called directly by `display_failure_output()` or `_handle_build_completion()`. Its only caller becomes `_display_failure_diagnostics()`.

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jenkins-common.sh` | Add `_display_failure_diagnostics()`. Simplify `display_failure_output()` to call it. Verify `_build_failure_json()` consistency. |
| `buildgit` | Simplify `_handle_build_completion()` to call `_display_failure_diagnostics()`. |

## Acceptance Criteria

1. **`buildgit build` shows Failed Jobs tree**: Monitoring mode displays the `=== Failed Jobs ===` section for failed builds with downstream jobs
2. **`buildgit push` shows Failed Jobs tree**: Same as build
3. **`buildgit status -f` shows Failed Jobs tree**: Same as build
4. **`buildgit status` unchanged**: Snapshot output is identical before and after refactoring
5. **`buildgit status --json` consistent**: JSON failure object includes the same downstream detection and error extraction as human-readable output
6. **Single code path**: `_display_failure_diagnostics()` is the only function that orchestrates failure diagnostic display for human-readable output — no direct calls to `_display_failed_jobs_tree()`, `fetch_test_results()`, `display_test_results()`, or `_display_error_log_section()` from `display_failure_output()` or `_handle_build_completion()`
7. **Early failure behavior preserved**: Builds with no stages still show full console output
8. **Test failure suppression preserved**: Error logs are still suppressed by default when test failures exist (unless `--console` is specified)
9. **--console option preserved**: `--console auto` and `--console <N>` continue to work in all modes

## Testing

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| Monitoring mode shows Failed Jobs tree | Mock a failed build with downstream jobs; verify `_handle_build_completion` output includes `=== Failed Jobs ===` section |
| Monitoring mode shows Failed Jobs without downstream | Mock a failed build without downstream; verify Failed Jobs shows root job with `← FAILED` |
| Snapshot and monitoring produce same diagnostics | Mock the same failed build; verify `display_failure_output` and `_handle_build_completion` produce identical diagnostics sections |
| Early failure skips Failed Jobs tree | Mock a build with no stages; verify full console is shown and Failed Jobs tree is not |
| JSON failure object matches human-readable detection | Mock a downstream failure; verify JSON `failed_jobs` array and `root_cause_job` match what `_display_failed_jobs_tree` would show |

### Manual Testing Checklist

- [ ] `buildgit build` for a pipeline with downstream failures shows Failed Jobs tree + Error Logs
- [ ] `buildgit push` for the same scenario shows identical diagnostic output
- [ ] `buildgit status` for the same build shows identical diagnostic sections (different surrounding context is expected: banner, stages, details, metadata are not part of monitoring output)
- [ ] `buildgit status --json` for the same build includes consistent failure data
- [ ] `buildgit push` for a simple FAILURE (no downstream) shows Failed Jobs with just root job
- [ ] `buildgit push` for an UNSTABLE build with test failures shows test results, suppresses error logs
- [ ] `buildgit push --console auto` for an UNSTABLE build shows error logs alongside test results

## Related Specifications

- `bug2026-02-12-phandlemono-no-logs-spec.md` — Previous fix that added NOT_BUILT handling and `_display_error_log_section()`
- `console-on-unstable-spec.md` — `--console` option and error log suppression logic
- `buildgit-early-build-failure-spec.md` — Early failure console display
- `bug-status-json-spec.md` — JSON output for failed builds
- `test-failure-display-spec.md` — Test failure output format
- `unify-follow-log-spec.md` — Unified monitoring output format
