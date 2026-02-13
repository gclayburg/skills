# Nested/Downstream Job Stage Display
Date: 2026-02-12T22:11:15-0700
References: specs/todo/feature-raw-nested-jobs.md
Supersedes: none

## Overview

When a pipeline job triggers downstream builds (via `build job:` steps), the current stage display shows only the parent stage name and its aggregate duration. This spec adds inline display of each downstream build's individual stages, with agent names, proper nesting indicators, and real-time monitoring support. The feature is recursive — downstream builds that trigger further downstream builds are displayed with increasing nesting depth.

## Problem Statement

Current output for an orchestrator pipeline that triggers downstream builds:

```
[18:00:18] ℹ   Stage: Build Handle (14s)    ← FAILED
```

This tells the user *that* Build Handle failed, but not *where* within the downstream build the failure occurred. The user must manually navigate to Jenkins to inspect the nested build.

## Solution

Display each downstream build's stages inline, indented under the parent stage, with the downstream agent name and a `->` separator indicating nesting:

```
[18:00:18] ℹ   Stage: [orchestrator1] Declarative: Checkout SCM (<1s)
[18:00:18] ℹ   Stage: [orchestrator1] Checkout (<1s)
[18:00:18] ℹ   Stage: [orchestrator1] Analyze Component Changes (<1s)
[18:00:18] ℹ   Stage: [orchestrator1] Trigger Component Builds (<1s)
[18:00:18] ℹ   Stage:   [buildagent9] Build Handle->Compile Code (18s)
[18:00:18] ℹ   Stage:   [buildagent9] Build Handle->Package Zip (20s)    ← FAILED
[18:00:18] ℹ   Stage: [orchestrator1] Build Handle (38s)    ← FAILED
[18:00:18] ℹ   Stage: [orchestrator1] Build SignalBoot (not executed)
[18:00:18] ℹ   Stage: [orchestrator1] Verify Docker Images (not executed)
[18:00:18] ℹ   Stage: [orchestrator1] Setup Handle (not executed)
[18:00:18] ℹ   Stage: [orchestrator1] Integration Tests (not executed)
[18:00:18] ℹ   Stage: [orchestrator1] E2E Tests (not executed)
```

Key elements:
- **Agent name prefix**: All stages show `[agent-name]` — top-level stages show the parent build's agent, nested stages show the downstream build's agent
- **Nesting indentation**: Each nesting level adds 2 spaces of indentation after `Stage:`
- **`->` separator**: Nested stage names use `ParentStage->NestedStage` format. For deeper nesting: `ParentStage->ChildStage->GrandchildStage`
- **Nested stages appear before their parent**: The downstream build's individual stages are printed as they complete, followed by the parent stage summary line when the downstream build finishes
- **All nested stages shown**: SUCCESS, FAILED, UNSTABLE, and NOT_EXECUTED stages from downstream builds are all displayed
- **Failed parent annotation**: When a downstream build fails, the parent stage that triggered it also shows `← FAILED`

## Scope

This specification applies to all build display commands:
- `buildgit status` (snapshot)
- `buildgit status -f/--follow` (monitoring)
- `buildgit push` (monitoring after push)
- `buildgit build` (trigger and monitor)
- `buildgit status --json` (JSON output)

Per the spec rules in specs/README.md, all output modes must remain consistent with each other.

## Display Format

### Nested Stage Line Format

```
[HH:MM:SS] ℹ   Stage: <indent>[agent-name] ParentStage->NestedStage (duration)
```

Where:
- `<indent>` = 2 spaces per nesting level (0 spaces for top-level, 2 for first nesting, 4 for second, etc.)
- `[agent-name]` = Jenkins node/agent that ran the build, in square brackets
- `ParentStage->NestedStage` = stage name hierarchy using `->` separator
- `(duration)` = same format as existing stages: `<1s`, `15s`, `2m 4s`, etc.

### Color Coding

