# Parallel Stages Display Fix and Enhancement
Date: 2026-02-13T16:20:00-0700
References: specs/done-reports/bug-show-paralel-stages.md
Supersedes: none (amends nested-jobs-display-spec.md)

## Overview

When a Jenkins pipeline uses `parallel { }` blocks (e.g., "Build Handle" and "Build SignalBoot" running simultaneously under a "Trigger Component Builds" wrapper stage), buildgit monitoring mode fails to track and display all parallel branch stages correctly. Additionally, parallel stages are not visually distinguished from sequential stages, and the wrapper stage duration is misleading.

## Problem Statement

### Bug 1: Monitoring Mode Prematurely Prints Parallel Stages

In monitoring mode (`buildgit build`, `buildgit push`, `buildgit status -f`), parallel branch stages are printed before they complete. Observed output:

```
[15:34:28] ℹ   Stage: [agent8_sixcore] Build SignalBoot (unknown)
```

Build SignalBoot was still running (it took 3m 24s total) but was printed at 15:34:28 with `(unknown)` duration. The stage tracker does not properly handle multiple stages in `IN_PROGRESS` state simultaneously.

### Bug 2: Missing Nested Downstream Stages for Parallel Branches

Because Build SignalBoot was prematurely "closed" in the stage tracker, its nested downstream stages (from `phandlemono-signalboot`) were never fetched or displayed. Only Build Handle's downstream stages appeared.

### Bug 3: Wrapper Stage Duration Shows API Duration Only

The wrapper stage "Trigger Component Builds" displays `(<1s)` because the `wfapi/describe` API reports its duration as 114ms — the time to set up the parallel block, not the time the parallel work actually took (3m 24s).

### Missing Feature: No Visual Distinction for Parallel Stages

There is no indication in the output that "Build Handle" and "Build SignalBoot" ran in parallel vs sequentially. Users cannot tell from the display alone.

## Data Model

### Jenkins wfapi/describe for Parallel Stages

Jenkins represents parallel stages as **flat siblings** in the `stages[]` array. For a pipeline with:

```groovy
stage('Trigger Component Builds') {
    parallel {
        stage('Build Handle') { ... }
        stage('Build SignalBoot') { ... }
    }
}
```

The `wfapi/describe` response returns:

```json
{
  "stages": [
    {"name": "Analyze Component Changes", "status": "SUCCESS", "durationMillis": 265, ...},
    {"name": "Trigger Component Builds", "status": "SUCCESS", "durationMillis": 114, ...},
    {"name": "Build Handle", "status": "FAILED", "startTimeMillis": 1771022065502, "durationMillis": 9524, ...},
    {"name": "Build SignalBoot", "status": "SUCCESS", "startTimeMillis": 1771022065514, "durationMillis": 204741, ...},
    {"name": "Verify Docker Images", "status": "FAILED", ...}
  ]
}
```

Key observations:
- The wrapper stage ("Trigger Component Builds") has a short duration (114ms) — just the setup time
- Parallel branch stages ("Build Handle", "Build SignalBoot") appear as flat siblings with nearly identical `startTimeMillis` values
- The API does **not** indicate which stages are parallel branches or which wrapper they belong to

### Parallel Stage Detection

Since the API does not explicitly mark parallel stages, detection requires heuristics:

1. **Console log parsing**: Look for `[Pipeline] parallel` blocks in the build console output to identify which stages are parallel branches
2. **Overlapping startTimeMillis**: Stages with `startTimeMillis` values within a small threshold (e.g., <1000ms apart) that immediately follow a wrapper stage are likely parallel branches
3. **Combined approach** (recommended): Use console log parsing as the primary method, with overlapping timestamps as a fallback confirmation

The console log structure for parallel blocks is:

```
[Pipeline] { (Trigger Component Builds)
[Pipeline] parallel
[Pipeline] { (Branch: Build Handle)
...
[Pipeline] { (Branch: Build SignalBoot)
...
[Pipeline] } // end Branch: Build Handle
[Pipeline] } // end Branch: Build SignalBoot
[Pipeline] } // end Trigger Component Builds
```

The `(Branch: <name>)` markers in the console output definitively identify parallel branches and their wrapper stage.

## Solution

### 1. Fix Parallel Stage Tracking in Monitoring Mode

