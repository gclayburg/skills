# Simple Refactoring: Deduplication Pass
Date: 2026-02-07

## Overview

Reduce code duplication across `buildgit` and `lib/jenkins-common.sh` through targeted extraction of repeated patterns into shared helper functions. No user-visible behavior changes. All existing tests must continue to pass without modification.

## Problem Statement

The codebase has grown organically as features were added. Several code patterns are now duplicated 2-4 times across files, making maintenance harder:

- Changing trigger display formatting requires edits in 3 places
- Adding a new Jenkins validation step requires edits in 4 places
- A bug in commit display formatting must be fixed in 3 places

Total estimated duplication: ~240 lines across 8 areas.

## Scope

- Files affected: `buildgit`, `lib/jenkins-common.sh`
- No new features, no changed behavior, no changed output
- All existing tests must pass unchanged
- Refactoring only — extract helpers, remove dead wrappers, merge near-identical functions

## Constraints

- Each refactoring item is independent and can be done in any order
- Preserve all existing function signatures that are called from `buildgit` (public API)
- Internal/private functions (prefixed with `_`) may be renamed, merged, or removed
- Spec references in comments should be preserved

---

## Refactoring Items

### R1. Extract display formatting helpers (jenkins-common.sh)

**Problem**: `display_success_output`, `display_failure_output`, and `display_building_output` each contain identical blocks for formatting trigger, commit, and correlation displays.

**Current locations**:
- Trigger formatting: lines ~1716-1722, ~1791-1797, ~2052-2058
- Commit formatting: lines ~1726-1735, ~1801-1810, ~2062-2071
- Correlation formatting: lines ~1739-1746, ~1813-1821, ~2074-2082

**Solution**: Extract three small helpers:

```bash
# Format trigger type into display string
# Usage: _format_trigger_display "automated" "username"
# Returns: "Automated (git push)" or "Manual (started by username)" or "Unknown"
_format_trigger_display() { ... }

# Format commit SHA and message into display string
# Usage: _format_commit_display "abc1234..." "commit message"
# Returns: "abc1234 - \"commit message\"" or "abc1234" or "unknown"
_format_commit_display() { ... }

# Format correlation status into colored display components
# Usage: Sets CORRELATION_SYMBOL, CORRELATION_DESC, CORRELATION_COLOR
# Input: correlation_status
_format_correlation_display() { ... }
```

Each `display_*_output` function replaces its inline block with a call to the helper.

**Lines saved**: ~40
**Risk**: Low

---

### R2. Extract Jenkins validation sequence (buildgit)

**Problem**: The sequence of `validate_dependencies` → `validate_environment` → resolve job name → `verify_jenkins_connection` → `verify_job_exists` is repeated four times in `buildgit` with near-identical error handling.

**Current locations**:
- `cmd_status` normal mode (lines ~650-700)
- `cmd_status` follow mode (lines ~589-623)
- `cmd_push` (lines ~889-938)
- `cmd_build` (lines ~1069-1114)

**Solution**: Extract a single function:

```bash
# Validate Jenkins environment, resolve job name, verify connectivity
# Usage: _validate_jenkins_setup "context-for-errors"
# Sets: _VALIDATED_JOB_NAME
# Returns: 0 on success, 1 on failure (with appropriate error messages)
_validate_jenkins_setup() {
    local context="$1"  # e.g., "monitor Jenkins builds", "trigger Jenkins build"
    ...
}
```

The `context` parameter customizes error messages (e.g., "Cannot monitor Jenkins builds" vs "Cannot trigger Jenkins build"). Each command replaces its validation block with a single call.

**Lines saved**: ~90
**Risk**: Low — error messages will be slightly normalized but convey the same information

---

### R3. Extract build context extraction (buildgit)

**Problem**: Both `_jenkins_status_check` and `_display_build_in_progress_banner` contain identical 20-line blocks that extract trigger info, commit info, and correlation status from a build.

**Current locations**:
- `_jenkins_status_check` (lines ~276-299)
- `_display_build_in_progress_banner` (lines ~447-474)

**Solution**: Extract a helper:

```bash
# Extract trigger, commit, and correlation info from a build
# Usage: _extract_build_context "job-name" "build-number" "console_output"
# Sets globals: _BC_TRIGGER_TYPE, _BC_TRIGGER_USER,
#               _BC_COMMIT_SHA, _BC_COMMIT_MSG, _BC_CORRELATION_STATUS
_extract_build_context() { ... }
```

Both callers replace their inline extraction with a call to this function, then read the globals.

**Lines saved**: ~20
**Risk**: Low — introduces globals but they follow existing patterns (e.g., `_BANNER_STAGES_JSON`)

---

### R4. Deduplicate format_stage_duration (jenkins-common.sh)