Same as existing stage display (per full-stage-print-spec.md):
- SUCCESS: Green
- FAILED: Red, with `← FAILED` marker
- UNSTABLE: Yellow
- NOT_EXECUTED: Gray/dim
- IN_PROGRESS (running): Cyan/blue (verbose mode only)

### Parallel Downstream Builds

When the parent pipeline has parallel stages that each trigger downstream builds (e.g., `Build Handle` and `Build SignalBoot` running simultaneously):
- **Monitoring mode**: Interleave nested stages by completion time. As each downstream stage completes, print it immediately regardless of which parallel branch it belongs to.
- **Snapshot mode**: Order does not matter (display as returned by API).

Example with both parallel downstream builds succeeding:

```
[18:00:18] ℹ   Stage: [orchestrator1] Trigger Component Builds (<1s)
[18:00:20] ℹ   Stage:   [buildagent9] Build Handle->Checkout (<1s)
[18:00:21] ℹ   Stage:   [buildagent4] Build SignalBoot->Checkout (<1s)
[18:00:30] ℹ   Stage:   [buildagent9] Build Handle->Compile Code (10s)
[18:00:32] ℹ   Stage:   [buildagent4] Build SignalBoot->Compile (11s)
[18:00:40] ℹ   Stage:   [buildagent9] Build Handle->Package Zip (10s)
[18:00:41] ℹ   Stage:   [buildagent4] Build SignalBoot->Docker Build (9s)
[18:00:41] ℹ   Stage: [orchestrator1] Build Handle (21s)
[18:00:41] ℹ   Stage: [orchestrator1] Build SignalBoot (20s)
[18:00:42] ℹ   Stage: [orchestrator1] Verify Docker Images (1s)
```

### Running Indicator (Verbose Mode)

When `--verbose` is set, show `(running)` for in-progress nested stages:

```
[18:00:20] ℹ   Stage:   [buildagent9] Build Handle->Compile Code (running)
```

## Data Source and Stage-to-Downstream Mapping

### Overview

The Jenkins `wfapi/describe` API does not provide any field linking a parent stage to a downstream build. The mapping requires combining two data sources:

1. **`wfapi/describe`** — provides stage structure, statuses, and timing for any build
2. **Console output parsing** — provides the definitive mapping from parent stages to downstream builds

### Mapping Algorithm

For a given build:

1. **Fetch parent build stages** via `wfapi/describe` endpoint: `/job/{job_name}/{build_number}/wfapi/describe`
2. **Fetch parent build console output** via existing `get_console_output()`
3. **For each parent stage**, extract its console logs using `extract_stage_logs(console_output, stage_name)`
4. **Search stage logs** for the pattern `Starting building: <job-name> #<build-number>` using `detect_all_downstream_builds(stage_logs)`
5. **If a downstream build is found**, this creates the mapping: `parent_stage → (downstream_job, downstream_build_number)`
6. **Fetch downstream build info**:
   - Stages via `wfapi/describe` for the downstream job/build
   - Agent name via `Running on <agent>` pattern in downstream console output (using the existing `_parse_build_metadata()` pattern)
7. **Recurse**: Apply steps 1-6 to each downstream build to support arbitrary nesting depth

### Agent Name Extraction

Agent names are extracted from build console output using the existing pattern:
```
Running on <agent-name> in /path/to/workspace/...
```

This is the same method used by `_parse_build_metadata()` for the Build Info block. Each build (top-level and downstream) has its own agent name extracted from its own console output.

### Caching

During a single status check or monitoring poll cycle, the same downstream build information should not be fetched multiple times. Cache downstream build data (stages, console output, agent name) per `(job_name, build_number)` pair for the duration of one display cycle.

## Monitoring Mode Behavior

### Real-Time Downstream Stage Tracking

When monitoring a build (`push`, `build`, `status -f`):