The stage tracker must handle multiple simultaneous `IN_PROGRESS` stages:

- Do **not** print a stage when it transitions to `IN_PROGRESS` (current behavior for sequential stages is correct)
- Only print a stage when it transitions from `IN_PROGRESS` to a terminal state (SUCCESS, FAILED, UNSTABLE)
- Track all `IN_PROGRESS` stages independently — one stage completing must not affect tracking of other in-progress stages
- For parallel downstream builds, poll and track each downstream build's stages independently and simultaneously

### 2. Fix Nested Downstream Stage Display for Parallel Branches

When parallel branch stages each trigger downstream builds:

- Detect downstream builds for **each** parallel branch independently
- Poll all active downstream builds in each monitoring cycle
- Interleave nested stages from parallel downstream builds by completion time (print each nested stage as it completes, regardless of which parallel branch it belongs to)
- Each parallel branch's downstream stages are properly attributed with the correct agent name and parent stage

### 3. Wrapper Stage Aggregate Duration

The wrapper stage that contains the parallel block should display the **aggregate wall-clock duration**: the wrapper's own API duration plus the duration of the longest parallel branch.

For the phandlemono-IT example:
- API wrapper duration: 114ms
- Longest branch: Build SignalBoot at 204,741ms (3m 24s)
- Aggregate: ~204,855ms → display as `3m 24s`

Formula: `wrapper_api_duration + max(branch_1_duration, branch_2_duration, ...)`

### 4. Visual Parallel Stage Indication

Parallel branch stages are displayed with both **indentation** and a **parallel marker**:

```
[HH:MM:SS] ℹ   Stage: <indent>║ [agent-name] StageName (duration)
```

Where:
- `<indent>` = 2 spaces of indentation (same depth as first-level nested stages)
- `║` = parallel indicator character (Unicode box-drawing: U+2551)
- Parallel branch stages appear between their wrapper stage's "start" (other stages before) and the wrapper stage summary line (printed last)

### 5. Wrapper Stage Printed Last

In monitoring mode, the wrapper stage is **not** printed when it first completes in the API (since its API duration is just the setup time). Instead, it is printed **after all its parallel branches have completed**, with the aggregate duration.

## Display Format

### Monitoring Mode Example (Successful Parallel Branches)

```
[18:00:18] ℹ   Stage: [orchestrator1] Declarative: Checkout SCM (<1s)
[18:00:18] ℹ   Stage: [orchestrator1] Checkout (<1s)
[18:00:18] ℹ   Stage: [orchestrator1] Analyze Component Changes (<1s)
[18:00:20] ℹ   Stage:   ║ [buildagent9] Build Handle->Checkout (<1s)
[18:00:21] ℹ   Stage:   ║ [buildagent4] Build SignalBoot->Checkout (<1s)
[18:00:30] ℹ   Stage:   ║ [buildagent9] Build Handle->Compile Code (10s)
[18:00:32] ℹ   Stage:   ║ [buildagent4] Build SignalBoot->Compile (11s)
[18:00:40] ℹ   Stage:   ║ [buildagent9] Build Handle->Package (10s)
[18:00:41] ℹ   Stage:   ║ [orchestrator1] Build Handle (21s)
[18:00:42] ℹ   Stage:   ║ [buildagent4] Build SignalBoot->Docker Build (9s)
[18:00:42] ℹ   Stage:   ║ [orchestrator1] Build SignalBoot (21s)
[18:00:42] ℹ   Stage: [orchestrator1] Trigger Component Builds (21s)
[18:00:43] ℹ   Stage: [orchestrator1] Verify Docker Images (1s)
```

Key elements:
- Parallel branches and their nested downstream stages are indented with `║` marker
- The wrapper stage "Trigger Component Builds" is printed last with aggregate duration
- Each parallel branch's summary line (e.g., "Build Handle (21s)") is also indented with `║`
- Stages from both branches interleave by completion time

### Monitoring Mode Example (One Branch Fails)

```
[15:34:27] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[15:34:27] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[15:34:28] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[15:34:33] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[15:34:38] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[15:34:38] ℹ   Stage:   ║ [agent8_sixcore] Build Handle (9s)    ← FAILED
[15:37:48] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot->Declarative: Checkout SCM (<1s)
[15:37:53] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot->Declarative: Post Actions (<1s)
[15:37:53] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot (3m 24s)
[15:37:53] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (3m 24s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Verify Docker Images (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Setup Handle (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Integration Tests (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] E2E Tests (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)
```

