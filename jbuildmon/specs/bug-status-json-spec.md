# Bug Fix: JSON Output Missing Console/Error Details for Failed Builds
Date: 2026-02-07
References: specs/todo/bug-status-json.md

## Overview

`buildgit status --json` omits critical failure details that `buildgit status` (non-JSON) shows. For early failures (no pipeline stages ran), the JSON has no console output at all. For stage failures, the `error_summary` is a single truncated line that doesn't match the multi-line error log extraction shown in the non-JSON output. The JSON output must be brought into parity with the non-JSON output per the spec rule that all three status modes stay consistent.

## Problem Statement

### Current JSON Output (early failure, no stages ran)

```json
{
  "failure": {
    "failed_jobs": ["ralph1"],
    "root_cause_job": "ralph1",
    "failed_stage": null,
    "error_summary": "org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:"
  }
}
```

No console output text is included. The `error_summary` is just the exception class name — useless for diagnosing the problem.

### Current Non-JSON Output (early failure, no stages ran)

```
=== Console Output ===
Started by user buildtriggerdude
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:
WorkflowScript: 3: Too many arguments for map key "node" @ line 3, column 9.
           node('fastnode') {
           ^
...
======================
```

The full console is shown, making the error immediately actionable.

### Current JSON Output (stage failure)

```json
{
  "failure": {
    "failed_jobs": ["ralph1"],
    "root_cause_job": "ralph1",
    "failed_stage": "Test",
    "error_summary": "ERROR: some single line..."
  }
}
```

The `error_summary` is a single grep-matched line (max 200 chars). The non-JSON output shows up to 30 lines of extracted error logs from the failed stage, which is far more useful.

## Expected Behavior

### Early Failure (no stages ran)

Add a `console_output` field containing the full console text. The `error_summary` field is not needed since the console tells the whole story.

```json
{
  "failure": {
    "failed_jobs": ["ralph1"],
    "root_cause_job": "ralph1",
    "failed_stage": null,
    "error_summary": null,
    "console_output": "Started by user buildtriggerdude\nObtained Jenkinsfile from git...\norg.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:\nWorkflowScript: 3: Too many arguments for map key \"node\" @ line 3, column 9.\n..."
  }
}
```

### Stage Failure (stages ran, one failed)

Replace the single-line `error_summary` with the same multi-line error extraction that `_display_error_logs()` produces. This includes:
- Stage-specific log extraction (via `extract_stage_logs` + `extract_error_lines`, up to 30 lines)
- Fallback to last 50 lines of console if stage extraction is insufficient (< 5 lines)
- Downstream build error extraction when applicable

The `console_output` field is omitted (not needed for stage failures — same as non-JSON behavior).

```json
{
  "failure": {
    "failed_jobs": ["ralph1"],
    "root_cause_job": "ralph1",
    "failed_stage": "Test",
    "error_summary": "multi-line error extraction matching\nwhat _display_error_logs would show\nfor this same build..."
  }
}
```

### Success / Building

No `failure` object — no change from current behavior. The `console_output` field is not added.

## Detection Criteria

The same logic used by `_display_early_failure_console()` determines which path to take:
- `get_all_stages()` returns empty array (`[]`) → early failure → include `console_output`
- `get_all_stages()` returns stages → stage failure → use `error_summary` with full error extraction

## Technical Requirements

### 1. Modify `_build_failure_json()` to detect early failures

At the top of `_build_failure_json()`, call `get_all_stages()` to determine if stages ran:
- If no stages ran: set `console_output` to the full console text, set `error_summary` to empty
- If stages ran: use the existing downstream/stage failure logic but improve `error_summary` extraction (see requirement 2)

### 2. Improve `error_summary` for stage failures

Replace the call to `_extract_error_summary()` (which returns a single grep-matched line) with logic that mirrors `_display_error_logs()`:

1. Check for downstream build failure → extract error lines from downstream console
2. If no downstream, get failed stage → extract stage logs → `extract_error_lines` (up to 30 lines)
3. If stage extraction is insufficient (< 5 lines), fall back to last 50 lines of console
4. If no failed stage found, `extract_error_lines` from main console

Store the multi-line result in `error_summary`.

### 3. Add `console_output` field to failure JSON

When early failure is detected, add a `console_output` string field to the failure JSON object containing the full console text.

When stages exist, omit the `console_output` field (or set to null).

### 4. Updated failure JSON schema

```json
{
  "failure": {
    "failed_jobs": ["string"],
    "root_cause_job": "string",
    "failed_stage": "string | null",
    "error_summary": "string | null",
    "console_output": "string | null (present only for early failures)"
  }
}
```

## Affected Components

| File | Function | Change |
|------|----------|--------|
| `lib/jenkins-common.sh` | `_build_failure_json()` | Add early failure detection, include `console_output` field, improve `error_summary` |
| `lib/jenkins-common.sh` | `_extract_error_summary()` | May be replaced or extended with multi-line extraction logic |

## Acceptance Criteria

1. **Early failure JSON includes console_output**: When no stages ran, `failure.console_output` contains the full console text
2. **Early failure JSON has null error_summary**: When no stages ran, `error_summary` is null
3. **Stage failure JSON has multi-line error_summary**: When stages ran and one failed, `error_summary` contains the same error extraction (up to 30 lines) that the non-JSON output shows
4. **Stage failure JSON omits console_output**: When stages ran, `console_output` is null or absent
5. **Downstream failure handling**: When a downstream build caused the failure, `error_summary` is extracted from the downstream console (matching non-JSON behavior)
6. **Fallback behavior**: When stage log extraction produces < 5 lines, `error_summary` falls back to the last 50 lines (matching non-JSON behavior)
7. **Success/building builds unchanged**: No `failure` object is added for non-failure builds

## Testing

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| Early failure JSON includes console_output | Mock build with no stages + FAILURE; verify `failure.console_output` contains full console text |
| Early failure JSON has null error_summary | Same mock; verify `failure.error_summary` is null |
| Stage failure JSON has multi-line error_summary | Mock build with failed stage; verify `failure.error_summary` has multiple lines matching error extraction |
| Stage failure JSON omits console_output | Same mock; verify `failure.console_output` is null or absent |
| Success build has no failure object | Mock successful build; verify no `failure` key in JSON |

## Related Specifications

- `buildgit-early-build-failure-spec.md` — Early failure console display (non-JSON path)
- `bug2026-01-27-jenkins-log-truncated-spec.md` — Stage log extraction and fallback behavior
- `buildgit-spec.md` — `buildgit status --json` output format