1. **Poll parent build** via `wfapi/describe` at regular intervals (existing behavior)
2. **Detect in-progress parent stages** that have downstream builds (via stage-to-downstream mapping)
3. **Poll each active downstream build** via its own `wfapi/describe` at the same interval
4. **Track stage transitions** for downstream builds using the same `track_stage_changes()` logic as parent builds
5. **Print nested stage lines** as downstream stages complete, using the nested format
6. **When downstream build completes**, print the parent stage summary line

### Polling Strategy

- When a parent stage is `IN_PROGRESS` and is known to trigger a downstream build, begin polling the downstream build's `wfapi/describe`
- The downstream build may not exist yet (queued). Handle gracefully by retrying on next poll cycle
- Stop polling a downstream build once it reaches a terminal status (SUCCESS, FAILED, UNSTABLE, ABORTED)

### State Management

Extend the existing stage tracking to maintain state for multiple builds simultaneously:
- Parent build stage state (existing)
- One downstream build stage state per active downstream build (new)
- Each downstream build state is independently tracked and cleaned up when the downstream build completes

## Snapshot Mode Behavior

For `buildgit status` (one-shot):

1. Fetch parent build stages and console output
2. Build the stage-to-downstream mapping
3. For each parent stage that triggered a downstream build:
   a. Fetch downstream build stages and agent name
   b. Insert nested stage lines before the parent stage line
   c. Recurse for deeper nesting
4. Display all stages in order

## JSON Output

For `buildgit status --json`, the stages array includes nested stages as flat entries with additional fields:

```json
{
  "stages": [
    {
      "name": "Checkout",
      "status": "SUCCESS",
      "duration_ms": 500,
      "agent": "orchestrator1"
    },
    {
      "name": "Trigger Component Builds",
      "status": "SUCCESS",
      "duration_ms": 200,
      "agent": "orchestrator1"
    },
    {
      "name": "Build Handle->Compile Code",
      "status": "SUCCESS",
      "duration_ms": 18000,
      "agent": "buildagent9",
      "downstream_job": "phandlemono-handle",
      "downstream_build": 42,
      "parent_stage": "Build Handle",
      "nesting_depth": 1
    },
    {
      "name": "Build Handle->Package Zip",
      "status": "FAILED",
      "duration_ms": 20000,
      "agent": "buildagent9",
      "downstream_job": "phandlemono-handle",
      "downstream_build": 42,
      "parent_stage": "Build Handle",
      "nesting_depth": 1
    },
    {
      "name": "Build Handle",
      "status": "FAILED",
      "duration_ms": 38000,
      "agent": "orchestrator1",
      "has_downstream": true
    },
    {
      "name": "Build SignalBoot",
      "status": "NOT_EXECUTED",
      "duration_ms": 0,
      "agent": "orchestrator1"
    }
  ]
}
```

Fields added by this spec:
- `agent` (string): Jenkins node/agent name that ran this stage's build
- `downstream_job` (string, optional): Present only on nested stages — the downstream job name
- `downstream_build` (number, optional): Present only on nested stages — the downstream build number
- `parent_stage` (string, optional): Present only on nested stages — the parent stage name in the top-level build
- `nesting_depth` (number, optional): Present only on nested stages — 1 for first level, 2 for second, etc.
- `has_downstream` (boolean, optional): Present only on parent stages that triggered downstream builds

## Interaction with Failed Jobs Tree

The `=== Failed Jobs ===` section (per refactor-shared-failure-diagnostics-spec.md) is retained alongside the inline nested stage display. They serve complementary purposes:
- **Inline nested stages**: Show the full execution timeline with all stages (success and failure)
- **Failed Jobs tree**: Summarizes only the failure chain and identifies the root cause job

Both are displayed for failed builds.

## Interaction with Existing Downstream Detection

