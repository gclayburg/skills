# Feature: --console Global Option
Date: 2026-02-08
References: specs/todo/bug-console-status.md

## Overview

When a build is UNSTABLE (test failures), the `=== Error Logs ===` section currently shown by `buildgit status` contains noisy, irrelevant console output — it picks up passing test names that happen to contain words like "failed" or "error" in their names. Since the `=== Test Results ===` section already displays the actual failed tests with stack traces, the Error Logs section adds clutter without value.

This spec removes the Error Logs section from the default output when test failures are present, and adds a new `--console` (`-c`) global option to explicitly request console log output in that case.

## Problem Statement

### Current Behavior

- `buildgit status` (snapshot): Shows `=== Error Logs ===` for all failure types (UNSTABLE and FAILURE) via `display_failure_output()` → `_display_error_logs()`.
- `buildgit build`, `buildgit push`, `buildgit status -f` (monitored): Do NOT show Error Logs — `_handle_build_completion()` only shows test results.
- `buildgit status --json`: Includes `error_summary` field in the `failure` object for all failure types.

This is inconsistent: `status` shows Error Logs but `build`/`push`/`status -f` do not.

### The Noise Problem

The `extract_error_lines()` function greps for lines matching `ERROR|Exception|FAILURE|failed|FATAL`. When the console output contains TAP test output (bats), this matches passing tests whose names contain these words:

```
ok 293 print_stage_line_failed # in 32 ms
ok 310 get_all_stages_api_failure # in 25 ms
ok 340 fetch_test_results_returns_empty_on_error # in 45 ms
```

These passing tests appear alongside actual failures, making the Error Logs section misleading.

### Expected Behavior

- **Default (no option):** When test results exist and contain failures (UNSTABLE), do not show console log output. The test results section is sufficient.
- **With `--console`:** Show console log output for UNSTABLE builds, using the specified mode.
- **FAILURE without test results:** Continue showing Error Logs as before (unchanged behavior). This is the case where Error Logs provide the only diagnostic information (e.g. build errors, stage failures without test output).
- **Early failure (no stages):** Continue showing full console as before (unchanged, handled by `_display_early_failure_console()`).

## Specification

### 1. New Global Option

```
-c, --console <mode>    Show console log output
                         Modes: auto, <number>
```

| Mode | Behavior |
|------|----------|
| `auto` | Automatically parse the console log to extract and display only the section relevant to the failure, using `extract_error_lines()` |
| `<number>` (e.g. `50`) | Show the last N lines of the console output |

The option is parsed in `parse_global_options()` alongside `--job` and `--verbose`. It stores the mode in a global variable (e.g. `CONSOLE_MODE`).

When the option is not specified, `CONSOLE_MODE` is empty (meaning: suppress console logs for UNSTABLE builds with test failures; use extracted error lines for FAILURE builds without test failures).

### 2. Default Behavior Change (No Option Specified)

When test results are present and contain failures (UNSTABLE result):

- **`display_failure_output()`**: Skip the `_display_error_logs()` call.
- **`_handle_build_completion()`**: No change needed (already does not show Error Logs).
- **`output_json()`**: Omit the `error_summary` field from the `failure` object (set to `null`).

This makes all paths consistent: no console log output for UNSTABLE builds by default.

When test results are NOT present (FAILURE result, non-test failure):

- **No change.** `_display_error_logs()` is still called, which uses `extract_error_lines()` to automatically parse the console log and display only the lines relevant to the failure. `error_summary` is still populated in JSON. This is the same mechanism as `--console auto`.

### 3. Behavior With `--console`

When the option is specified:

#### Human-readable output (`status`, `status -f`, `build`, `push`)

| Mode | Display |
|------|---------|
| `auto` | Show `=== Error Logs ===` section using `extract_error_lines()` to automatically parse the console log and display only the failure-relevant lines |
| `<N>` | Show `=== Console Log (last N lines) ===` section with the last N lines of raw console output |

This applies to all failure output paths:
- `display_failure_output()` — used by `status` and `status -f` (completed build)
- `_handle_build_completion()` — used by `build`, `push`, `status -f` (monitored build)

#### JSON output (`status --json`)

When `--console` is specified:

| Mode | JSON behavior |
|------|---------------|
| `auto` | Populate `error_summary` using `extract_error_lines()` (current behavior) |
| `<N>` | Populate `console_log` field with the last N lines of raw console output |

New field in the `failure` object:
```json
{
  "failure": {
    "failed_jobs": [...],
    "root_cause_job": "...",
    "failed_stage": "...",
    "error_summary": "...",
    "console_log": "..."
  }
}
```

- `error_summary`: Populated when mode is `auto`, `null` otherwise
- `console_log`: Populated when mode is a number, `null` otherwise

### 4. Consistency Rule

Per `specs/README.md` spec rules: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must always be consistent. This spec ensures:

- All paths suppress console logs for UNSTABLE by default
- All paths honor `--console` when specified
- JSON output fields reflect the same data as human-readable output

### 5. Help Text Update

```
Global Options:
  -j, --job <name>               Specify Jenkins job name (overrides auto-detection)
  -c, --console <mode>           Show console log output (auto or line count)
  -h, --help                     Show this help message
  --verbose                      Enable verbose output for debugging
```

### 6. Decision Table

| Build Result | Test Failures? | `--console` | Error Logs Shown? |
|---|---|---|---|
| UNSTABLE | Yes | not specified | No |
| UNSTABLE | Yes | `auto` | Yes (extracted) |
| UNSTABLE | Yes | `50` | Yes (last 50 lines) |
| FAILURE | No | not specified | Yes (extracted) |
| FAILURE | No | `auto` | Yes (extracted) |
| FAILURE | No | `50` | Yes (last 50 lines) |
| FAILURE | Yes | not specified | No |
| FAILURE | Yes | `auto` | Yes (extracted) |
| FAILURE | Yes | `50` | Yes (last 50 lines) |
| SUCCESS | N/A | any | No (no failure output) |

**Terminology:**
- **Yes (extracted):** The script uses `extract_error_lines()` to automatically parse the console log and display only lines relevant to the failure (lines matching error/exception/failure patterns). This is the same mechanism used by both the default FAILURE behavior (no option specified) and the explicit `--console auto` mode.
- **Yes (last N lines):** The script displays the last N lines of raw console output without any filtering.

Note: FAILURE with test failures is possible (e.g. a post-build step fails after tests ran). In that case, the same logic applies — if test results exist, suppress console logs by default.

### 7. Files to Modify

| File | Changes |
|------|---------|
| `buildgit` | Add `-c, --console` to `parse_global_options()`, `show_usage()`. Pass mode to display functions. Update `_handle_build_completion()` to show console when option specified. |
| `lib/jenkins-common.sh` | Update `display_failure_output()` to conditionally call `_display_error_logs()`. Update `output_json()` / `_build_failure_json()` to conditionally populate `error_summary`/`console_log`. |
