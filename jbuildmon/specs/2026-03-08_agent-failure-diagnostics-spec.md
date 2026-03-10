## Agent-Friendly Build Failure Diagnostics

- **Date:** `2026-03-08T17:44:00-06:00`
- **References:** `specs/done-reports/extra-features-to-examine-build-fails.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Overview

When an AI agent (Claude Code, Cursor, etc.) monitors a build via `buildgit push` or `buildgit status` and the build fails, the agent currently cannot get enough diagnostic detail to fix the problem without resorting to direct Jenkins API calls. Direct API calls are problematic because:

1. **Permission friction** — the user must approve each `curl` command individually
2. **Environment variable expansion issues** — Claude Code's Bash tool has trouble expanding `$JENKINS_URL`, `$JENKINS_USER_ID`, and `$JENKINS_API_TOKEN` inline, requiring workarounds like writing temp scripts
3. **Fragile ad-hoc queries** — agents must guess the right Jenkins API endpoint structure and parse raw JSON

This spec adds new `buildgit` options that let agents drill down into build failures using the same tool they already have, eliminating the need for direct API access.

## Problem Statement

### What Happened (2026-03-08 debugging session)

Build #60 failed with 1 test failure. The `buildgit status --all` output showed:

```
FAILED TESTS:
✗ buildgit_status_follow.bats::follow_completed_build_shows_console_url
  (from function `assert_success' in file .../assert_success.bash, line 45,
   in test file test/buildgit_status_follow.bats, line 944)
    `assert_success' failed

  -- command failed --
  ...
```

The critical information was **truncated** — the `...` hid the exit code (141) and the 4 lines of actual output that were essential for diagnosing the root cause (SIGPIPE from internal `jq|head -1` pipes under parallel bats execution).

To get the full picture, the agent had to:
1. Construct a Jenkins API URL manually for the test report endpoint
2. Write a temp script to work around env var expansion issues
3. Parse the JSON response with inline Python
4. When that failed (empty response), fall back to fetching the full console text
5. Grep through the console text for the test name to find the full TAP output

All of this required multiple user approvals and multiple failed attempts before getting the data needed to diagnose the issue.

### What the Agent Needed

The agent needed three things that `buildgit` doesn't currently provide:

1. **Full failed test output** — the complete `stdout` and error details for a specific failed test, not truncated
2. **Stage console text** — the raw console output from a specific parallel stage (e.g., "Unit Tests D") to see TAP output, timing, and context around the failure
3. **Structured failure data** — the exit code, stdout, and stderr of failed tests in a machine-parseable format (`--json`) without truncation

## Specification

### Feature 1: `--verbose` shows untruncated test failure output

Currently, failed test output in both `--all` and `--json` modes is truncated. The `--verbose` / `-v` flag (which already exists as a global option) should also control test failure output verbosity.

#### Behavior

| Mode | Current | With `-v` |
|------|---------|-----------|
| `--all` | Stack trace truncated to 5 lines, error messages to 500 chars, `...` at end | Full stack trace, full error message, full stdout/output captured by test runner |
| `--json` | `error_stack_trace` truncated | `error_stack_trace` and new `stdout` field untruncated |
| `--line` | No change | No change (line mode is always compact) |

#### JSON output with `-v`

```json
{
  "test_results": {
    "total": 725,
    "passed": 718,
    "failed": 1,
    "skipped": 6,
    "failed_tests": [
      {
        "class_name": "buildgit_status_follow.bats",
        "test_name": "follow_completed_build_shows_console_url",
        "duration_seconds": 0.545,
        "age": 1,
        "error_details": "assert_success failed",
        "error_stack_trace": "(from function `assert_success' ...full untruncated trace...)",
        "stdout": "[22:54:28] ℹ Follow mode enabled (once, timeout=10s)...\n[22:54:28] ℹ Waiting for Jenkins build...\n..."
      }
    ]
  }
}
```

#### Jenkins API source

The `stdout` field comes from the Jenkins test report API field `suites[].cases[].stdout`. This field is already available in the API response but is not currently fetched or displayed by buildgit.

#### Examples

```bash
buildgit status 60 --all -v         # Full failure details, untruncated
buildgit status 60 --json -v        # JSON with full stdout/stderr for failed tests
buildgit status --all -v            # Latest build, verbose failure output
```

### Feature 2: `--console-text` shows raw console output for a build or stage

Add a new option `--console-text [stage-name]` to `buildgit status` that retrieves and outputs the raw Jenkins console text.

#### Behavior

| Usage | Output |
|-------|--------|
| `buildgit status 60 --console-text` | Full console text for build #60 |
| `buildgit status 60 --console-text "Unit Tests D"` | Console text for the "Unit Tests D" stage only |
| `buildgit status --console-text` | Full console text for the latest build |

#### Stage filtering

When a stage name is provided:
- Use the Jenkins Pipeline `wfapi` nodes endpoint to find the stage's node ID
- Fetch the stage-specific log via the `log` endpoint for that node
- Match stage names aggressively:
  - exact match first
  - case-insensitive exact match second
  - unique case-insensitive partial match third
  - if multiple stages match the partial text, fail and list the matching stage names instead of guessing
- If the matched stage's own `wfapi/log` payload is empty, recursively inspect descendant stage/substage nodes and emit the first non-empty descendant logs in pipeline order
- When descendant fallback emits multiple child stage logs, separate them with lightweight `===== Parent -> Child =====` headers so the source stage is obvious
- If the stage name doesn't match any stage, print an error listing available stage names

#### Console text output

- Output goes to stdout (no banners, no formatting, raw text)
- This makes it pipeable: `buildgit status 60 --console-text "Unit Tests D" | grep "not ok"`
- Exit code 0 on success, 1 if build/stage not found

#### Examples

```bash
# Get full console for a build
buildgit status 60 --console-text

# Get console for a specific parallel stage
buildgit status 60 --console-text "Unit Tests D"

# Grep for a failing test in a stage
buildgit status 60 --console-text "Unit Tests D" | grep -A 20 "not ok"

# Agent workflow: find what failed, then drill into the stage
buildgit status 60 --json -v | jq '.test_results.failed_tests[0]'
buildgit status 60 --console-text "Unit Tests D" | grep -A 20 "follow_completed_build"
```

### Feature 3: `--list-stages` shows available stage names

Add `--list-stages` to `buildgit status` to list all pipeline stage names for a build. This helps agents discover the correct stage name for `--console-text`.

#### Behavior

```bash
$ buildgit status 60 --list-stages
Build
Unit Tests A
Unit Tests B
Unit Tests C
Unit Tests D
Unit Tests
Deploy
```

- One stage per line, plain text, no formatting
- Includes parallel branch names and wrapper stages
- With `--json`, outputs a JSON array of stage objects (reuses existing stage data)

### Option compatibility matrix

| Option | `--all` | `--json` | `--line` | `-f` | `-v` |
|--------|---------|----------|----------|------|------|
| `--console-text` | N/A (exclusive) | N/A (exclusive) | N/A (exclusive) | No | No |
| `--list-stages` | N/A (exclusive) | Outputs JSON array | N/A (exclusive) | No | No |
| `-v` (verbose) | Untruncated output | Untruncated + stdout | No effect | No effect | - |

`--console-text` and `--list-stages` are exclusive options — they produce their own output format and cannot be combined with `--all`, `--line`, or `-f`.

## Test Strategy

### Unit Tests

New test file: `test/buildgit_agent_diagnostics.bats`

**Verbose test output:**
- `status_verbose_shows_full_stack_trace` — `-v --all` does not truncate error_stack_trace
- `status_verbose_json_includes_stdout` — `-v --json` includes `stdout` field for failed tests
- `status_verbose_json_stdout_untruncated` — `-v --json` stdout field is not truncated
- `status_nonverbose_truncates_as_before` — without `-v`, truncation unchanged

**Console text:**
- `status_console_text_outputs_raw` — `--console-text` outputs raw text, no banners
- `status_console_text_specific_stage` — `--console-text "Stage Name"` filters to stage
- `status_console_text_unknown_stage_lists_available` — unknown stage name shows error with available stages
- `status_console_text_parent_stage_falls_back_to_substages` — empty parent stage log emits descendant substage logs in pipeline order
- `status_console_text_partial_match_is_case_insensitive` — lowercase/partial stage input resolves when one unique stage matches
- `status_console_text_ambiguous_stage_lists_matches` — ambiguous partial stage names fail with candidate matches
- `status_console_text_exit_code_success` — exit 0 on success
- `status_console_text_exit_code_not_found` — exit 1 when build not found

**List stages:**
- `status_list_stages_plain` — `--list-stages` outputs one stage per line
- `status_list_stages_json` — `--list-stages --json` outputs JSON array
- `status_list_stages_includes_parallel` — parallel branch names included

### Existing tests

All existing tests must continue to pass. The `-v` flag already exists as a global option so no new flag parsing is needed — just behavior changes in the output functions when `VERBOSE=true`.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