The existing `detect_all_downstream_builds()` and `find_failed_downstream_build()` functions remain unchanged. This spec adds a new layer that:
1. Uses `detect_all_downstream_builds()` at the per-stage level (via `extract_stage_logs()`) instead of on the full console output
2. Fetches downstream build stages for display purposes (not just for failure analysis)

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jenkins-common.sh` | Add stage-to-downstream mapping function. Add nested stage fetching and display functions. Extend `print_stage_line()` to support indentation, agent prefix, and `->` name format. Extend `get_all_stages()` or add wrapper to include nested stages. Add agent name to stage data. |
| `buildgit` | Extend monitoring loop to poll downstream builds. Extend `_handle_build_completion()` snapshot display to include nested stages. Extend `output_json()` to include nested stage fields. |

## Acceptance Criteria

1. **Nested stages displayed inline**: Downstream build stages appear indented under their parent stage with `[agent] Parent->Child` format
2. **All stages shown**: SUCCESS, FAILED, UNSTABLE, and NOT_EXECUTED nested stages are all displayed
3. **Agent names on all stages**: Both top-level and nested stages show `[agent-name]` prefix
4. **Real-time monitoring**: In follow/monitoring mode, downstream stages appear as they complete (not batched at end)
5. **Parallel interleaving**: Parallel downstream builds interleave stages by completion time in monitoring mode
6. **Recursive support**: A downstream build that triggers further downstream builds shows additional nesting levels
7. **Snapshot consistency**: `buildgit status` shows the same nested stage information as monitoring mode
8. **JSON output**: `buildgit status --json` includes nested stages as flat entries with `downstream_job`, `downstream_build`, `parent_stage`, `nesting_depth`, and `agent` fields
9. **Failed Jobs tree preserved**: The `=== Failed Jobs ===` section continues to appear for failed builds alongside nested stage display
10. **Verbose running indicator**: `--verbose` shows `(running)` for in-progress nested stages
11. **Graceful degradation**: If a downstream build's API is unreachable, show the parent stage normally without nested expansion (do not fail the entire display)

## Testing

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| Stage-to-downstream mapping | Mock console output with `Starting building:` patterns inside specific stage logs; verify correct stage-to-job mapping |
| Nested stage line formatting | Verify `print_stage_line()` produces correct indentation, agent prefix, and `->` name format at various nesting depths |
| Parallel downstream interleaving | Mock two downstream builds with interleaved completion times; verify output order matches completion time |
| Recursive nesting display | Mock a 3-level deep nesting; verify indentation and `->` chaining (e.g., `A->B->C`) |
| JSON nested stage fields | Verify JSON output includes `downstream_job`, `parent_stage`, `nesting_depth`, and `agent` fields on nested stages |
| Agent name extraction | Verify agent name is correctly extracted from downstream build console output |
| No downstream builds | Verify a simple pipeline with no downstream builds displays identically to current behavior (with added agent prefix) |
| Not-executed nested stages | Verify downstream build stages with NOT_EXECUTED status are displayed |
| Graceful degradation | Mock a downstream API failure; verify parent stage displays normally without nested expansion |

### Manual Testing Checklist

- [ ] `buildgit status` for orchestrator pipeline shows nested stages from downstream builds
- [ ] `buildgit push` for orchestrator pipeline shows nested stages in real-time as downstream builds progress
- [ ] `buildgit status -f` shows nested stages during monitoring
- [ ] `buildgit status --json` includes nested stage entries with correct fields
- [ ] Parallel downstream builds interleave correctly in monitoring mode
- [ ] Failed downstream build shows `← FAILED` on both the nested stage and the parent stage
- [ ] Agent names are correct for both top-level and nested stages
- [ ] Simple pipeline (no downstream) still works correctly (with agent prefix addition)
- [ ] `--verbose` shows `(running)` for in-progress nested stages

## Related Specifications

- `full-stage-print-spec.md` — Base stage display format (extended by this spec)
- `unify-follow-log-spec.md` — Unified monitoring output format
- `refactor-shared-failure-diagnostics-spec.md` — Failed Jobs tree and shared failure diagnostics
- `bug-status-json-spec.md` — JSON output format for builds
- `buildgit-spec.md` — Overall buildgit command structure
