# Full Stage Print Specification
Date: 2026-02-02

## Overview

All commands that display build status should show a complete, concise summary of pipeline stages with their durations. Stages are only printed once they complete (or when determining final build status), ensuring users always see accurate timing information.

## Scope

This specification applies to all build-monitoring functionality:
- `buildgit push` (monitors build after push)
- `buildgit build` (triggers and monitors build)
- `buildgit status -f/--follow` (continuous monitoring)
- `buildgit status` (one-shot status of completed/in-progress builds)

## Stage Display Format

### Completed Stages

Completed stages are displayed with slight indentation and include duration:

```
[HH:MM:SS] ℹ   Stage: <name> (<duration>)
```

**Color coding:**
- SUCCESS stages: Green
- FAILED stages: Red
- UNSTABLE stages: Yellow

**Duration format:**
- Sub-second durations: `<1s`
- Seconds only: `15s`
- Minutes and seconds: `2m 4s`
- Hours, minutes, seconds: `1h 5m 30s`

### In-Progress Stages

When a stage is currently executing, display it without duration:

```
[HH:MM:SS] ℹ   Stage: <name> (running)
```

The `(running)` indicator should be displayed in cyan/blue to distinguish from completed stages.

### Not-Executed Stages

For failed builds where some stages were never executed:

```
[HH:MM:SS] ℹ   Stage: <name> (not executed)
```

Display in gray/dim color to indicate skipped status.

## Example Output

### Successful Build (all stages complete)

```
[16:44:23] ℹ   Stage: Initialize Submodules (10s)
[16:44:39] ℹ   Stage: Build (15s)
[16:46:41] ℹ   Stage: Unit Tests (2m 2s)
[16:46:42] ℹ   Stage: Deploy (<1s)
```

### Build In Progress

```
[16:44:23] ℹ   Stage: Initialize Submodules (10s)
[16:44:39] ℹ   Stage: Build (15s)
[16:44:39] ℹ   Stage: Unit Tests (running)
```

### Failed Build

```
[16:44:23] ℹ   Stage: Initialize Submodules (10s)
[16:44:39] ℹ   Stage: Build (15s)
[16:46:41] ℹ   Stage: Unit Tests (2m 2s)    ← FAILED
[16:46:41] ℹ   Stage: Deploy (not executed)
```

The `← FAILED` marker should be in red.

## Behavior by Command

### `buildgit push` and `buildgit build`

During build monitoring:
1. Poll Jenkins wfapi/describe endpoint at regular intervals
2. Track stage status changes between polls
3. When a stage transitions from `IN_PROGRESS` to `SUCCESS`/`FAILED`/`UNSTABLE`, print the stage line with duration
4. Show currently running stage with `(running)` indicator
5. When build completes, show any not-executed stages

**Verbose mode (`--verbose`):**
- Include periodic "Build in progress... (60s elapsed)" messages
- These messages appear between stage completion lines

**Non-verbose mode (default):**
- Only show stage completion lines
- No periodic elapsed time messages

### `buildgit status -f/--follow`

Same behavior as push/build monitoring:
1. If a build is in progress, show completed stages and current stage
2. Continue monitoring until build completes
3. Show final stage summary
4. Wait for next build and repeat

### `buildgit status` (one-shot)

For completed builds:
- Fetch all stages from wfapi/describe
- Display all stages with their durations and statuses
- Include not-executed stages if build failed

For in-progress builds:
- Show completed stages with durations
- Show currently running stage with `(running)`
- Exit (does not follow)

## Implementation Requirements

### Stage Tracking

The implementation must track stage state across polling intervals:

1. **Previous state**: Store the last known status of each stage
2. **Current state**: Fetch current status from wfapi/describe
3. **Transitions**: Detect when `status` changes:
   - `NOT_EXECUTED` → `IN_PROGRESS`: Stage started (don't print yet)
   - `IN_PROGRESS` → `SUCCESS`: Print stage with duration (green)
   - `IN_PROGRESS` → `FAILED`: Print stage with duration + marker (red)
   - `IN_PROGRESS` → `UNSTABLE`: Print stage with duration (yellow)

### API Data Source

Use Jenkins wfapi/describe endpoint which provides:
- `stages[].name`: Stage name
- `stages[].status`: NOT_EXECUTED, IN_PROGRESS, SUCCESS, FAILED, UNSTABLE, ABORTED, PAUSED_PENDING_INPUT
- `stages[].startTimeMillis`: When stage started (epoch ms)
- `stages[].durationMillis`: How long stage took (ms)

### Duration Calculation

- For completed stages: Use `durationMillis` from API
- Format using existing `format_duration` function, modified to handle sub-second values

### New Function Requirements

1. **`get_all_stages`**: Fetch all stages with their statuses and timing from wfapi/describe
2. **`format_stage_duration`**: Format milliseconds to human-readable, with `<1s` for sub-second
3. **`print_stage_line`**: Output a single stage line with appropriate color and format
4. **`track_stage_changes`**: Compare previous/current state and print completed stages

## Integration Points

### Affected Functions

These functions in `buildgit` currently call `get_current_stage` and need updating:
- `_push_monitor_build` (line ~694)
- `_follow_monitor_build` (line ~342)
- `_build_monitor` (line ~965)

### Affected Library Functions

In `lib/jenkins-common.sh`:
- `get_current_stage`: May be replaced or augmented by new `get_all_stages`
- Add new stage tracking and formatting functions

### Display Functions

Update these to include stage summary:
- `display_success_output`
- `display_failure_output`
- `display_building_output`

## Backward Compatibility

- The `--verbose` flag behavior changes: elapsed time messages now require `--verbose`
- Stage output format changes from single "current stage" to full stage list
- These are enhancements, not breaking changes to command-line interface

## Testing Requirements

1. **Unit tests**: Test stage formatting functions with various durations
2. **Integration tests**: Verify stage tracking across simulated poll cycles
3. **Manual testing**: Verify color output and formatting in terminal