Note:
- Build Handle fails at 15:34:38, but monitoring continues for Build SignalBoot
- Build SignalBoot completes at 15:37:53, then the wrapper stage is printed
- The wrapper shows `← FAILED` because one of its branches failed

### Snapshot Mode Example

Snapshot mode (`buildgit status`) displays the same format. Since all data is fetched at once, order is determined by stage completion time.

### Verbose Mode

With `--verbose`, show `(running)` for in-progress parallel stages:

```
[18:00:20] ℹ   Stage:   ║ [buildagent9] Build Handle->Compile Code (running)
[18:00:20] ℹ   Stage:   ║ [buildagent4] Build SignalBoot->Compile (running)
```

### JSON Output

For `buildgit status --json`, parallel stages include additional fields:

```json
{
  "stages": [
    {
      "name": "Trigger Component Builds",
      "status": "FAILED",
      "duration_ms": 204855,
      "agent": "orchestrator1",
      "is_parallel_wrapper": true,
      "parallel_branches": ["Build Handle", "Build SignalBoot"]
    },
    {
      "name": "Build Handle->Declarative: Checkout SCM",
      "status": "SUCCESS",
      "duration_ms": 500,
      "agent": "agent8_sixcore",
      "downstream_job": "phandlemono-handle",
      "downstream_build": 42,
      "parent_stage": "Build Handle",
      "nesting_depth": 1,
      "parallel_branch": "Build Handle"
    },
    {
      "name": "Build Handle",
      "status": "FAILED",
      "duration_ms": 9524,
      "agent": "orchestrator1",
      "has_downstream": true,
      "parallel_branch": "Build Handle",
      "parallel_wrapper": "Trigger Component Builds"
    },
    {
      "name": "Build SignalBoot",
      "status": "SUCCESS",
      "duration_ms": 204741,
      "agent": "orchestrator1",
      "has_downstream": true,
      "parallel_branch": "Build SignalBoot",
      "parallel_wrapper": "Trigger Component Builds"
    }
  ]
}
```

New JSON fields added by this spec:
- `is_parallel_wrapper` (boolean, optional): Present on wrapper stages that contain parallel branches
- `parallel_branches` (string array, optional): Present on wrapper stages — lists the branch stage names
- `parallel_branch` (string, optional): Present on parallel branch stages and their nested stages — the branch name
- `parallel_wrapper` (string, optional): Present on parallel branch stages — the wrapper stage name

The wrapper stage `duration_ms` reflects the aggregate duration (not the raw API value).

## Scope

Per specs/README.md rules, all output modes must remain consistent:
- `buildgit status` (snapshot)
- `buildgit status -f/--follow` (monitoring)
- `buildgit push` (monitoring after push)
- `buildgit build` (trigger and monitor)
- `buildgit status --json` (JSON output)

## Implementation Notes

### Parallel Detection Function

Add a function `_detect_parallel_branches()` that:
1. Parses build console output for `[Pipeline] parallel` and `(Branch: <name>)` patterns
2. Returns a mapping: `wrapper_stage_name → [branch_stage_name_1, branch_stage_name_2, ...]`
3. Falls back to timestamp-based heuristic if console parsing fails

### Stage Tracker Changes

The existing `_track_nested_stage_changes()` function must be updated:
1. Maintain a set of **all** currently `IN_PROGRESS` stages (not just one)
2. When a stage transitions to `IN_PROGRESS`, add it to the set
3. When a stage transitions to terminal status, remove from the set and print
4. A parallel branch completing does not close the wrapper stage — the wrapper is only printed when **all** branches reach terminal status
5. Downstream build polling must continue for all active parallel branches, not just the first one found

### Wrapper Stage Deferred Printing

1. When the wrapper stage reaches terminal status in `wfapi/describe`, do **not** print it yet
2. Check if all parallel branches have reached terminal status
3. Only when all branches are done, calculate aggregate duration and print the wrapper line
4. If the build itself completes (reaches terminal status), force-print any deferred wrapper stages

