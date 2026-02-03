# Full Stage Print Implementation Plan

Implementation plan for [full-stage-print-spec.md](./full-stage-print-spec.md)

## Contents

- [x] **Chunk A: Stage Duration Formatting Functions**
- [x] **Chunk B: Stage Data Retrieval Function**
- [x] **Chunk C: Stage Line Printing Function**
- [x] **Chunk D: Stage Change Tracking Function**
- [x] **Chunk E: Update Monitoring Functions**
- [x] **Chunk F: Update Display Output Functions**

---

## Chunk Detail

---

- [x] **Chunk A: Stage Duration Formatting Functions**

### Description

Create the `format_stage_duration` function that formats milliseconds to human-readable duration with support for sub-second values (`<1s`). This extends the existing `format_duration` function with sub-second handling.

### Spec Reference

See spec [Duration format](./full-stage-print-spec.md#completed-stages) in Stage Display Format section.

### Dependencies

- None

### Produces

- `lib/jenkins-common.sh` (add `format_stage_duration` function)
- `test/stage_duration.bats`

### Implementation Details

1. Create `format_stage_duration` function in `lib/jenkins-common.sh`:
   - Input: duration in milliseconds
   - For values < 1000ms: return `<1s`
   - For values >= 1000ms: delegate to existing `format_duration` logic
   - Handle edge cases: empty, null, non-numeric input

2. Function signature:
   ```bash
   # Format stage duration from milliseconds to human-readable format
   # Usage: format_stage_duration 154000
   # Returns: "2m 34s", "45s", "<1s", "1h 5m 30s", or "unknown"
   format_stage_duration() {
       local ms="$1"
       # Implementation...
   }
   ```

### Test Plan

**Test File:** `test/stage_duration.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `format_stage_duration_sub_second` | Duration < 1000ms returns `<1s` | Duration format |
| `format_stage_duration_seconds_only` | Duration 15000ms returns `15s` | Duration format |
| `format_stage_duration_minutes_seconds` | Duration 124000ms returns `2m 4s` | Duration format |
| `format_stage_duration_hours` | Duration 3930000ms returns `1h 5m 30s` | Duration format |
| `format_stage_duration_zero` | Duration 0ms returns `<1s` | Duration format |
| `format_stage_duration_empty` | Empty input returns `unknown` | Duration format |
| `format_stage_duration_null` | Null input returns `unknown` | Duration format |
| `format_stage_duration_invalid` | Non-numeric returns `unknown` | Duration format |

**Mocking Requirements:**
- None (pure function)

**Dependencies:** None

---

- [x] **Chunk B: Stage Data Retrieval Function**

### Description

Create the `get_all_stages` function that fetches all stages with their statuses, timing, and durations from the Jenkins wfapi/describe endpoint. Returns structured data suitable for stage tracking.

### Spec Reference

See spec [API Data Source](./full-stage-print-spec.md#api-data-source) and [New Function Requirements](./full-stage-print-spec.md#new-function-requirements).

### Dependencies

- None (uses existing `jenkins_api` function)

### Produces

- `lib/jenkins-common.sh` (add `get_all_stages` function)
- `test/stage_retrieval.bats`

### Implementation Details

1. Create `get_all_stages` function in `lib/jenkins-common.sh`:
   - Input: job_name, build_number
   - Calls wfapi/describe endpoint
   - Extracts stages array with: name, status, startTimeMillis, durationMillis
   - Returns JSON array of stage objects on stdout
   - Returns empty JSON array `[]` on error

2. Function signature:
   ```bash
   # Fetch all stages with statuses and timing from wfapi/describe
   # Usage: get_all_stages "job-name" "build-number"
   # Returns: JSON array of stage objects on stdout
   #          Each object has: name, status, startTimeMillis, durationMillis
   get_all_stages() {
       local job_name="$1"
       local build_number="$2"
       # Implementation using jenkins_api and jq
   }
   ```

3. Expected output format:
   ```json
   [
     {"name":"Initialize Submodules","status":"SUCCESS","startTimeMillis":1234567890000,"durationMillis":10000},
     {"name":"Build","status":"IN_PROGRESS","startTimeMillis":1234567900000,"durationMillis":0}
   ]
   ```

### Test Plan

**Test File:** `test/stage_retrieval.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `get_all_stages_success` | Returns stages array with all fields | API Data Source |
| `get_all_stages_empty` | Returns empty array when no stages | API Data Source |
| `get_all_stages_api_failure` | Returns empty array on API error | API Data Source |
| `get_all_stages_missing_fields` | Handles stages with missing optional fields | API Data Source |
| `get_all_stages_various_statuses` | Correctly extracts all status types (SUCCESS, FAILED, IN_PROGRESS, etc.) | API Data Source |

**Mocking Requirements:**
- Mock `jenkins_api` function to return test fixtures
- Create fixture files with sample wfapi/describe responses

**Dependencies:** None

---

- [x] **Chunk C: Stage Line Printing Function**

### Description

Create the `print_stage_line` function that outputs a single stage line with appropriate color coding and formatting. Handles completed, in-progress, and not-executed stages.

### Spec Reference

See spec [Stage Display Format](./full-stage-print-spec.md#stage-display-format) sections: Completed Stages, In-Progress Stages, Not-Executed Stages.

### Dependencies

- Chunk A (format_stage_duration)

### Produces

- `lib/jenkins-common.sh` (add `print_stage_line` function)
- `test/stage_print.bats`

### Implementation Details

1. Create `print_stage_line` function in `lib/jenkins-common.sh`:
   - Input: stage_name, status, duration_ms (optional for in-progress/not-executed)
   - Output format: `[HH:MM:SS] ℹ   Stage: <name> (<duration>)`
   - Color coding based on status:
     - SUCCESS: Green
     - FAILED: Red (with `← FAILED` marker)
     - UNSTABLE: Yellow
     - IN_PROGRESS: Cyan `(running)`
     - NOT_EXECUTED: Dim/gray `(not executed)`
   - Uses `_timestamp` for timestamp and existing color variables

2. Function signature:
   ```bash
   # Print a single stage line with appropriate color and format
   # Usage: print_stage_line "stage-name" "status" [duration_ms]
   # status: SUCCESS, FAILED, UNSTABLE, IN_PROGRESS, NOT_EXECUTED, ABORTED
   print_stage_line() {
       local stage_name="$1"
       local status="$2"
       local duration_ms="${3:-}"
       # Implementation...
   }
   ```

3. Add COLOR_DIM for gray/dim text in `_init_colors`:
   ```bash
   COLOR_DIM=$(tput dim 2>/dev/null || echo "")
   ```

### Test Plan

**Test File:** `test/stage_print.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `print_stage_line_success` | SUCCESS stage shows green with duration | Completed Stages |
| `print_stage_line_failed` | FAILED stage shows red with duration and marker | Completed Stages |
| `print_stage_line_unstable` | UNSTABLE stage shows yellow with duration | Completed Stages |
| `print_stage_line_in_progress` | IN_PROGRESS shows cyan with `(running)` | In-Progress Stages |
| `print_stage_line_not_executed` | NOT_EXECUTED shows dim with `(not executed)` | Not-Executed Stages |
| `print_stage_line_format` | Output matches `[HH:MM:SS] ℹ   Stage:` format | Stage Display Format |
| `print_stage_line_no_color` | Works correctly when NO_COLOR is set | Color coding |

**Mocking Requirements:**
- Set `NO_COLOR=1` for color-disabled tests
- Mock `_timestamp` for predictable output

**Dependencies:** Chunk A (format_stage_duration)

---

- [x] **Chunk D: Stage Change Tracking Function**

### Description

Create the `track_stage_changes` function that compares previous and current stage states, detects transitions, and prints completed stages. Maintains state between calls using a passed-in associative array reference.

### Spec Reference

See spec [Stage Tracking](./full-stage-print-spec.md#stage-tracking) and [Behavior by Command](./full-stage-print-spec.md#behavior-by-command).

### Dependencies

- Chunk B (get_all_stages)
- Chunk C (print_stage_line)

### Produces

- `lib/jenkins-common.sh` (add `track_stage_changes` function)
- `test/stage_tracking.bats`

### Implementation Details

1. Create `track_stage_changes` function in `lib/jenkins-common.sh`:
   - Input: job_name, build_number, previous_stages_json (or empty for first call)
   - Fetches current stages using `get_all_stages`
   - Detects state transitions:
     - `NOT_EXECUTED` → `IN_PROGRESS`: Stage started (don't print)
     - `IN_PROGRESS` → `SUCCESS`: Print stage with duration (green)
     - `IN_PROGRESS` → `FAILED`: Print stage with duration + marker (red)
     - `IN_PROGRESS` → `UNSTABLE`: Print stage with duration (yellow)
   - Prints currently running stage (if any) with `(running)`
   - Returns updated stages JSON on stdout for next iteration
   - Outputs stage lines to stderr (so stdout can be captured for state)

2. Function signature:
   ```bash
   # Track stage state changes and print completed stages
   # Usage: new_state=$(track_stage_changes "job-name" "build-number" "$previous_state" "$verbose")
   # Returns: Current stages JSON on stdout (capture for next iteration)
   # Side effect: Prints completed/running stage lines to stderr
   track_stage_changes() {
       local job_name="$1"
       local build_number="$2"
       local previous_stages_json="${3:-[]}"
       local verbose="${4:-false}"
       # Implementation...
   }
   ```

3. Verbose mode handling:
   - When verbose=true: Show "Build in progress... (Xs elapsed)" messages
   - When verbose=false: Only show stage completion lines

### Test Plan

**Test File:** `test/stage_tracking.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `track_stage_changes_first_call` | First call returns current state, no prints | Stage Tracking |
| `track_stage_changes_stage_completes` | Detects IN_PROGRESS→SUCCESS, prints completion | Stage Tracking |
| `track_stage_changes_stage_fails` | Detects IN_PROGRESS→FAILED, prints with marker | Stage Tracking |
| `track_stage_changes_stage_unstable` | Detects IN_PROGRESS→UNSTABLE, prints yellow | Stage Tracking |
| `track_stage_changes_shows_running` | Shows currently running stage | In-Progress Stages |
| `track_stage_changes_multiple_transitions` | Handles multiple stages changing in one poll | Stage Tracking |
| `track_stage_changes_verbose_mode` | Shows elapsed messages in verbose mode | Verbose mode |
| `track_stage_changes_non_verbose` | No elapsed messages in non-verbose | Non-verbose mode |

**Mocking Requirements:**
- Mock `get_all_stages` to return controlled test data
- Mock `print_stage_line` to verify calls

**Dependencies:** Chunk B, Chunk C

---

- [x] **Chunk E: Update Monitoring Functions**

### Description

Update the three monitoring functions (`_push_monitor_build`, `_follow_monitor_build`, `_build_monitor`) to use the new stage tracking system instead of the current single-stage approach.

### Spec Reference

See spec [Affected Functions](./full-stage-print-spec.md#affected-functions) and [Behavior by Command](./full-stage-print-spec.md#behavior-by-command).

### Dependencies

- Chunk D (track_stage_changes)

### Produces

- `buildgit` (modified functions: `_push_monitor_build`, `_follow_monitor_build`, `_build_monitor`)
- `test/monitoring_stages.bats`

### Implementation Details

1. Update `_push_monitor_build` in `buildgit` (~line 775):
   - Replace `get_current_stage` calls with `track_stage_changes`
   - Maintain stage state JSON across poll iterations
   - Pass VERBOSE_MODE to track_stage_changes
   - Remove manual "Stage completed" messages (now handled by track_stage_changes)

2. Update `_follow_monitor_build` in `buildgit` (~line 360):
   - Same changes as _push_monitor_build
   - Ensure state resets between build monitoring sessions

3. Update `_build_monitor` in `buildgit` (~line 1052):
   - Same changes as _push_monitor_build

4. Pattern for all three functions:
   ```bash
   local stage_state="[]"
   while [[ $elapsed -lt $MAX_BUILD_TIME ]]; do
       # ... existing build_info fetch ...

       # Track stage changes (replaces get_current_stage logic)
       stage_state=$(track_stage_changes "$job_name" "$build_number" "$stage_state" "$VERBOSE_MODE")

       # Verbose-only elapsed time messages
       if [[ "$VERBOSE_MODE" == "true" && $((elapsed - last_time_report)) -ge 30 ]]; then
           bg_log_progress "Build in progress... (${elapsed}s elapsed)"
           last_time_report=$elapsed
       fi

       # ... rest of loop ...
   done
   ```

### Test Plan

**Test File:** `test/monitoring_stages.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `push_monitor_shows_stage_completions` | _push_monitor_build prints stage completions | buildgit push |
| `follow_monitor_shows_stage_completions` | _follow_monitor_build prints stage completions | buildgit status -f |
| `build_monitor_shows_stage_completions` | _build_monitor prints stage completions | buildgit build |
| `monitor_verbose_shows_elapsed` | Shows elapsed in verbose mode | Verbose mode |
| `monitor_non_verbose_no_elapsed` | No elapsed in non-verbose mode | Non-verbose mode |
| `monitor_shows_running_stage` | Shows currently running stage | In-Progress Stages |

**Mocking Requirements:**
- Mock `get_build_info` to return controlled build states
- Mock `track_stage_changes` to verify integration
- Use test fixtures for multi-stage build scenarios

**Dependencies:** Chunk D

---

- [x] **Chunk F: Update Display Output Functions**

### Description

Update the display output functions (`display_success_output`, `display_failure_output`, `display_building_output`) to include the full stage summary when displaying build results. Also update `_jenkins_status_check` for one-shot status.

### Spec Reference

See spec [Display Functions](./full-stage-print-spec.md#display-functions), [buildgit status (one-shot)](./full-stage-print-spec.md#buildgit-status-one-shot), and [Example Output](./full-stage-print-spec.md#example-output).

### Dependencies

- Chunk B (get_all_stages)
- Chunk C (print_stage_line)

### Produces

- `lib/jenkins-common.sh` (modified: `display_success_output`, `display_failure_output`, `display_building_output`)
- `buildgit` (modified: `_jenkins_status_check`)
- `test/display_stages.bats`

### Implementation Details

1. Create helper function `_display_all_stages` in `lib/jenkins-common.sh`:
   ```bash
   # Display all stages with their statuses and durations
   # Usage: _display_all_stages "job-name" "build-number"
   _display_all_stages() {
       local job_name="$1"
       local build_number="$2"
       local stages_json
       stages_json=$(get_all_stages "$job_name" "$build_number")
       # Iterate through stages and call print_stage_line for each
   }
   ```

2. Update `display_success_output` in `lib/jenkins-common.sh`:
   - Add job_name and build_number as parameters (or extract from build_json url)
   - After banner, before build details: call `_display_all_stages`
   - All stages should show as SUCCESS with durations

3. Update `display_failure_output` in `lib/jenkins-common.sh`:
   - Add `_display_all_stages` call after banner
   - Show completed stages with appropriate colors
   - Show not-executed stages for failed builds

4. Update `display_building_output` in `lib/jenkins-common.sh`:
   - Add `_display_all_stages` call after banner
   - Show completed stages with durations
   - Show current stage with `(running)`

5. Update `_jenkins_status_check` in `buildgit` (~line 244):
   - For one-shot status (not follow mode), pass job_name and build_number to display functions
   - Ensure stages are fetched and displayed

### Test Plan

**Test File:** `test/display_stages.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `display_success_shows_all_stages` | Success output includes all stage lines | Successful Build |
| `display_failure_shows_completed_stages` | Failure output shows completed stages | Failed Build |
| `display_failure_shows_not_executed` | Failure output shows not-executed stages | Failed Build |
| `display_building_shows_running` | Building output shows running stage | Build In Progress |
| `display_stages_correct_order` | Stages displayed in execution order | Example Output |
| `display_stages_correct_colors` | Stages have correct color coding | Color coding |
| `status_one_shot_shows_stages` | One-shot status displays all stages | buildgit status |

**Mocking Requirements:**
- Mock `get_all_stages` to return test fixtures
- Test with various stage combinations (all success, mixed, failed with not-executed)

**Dependencies:** Chunk B, Chunk C

---

## Integration Testing Notes

After all chunks are implemented, perform integration testing:

1. **Real Jenkins build monitoring**: Run `buildgit push` and verify stage output matches spec format
2. **Follow mode**: Test `buildgit status -f` to ensure stages display correctly across multiple builds
3. **One-shot status**: Test `buildgit status` for completed and in-progress builds
4. **Color verification**: Manual terminal testing for correct ANSI color codes
5. **Verbose vs non-verbose**: Verify elapsed messages only appear with `--verbose`

## API Response Fixture

Create test fixture at `test/fixtures/wfapi_describe_response.json`:
```json
{
  "name": "#42",
  "status": "IN_PROGRESS",
  "stages": [
    {"name": "Initialize Submodules", "status": "SUCCESS", "startTimeMillis": 1706889863000, "durationMillis": 10000},
    {"name": "Build", "status": "SUCCESS", "startTimeMillis": 1706889879000, "durationMillis": 15000},
    {"name": "Unit Tests", "status": "IN_PROGRESS", "startTimeMillis": 1706889899000, "durationMillis": 0},
    {"name": "Deploy", "status": "NOT_EXECUTED", "startTimeMillis": 0, "durationMillis": 0}
  ]
}
```