**Problem**: `format_stage_duration` (line ~1412) copies the entire body of `format_duration` (line ~1384) and just prepends a sub-second check.

**Solution**: Have `format_stage_duration` delegate to `format_duration`:

```bash
format_stage_duration() {
    local ms="$1"
    if [[ -z "$ms" || "$ms" == "null" || ! "$ms" =~ ^[0-9]+$ ]]; then
        echo "unknown"
        return
    fi
    if [[ "$ms" -lt 1000 ]]; then
        echo "<1s"
        return
    fi
    format_duration "$ms"
}
```

**Lines saved**: ~15
**Risk**: None

---

### R5. Merge stage display functions (jenkins-common.sh)

**Problem**: `_display_all_stages` and `_display_completed_stages` share the same fetch-iterate-print structure. The only difference is that `_display_completed_stages` filters by status and saves state to `_BANNER_STAGES_JSON`.

**Current locations**: lines ~1501-1572

**Solution**: Merge into one function with a filter parameter:

```bash
# Display stages from a build
# Usage: _display_stages "job-name" "build-number" [--completed-only]
# When --completed-only: skips IN_PROGRESS/NOT_EXECUTED, saves state to _BANNER_STAGES_JSON
_display_stages() { ... }
```

Update callers:
- `display_success_output` / `display_failure_output` call `_display_stages "$job" "$build"`
- `_display_build_in_progress_banner` calls `_display_stages "$job" "$build" --completed-only`

**Lines saved**: ~25
**Risk**: Low

---

### R6. Deduplicate build metadata extraction (jenkins-common.sh)

**Problem**: `display_build_metadata` (line ~1125) and `_build_info_json` (line ~2470) both extract the same three fields from console output using identical grep/sed patterns.

**Solution**: Extract a parser that sets variables:

```bash
# Parse build metadata from console output
# Usage: _parse_build_metadata "$console_output"
# Sets: _META_STARTED_BY, _META_AGENT, _META_PIPELINE
_parse_build_metadata() { ... }
```

`display_build_metadata` calls the parser then formats text output.
`_build_info_json` calls the parser then formats JSON output.

**Lines saved**: ~15
**Risk**: Low

---

### R7. Remove dead wrappers (buildgit)

**Problem**: Two functions exist solely to forward to `_handle_build_completion`:

```bash
_push_handle_build_result() {
    _handle_build_completion "$@"
}
_build_handle_result() {
    _handle_build_completion "$@"
}
```

**Solution**: Delete both functions. Replace call sites with direct calls to `_handle_build_completion`.

- Line ~967: `_push_handle_build_result` → `_handle_build_completion`
- Line ~1164: `_build_handle_result` → `_handle_build_completion`

**Lines saved**: ~10
**Risk**: None

---

### R8. Merge wait-for-build-start functions (buildgit)

**Problem**: `_push_wait_for_build_start` (line ~739) and `_build_wait_for_start` (line ~998) both poll Jenkins for a new build. The build version additionally tries the queue API first, but otherwise the polling loop is identical.

**Solution**: Merge into one function:

```bash
# Wait for a new build to start
# Usage: _wait_for_build_start "job-name" "baseline-build-number" ["queue-url"]
# Returns: new build number on stdout, 1 on timeout
_wait_for_build_start() { ... }
```

When `queue_url` is provided, try the queue API first (current `_build_wait_for_start` behavior). Otherwise, or on queue API failure, fall back to polling by build number (current `_push_wait_for_build_start` behavior).

Update callers:
- `cmd_push`: `_wait_for_build_start "$job_name" "$baseline_build" ""`
- `cmd_build`: `_wait_for_build_start "$job_name" "$baseline_build" "$queue_url"`

**Lines saved**: ~25
**Risk**: Low — the push version gains the queue notification message from the build version, which is harmless and slightly better UX

---

## Implementation Order (Suggested)

Items are independent, but this order minimizes conflicts:

1. **R7** — Remove dead wrappers (trivial, zero risk)
2. **R4** — Deduplicate `format_stage_duration` (trivial, zero risk)
3. **R6** — Extract build metadata parser (self-contained in jenkins-common.sh)
4. **R1** — Extract display formatting helpers (self-contained in jenkins-common.sh)
5. **R5** — Merge stage display functions (self-contained in jenkins-common.sh)
6. **R3** — Extract build context extraction (buildgit only)
7. **R8** — Merge wait-for-build-start (buildgit only)
8. **R2** — Extract Jenkins validation sequence (largest change, do last)

## Verification

After each item:
- Run the full bats test suite: `./test/bats/bin/bats test/`
- All tests must pass without modification
- Manual smoke test: `buildgit status` should produce identical output
