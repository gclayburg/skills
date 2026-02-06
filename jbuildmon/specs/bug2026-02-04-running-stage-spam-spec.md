# Bug: Running Stage Printed on Every Poll Cycle
Date: 2026-02-04

## Summary

During build monitoring (`buildgit push`, `buildgit build`, `buildgit status -f`), the currently running stage is printed on every poll cycle (every 5 seconds), creating excessive noise in the terminal output.

## Observed Behavior

```
[18:59:38] ℹ   Stage: Unit Tests (running)
[18:59:43] ℹ   Stage: Unit Tests (running)
[18:59:48] ℹ   Stage: Unit Tests (running)
[18:59:53] ℹ   Stage: Unit Tests (running)
[18:59:58] ℹ   Stage: Unit Tests (running)
[19:00:04] ℹ   Stage: Unit Tests (running)
```

For a stage that runs for 2 minutes, this produces ~24 identical lines.

## Expected Behavior

### Non-verbose mode (default)

Do NOT print "(running)" status at all. Only print stages when they complete (transition from IN_PROGRESS to SUCCESS/FAILED/UNSTABLE/ABORTED).

Expected output (non-verbose):
```
[19:01:40] ℹ   Stage: Unit Tests (2m 2s)
```

### Verbose mode (`--verbose`)

Print "(running)" exactly once when a stage first starts, then print completion when it finishes.

Expected output (verbose):
```
[18:59:38] ℹ   Stage: Unit Tests (running)
[19:01:40] ℹ   Stage: Unit Tests (2m 2s)
```

## Root Cause

In `lib/jenkins-common.sh`, the `track_stage_changes` function (lines ~1540-1590) prints the running stage on every poll after the first:

```bash
# Print currently running stage (if any and verbose mode enabled)
if [[ -n "$running_stage_name" ]]; then
    local prev_count
    prev_count=$(echo "$previous_stages_json" | jq 'length')

    if [[ "$prev_count" -gt 0 || "$verbose" == "true" ]]; then
        print_stage_line "$running_stage_name" "IN_PROGRESS" >&2
    fi
fi
```

The condition `prev_count -gt 0` is true on every poll after the first, causing the running stage to be printed repeatedly even in non-verbose mode.

## Affected Code

- **File**: `jbuildmon/lib/jenkins-common.sh`
- **Function**: `track_stage_changes()` (approximately lines 1506-1591)

## Fix Requirements

1. **Non-verbose mode**: Never print "(running)" status - only print when stages complete
2. **Verbose mode**: Print "(running)" exactly once when a stage first transitions to IN_PROGRESS
3. Continue printing stage completion (SUCCESS/FAILED/etc.) when the stage finishes (both modes)

## Proposed Solution

Modify `track_stage_changes` to only print running stages in verbose mode:

```bash
IN_PROGRESS)
    # Only print running stage in verbose mode, and only once when it first starts
    if [[ "$verbose" == "true" && "$previous_status" == "NOT_EXECUTED" ]]; then
        print_stage_line "$stage_name" "IN_PROGRESS" >&2
    fi
    ;;
```

Remove the unconditional running stage print block at the end of the function.

## Testing

1. Run `buildgit push` (non-verbose) with a multi-stage pipeline
   - Verify NO "(running)" lines appear
   - Verify each stage shows duration only when it completes
2. Run `buildgit --verbose push` with a multi-stage pipeline
   - Verify each stage shows "(running)" exactly once when it starts
   - Verify each stage shows duration when it completes
3. Verify no duplicate lines for the same stage status in either mode

## Spec Reference

- `full-stage-print-spec.md` - Stage Display Format, In-Progress Stages
