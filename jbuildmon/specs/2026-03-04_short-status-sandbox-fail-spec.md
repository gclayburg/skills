## Warn user when test results cannot be retrieved

- **Date:** `2026-03-04T11:10:46-0700`
- **References:** `specs/todo/short-status-sandbox-fail.md`
- **Supersedes:** none
- **State:** `DRAFT`

## Background

When `buildgit status` runs in a restrictive sandbox (e.g. Claude Code with `/sandbox` enabled) or encounters a network failure, the curl call to the Jenkins test report API fails silently. The user sees `Tests=?/?/?` with no color — identical to the display for in-progress builds or `--no-tests`. In the sandbox case, the build status itself may show SUCCESS (green), giving the false impression that everything is fine when in reality test data was never retrieved.

A `log_warning` is emitted to stderr inside `fetch_test_results` for non-200/404 HTTP codes (the `*` case), but this is easy to miss and doesn't distinguish "no test report exists" (404) from "couldn't reach Jenkins" (network error / HTTP 000).

The user should see a clear, unambiguous warning that test information could not be retrieved due to a communication failure — not a project or test issue.

## Root Cause Analysis

In `lib/jenkins-common.sh`, `jenkins_api_with_status` uses `curl -s -w "\n%{http_code}"`. When curl fails at the network level (sandbox block, DNS failure, connection refused):
- curl exits non-zero but `set -e` doesn't trigger because the result is captured in a variable
- `-w "%{http_code}"` outputs `000` for connection-level failures
- `fetch_test_results` hits the `*` case, logs a warning to stderr, and returns empty string
- The caller in `_status_line_for_build_json` sees empty string, keeps `tests_display="?/?/?"`, and renders with no color

The problem: `?/?/?` is ambiguous — it means the same thing for "build in progress", "used --no-tests", "no test report (404)", and "network failure". The user has no way to distinguish these cases in the output.

## Specification

### 1. Distinguish communication failures from missing test data

`fetch_test_results` currently returns an empty string for both 404 (no test report) and network failures. Change the return convention:

| Scenario | Return value | Exit code |
|----------|-------------|-----------|
| HTTP 200, valid JSON | JSON body | 0 |
| HTTP 404 (no test report) | empty string | 0 |
| Network error (HTTP 000) | empty string | 2 |
| Other HTTP error (5xx, etc.) | empty string | 2 |

Exit code 2 signals "communication failure" vs exit code 0 for "no data available". The caller can distinguish the two cases.

### 2. Inline display change for communication failures

When `fetch_test_results` returns exit code 2 (communication failure), change the inline test display across all output modes:

#### Line mode (`--line`, `--format`)

Replace `Tests=?/?/?` with `Tests=!err!` styled in the existing warning/yellow color (`COLOR_YELLOW`):

```
SUCCESS #9 id=5b0eab8 Tests=!err! Took 2m 26s on 2026-03-04T10:45:51-0700 (1 minute ago)
```

The `!err!` token is visually distinct from `?/?/?` and signals something went wrong. Use yellow color on TTY.

For `--format`, the `%t` placeholder emits `!err!` (with color if TTY).

#### Full snapshot mode (default `--all`)

In the test results section, replace the normal test summary with:

```
Test Results: ⚠ Communication error retrieving test results
```

Use yellow color on TTY.

#### JSON mode (`--json`)

Add a `testResultsError` field when communication fails:

```json
{
  "testResults": null,
  "testResultsError": "communication_failure"
}
```

When test results are successfully fetched or simply not available (404), `testResultsError` is omitted (not present in the JSON).

#### Follow/monitoring mode (`status -f`, `push`, `build`)

Same inline `Tests=!err!` display in the progress bar and completion line. The stderr warning (below) provides detail.

### 3. Stderr warning message

When a communication failure is detected, print a single warning line to stderr:

```
⚠ Could not retrieve test results (communication error)
```

This uses `log_warning` (existing function), which already writes to stderr with the `⚠` prefix. Print this once per build, not on every poll cycle in follow mode.

### 4. Preserve existing behavior for non-error cases

| Scenario | Inline display | Color | Stderr |
|----------|---------------|-------|--------|
| Tests fetched successfully (all pass) | `Tests=667/0/0` | green | none |
| Tests fetched (some failures) | `Tests=660/7/0` | yellow | none |
| No test report (HTTP 404) | `Tests=?/?/?` | none | none |
| `--no-tests` flag | `Tests=?/?/?` | none | none |
| Build in progress | `Tests=?/?/?` | none | none |
| **Communication failure** | **`Tests=!err!`** | **yellow** | **⚠ warning** |

### 5. No retry logic

Do not add automatic retries. The failure is logged and displayed. The user can re-run the command if the issue is transient.

## Test Strategy

### Unit tests

1. **Communication failure display (line mode)**: Mock `jenkins_api_with_status` to return HTTP 000. Verify `_status_line_for_build_json` outputs `Tests=!err!` instead of `Tests=?/?/?`.
2. **Communication failure display (JSON mode)**: Same mock. Verify JSON output contains `"testResultsError": "communication_failure"` and `"testResults": null`.
3. **Communication failure stderr warning**: Same mock. Verify stderr contains the warning message.
4. **Normal 404 unchanged**: Mock HTTP 404. Verify output still shows `Tests=?/?/?` with no stderr warning and no `testResultsError` in JSON.
5. **Normal success unchanged**: Mock HTTP 200 with valid test JSON. Verify `Tests=pass/fail/skip` displays correctly.
6. **`--no-tests` unchanged**: Verify `Tests=?/?/?` with no fetch attempted.
7. **Follow mode dedup**: In follow/monitoring mode, verify the stderr warning is printed only once per build, not on every poll.
8. **HTTP 5xx treated as communication failure**: Mock HTTP 500. Verify `Tests=!err!` and stderr warning.

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