### Aggregate Duration Calculation

```
aggregate_duration = wrapper_api_duration + max(branch_durations)
```

Where `branch_durations` are the `durationMillis` values from each parallel branch stage in `wfapi/describe`.

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jenkins-common.sh` | Add `_detect_parallel_branches()` function. Update `_track_nested_stage_changes()` to handle multiple simultaneous IN_PROGRESS stages. Update `print_stage_line()` to support `║` parallel marker. Add wrapper stage deferred printing logic. Add aggregate duration calculation. Update `_get_nested_stages()` to identify and mark parallel stages. |
| `buildgit` | Update monitoring loop to continue polling all parallel downstream builds. Update `output_json()` to include parallel stage fields. |

## Acceptance Criteria

1. **No premature stage printing**: Parallel stages in IN_PROGRESS state are not printed until they complete
2. **All parallel branches tracked**: Both (or all) parallel branch stages are independently tracked through completion
3. **Nested downstream stages for all branches**: Each parallel branch's downstream build stages are fetched and displayed
4. **Real-time interleaving**: Nested stages from parallel downstream builds interleave by completion time in monitoring mode
5. **Visual parallel indicator**: Parallel branch stages display with indentation and `║` marker
6. **Wrapper stage printed last**: Wrapper stage appears after all parallel branches complete, with aggregate duration
7. **Aggregate duration**: Wrapper duration = API wrapper duration + longest branch duration
8. **Snapshot consistency**: `buildgit status` shows the same parallel formatting as monitoring mode
9. **JSON parallel fields**: `buildgit status --json` includes `is_parallel_wrapper`, `parallel_branches`, `parallel_branch`, and `parallel_wrapper` fields
10. **Graceful degradation**: If parallel detection fails (console parsing error), display stages without parallel indicators (fall back to current flat display with fixed tracking)
11. **Multiple pipelines**: Works for any pipeline with parallel stages, not just phandlemono-IT
12. **Failed branch continues**: When one parallel branch fails, monitoring continues for remaining branches until all complete

## Testing

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| Parallel detection from console | Mock console output with `[Pipeline] parallel` and `(Branch: X)` patterns; verify correct wrapper-to-branches mapping |
| Parallel detection fallback | Mock console without parallel markers; verify timestamp-based heuristic identifies overlapping stages |
| Stage tracker multiple IN_PROGRESS | Simulate two stages simultaneously IN_PROGRESS; verify neither is printed until it reaches terminal status |
| Wrapper deferred printing | Simulate wrapper reaching SUCCESS while branches still IN_PROGRESS; verify wrapper is not printed until all branches complete |
| Aggregate duration calculation | Verify wrapper duration = API duration + max(branch durations) for various branch timing combinations |
| Parallel marker formatting | Verify `print_stage_line()` produces `║` marker with correct indentation for parallel branches |
| Parallel + nested downstream | Verify parallel branches with downstream builds show nested stages with both `║` marker and `->` nesting |
| JSON parallel fields | Verify JSON output includes `is_parallel_wrapper`, `parallel_branches`, `parallel_branch`, `parallel_wrapper` |
| One branch fails, other succeeds | Verify monitoring continues after one branch fails until all branches complete |
| No parallel stages | Verify a simple pipeline with no parallel blocks displays identically to current behavior |

### Manual Testing Checklist

- [ ] `buildgit build` on phandlemono-IT shows parallel branches with `║` marker
- [ ] Both Build Handle and Build SignalBoot nested stages appear in monitoring mode
- [ ] Build SignalBoot stages continue to appear after Build Handle fails
- [ ] Wrapper stage "Trigger Component Builds" prints after both branches complete with aggregate duration
- [ ] `buildgit status` for same build shows matching parallel formatting
- [ ] `buildgit status --json` includes parallel-specific fields
- [ ] Simple pipeline (ralph1) without parallel stages still works correctly
- [ ] `--verbose` shows `(running)` for in-progress parallel stages

## Related Specifications

- `nested-jobs-display-spec.md` — Base nested/downstream stage display (this spec amends the parallel handling)
- `full-stage-print-spec.md` — Base stage display format
- `unify-follow-log-spec.md` — Unified monitoring output format
- `bug-status-json-spec.md` — JSON output format for builds
