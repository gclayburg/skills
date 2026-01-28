# Bug Fix: Jenkins Stage Log Truncation

## Overview

When a Jenkins build fails or becomes UNSTABLE, the `pushmon.sh` script displays stage-specific logs to help diagnose the failure. Currently, the log extraction is too aggressive, truncating the output before showing the actual failure reason.

## Problem Statement

### Current Behavior

When displaying failed stage logs, `pushmon.sh` shows only a small portion of the stage output:

```
=== Stage 'Unit Tests' Logs ===
[Pipeline] dir
Running in /home/jenkins/workspace/ralph1/jbuildmon
[Pipeline] {
[Pipeline] sh
+ ./test/bats/bin/bats --formatter junit test/smoke.bats test/test_helper.bats
+ true
=================================
```

### Expected Behavior

The stage logs should include all output from the failed stage, including:
- All shell command output
- Test results and failure messages
- Pipeline markers showing stage completion

The expected output should look like:

```
=== Stage 'Unit Tests' Logs ===
[Pipeline] dir
Running in /home/jenkins/workspace/ralph1/jbuildmon
[Pipeline] {
[Pipeline] sh
+ ./test/bats/bin/bats --formatter junit test/smoke.bats test/test_helper.bats
+ true
[Pipeline] }
[Pipeline] // dir
Post stage
[Pipeline] junit
Recording test results
[Checks API] No suitable checks publisher found.
=================================
```

### Impact

- Developers cannot see the actual failure reason from the terminal output
- Users must manually visit the Jenkins console URL to diagnose failures
- Defeats the purpose of the automated failure analysis feature

---

## Root Cause Analysis

The log extraction logic uses Pipeline markers to identify stage boundaries:
- Start marker: `[Pipeline] { (StageName)`
- End marker: `[Pipeline] }`

However, the current implementation appears to stop at the first `[Pipeline] }` encountered, which may be a nested block (like `[Pipeline] {` from `dir` step) rather than the actual stage end marker.

### Pipeline Nesting Example

```
[Pipeline] { (Unit Tests)           <-- Stage start
[Pipeline] dir
Running in /path/to/workspace
[Pipeline] {                        <-- Nested block start (dir)
[Pipeline] sh
+ command output here
[Pipeline] }                        <-- Nested block end (INCORRECTLY matched as stage end)
[Pipeline] // dir
Post stage
[Pipeline] junit
...
[Pipeline] }                        <-- Actual stage end
[Pipeline] // stage
```

---

## Technical Requirements

### 1. Improve Stage Log Extraction

The log extraction must correctly handle nested Pipeline blocks:

| Requirement | Description |
|-------------|-------------|
| Track nesting depth | Maintain a counter for nested `{` and `}` markers |
| Match stage boundaries | Only consider stage complete when nesting returns to 0 |
| Include post-stage actions | Capture `Post stage` actions that appear after nested blocks |

### 2. Extraction Algorithm

```
1. Find stage start: "[Pipeline] { (StageName)"
2. Initialize nesting_depth = 1
3. For each subsequent line:
   a. If line matches "[Pipeline] {", increment nesting_depth
   b. If line matches "[Pipeline] }", decrement nesting_depth
   c. If nesting_depth == 0, stop (stage complete)
   d. Include line in output
4. Return collected lines
```

### 3. Edge Cases

| Case | Handling |
|------|----------|
| Stage with no nested blocks | Works normally (single `{` and `}`) |
| Deeply nested blocks | Track all nesting levels correctly |
| Stage end not found | Fall back to showing remaining output up to next stage or end |
| Post-stage section | Include lines between last nested `}` and stage `}` |

### 4. Fallback Behavior

If stage extraction fails or produces insufficient output (< 5 lines):

1. Show last N lines of console output (configurable, default 50)
2. Include a message indicating extraction may be incomplete
3. Always provide the full console URL for reference

---

## Affected Components

| File | Function/Section |
|------|------------------|
| `pushmon.sh` | `extract_stage_logs()` or equivalent log extraction function |

---

## Acceptance Criteria

1. **Nested blocks handled**: Stage logs include content from all nested Pipeline blocks
2. **Post-stage included**: `Post stage` actions (like `junit`) are visible in output
3. **No truncation**: All lines from stage start to stage end are displayed
4. **Fallback works**: If extraction fails, show last 50 lines with explanation
5. **Existing tests pass**: No regression in other failure analysis scenarios

---

## Test Plan

### Manual Verification

1. Trigger a build with failing unit tests
2. Verify stage logs show complete output including:
   - All nested `[Pipeline] {` and `}` blocks
   - `Post stage` section
   - `junit` recording step
3. Verify the full console URL is still provided

### Unit Test Cases

| Test Case | Description |
|-----------|-------------|
| `extract_simple_stage` | Single stage with no nesting extracts correctly |
| `extract_nested_stage` | Stage with `dir` block includes all nested content |
| `extract_deeply_nested` | Multiple nesting levels handled correctly |
| `extract_with_post_stage` | Post-stage actions are included |
| `extract_fallback` | Insufficient extraction triggers fallback |

---

## References

- Parent spec: [jenkins-build-monitor-spec.md](./jenkins-build-monitor-spec.md), Section 7.3 "Log Extraction Priority"
- Bug report: [bug1-jenkins-log-truncated.md](./bug1-jenkins-log-truncated.md)
