# Implementation Plan: buildgit Monitoring Fixes and Enhancements

**Spec Reference:** [bug2026-02-01-buildgit-monitoring-spec.md](./bug2026-02-01-buildgit-monitoring-spec.md)

---

## Contents

- [x] **Chunk A: Fix Verbose Mode stderr Redirection**
- [x] **Chunk B: Add Build Info Banner Display in Follow Mode**
- [x] **Chunk C: Implement Real-Time Progress Display**

---

## Chunk Detail

- [x] **Chunk A: Fix Verbose Mode stderr Redirection**

### Description

Fix the `bg_log_info()` and `bg_log_success()` wrapper functions to redirect their output to stderr instead of stdout. This prevents verbose logging from corrupting function return values captured via command substitution.

### Spec Reference

See spec [Issue 2: Verbose Mode Causes Output Corruption](./bug2026-02-01-buildgit-monitoring-spec.md#issue-2-verbose-mode-causes-output-corruption).

### Dependencies

- None

### Produces

- `buildgit` (modified - lines 73-85)
- `test/buildgit_verbose_stderr.bats` (new test file)

### Implementation Details

1. Modify `bg_log_info()` function in `buildgit`:
   - Add `>&2` redirection after the `log_info "$@"` call
   - This ensures verbose info messages go to stderr, not stdout

2. Modify `bg_log_success()` function in `buildgit`:
   - Add `>&2` redirection after the `log_success "$@"` call
   - This ensures verbose success messages go to stderr, not stdout

3. The changes are minimal and localized:
   ```bash
   bg_log_info() {
       if [[ "$VERBOSE_MODE" == "true" ]]; then
           log_info "$@" >&2
       fi
   }

   bg_log_success() {
       if [[ "$VERBOSE_MODE" == "true" ]]; then
           log_success "$@" >&2
       fi
   }
   ```

4. Do NOT modify `jenkins-common.sh` - changes are scoped to `buildgit` only per spec requirements.

### Test Plan

**Test File:** `test/buildgit_verbose_stderr.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `verbose_info_goes_to_stderr` | Verify `bg_log_info` output goes to stderr when VERBOSE_MODE=true | Issue 2 |
| `verbose_success_goes_to_stderr` | Verify `bg_log_success` output goes to stderr when VERBOSE_MODE=true | Issue 2 |
| `verbose_does_not_corrupt_return_value` | Verify function return values via command substitution are not corrupted by verbose logging | Issue 2 |
| `quiet_mode_no_output` | Verify `bg_log_info` and `bg_log_success` produce no output when VERBOSE_MODE=false | Issue 2 |

**Mocking Requirements:**
- Source `buildgit` functions directly for unit testing
- Mock `log_info` and `log_success` from jenkins-common.sh to capture output streams

**Dependencies:** None

---

- [x] **Chunk B: Add Build Info Banner Display in Follow Mode**

### Description

Update `_cmd_status_follow()` to display the build information banner when an in-progress build is detected, before entering the monitoring loop. This provides users with immediate context about what build is being monitored.

### Spec Reference

See spec [Issue 1: Missing Build Information in Follow Mode](./bug2026-02-01-buildgit-monitoring-spec.md#issue-1-missing-build-information-in-follow-mode).

### Dependencies

- Chunk A (verbose stderr fix) - ensures any verbose logging during banner display doesn't corrupt output

### Produces

- `buildgit` (modified - `_cmd_status_follow()` function, approximately lines 424-479)
- `test/buildgit_follow_banner.bats` (new test file)

### Implementation Details

1. Create a new helper function `_display_build_in_progress_banner()` that:
   - Takes job_name and build_number as parameters
   - Fetches build info using `get_build_info()`
   - Fetches console output for trigger detection and commit extraction
   - Displays the formatted banner using existing display functions from jenkins-common.sh
   - Uses `display_building_output()` which already formats the banner correctly

2. Modify `_cmd_status_follow()` function:
   - After detecting `building == "true"` at line 460
   - Before calling `_follow_monitor_build()`
   - Call `_display_build_in_progress_banner "$job_name" "$build_number"`

3. The banner format matches the spec:
   ```
   ╔════════════════════════════════════════╗
   ║          BUILD IN PROGRESS             ║
   ╚════════════════════════════════════════╝

   Job:        ralph1
   Build:      #53
   Status:     BUILDING
   Stage:      Unit Tests
   Trigger:    Automated (git push)
   Commit:     6157e1a - "test build without verbose flag5"
               ✓ Your commit (HEAD)
   Started:    2026-02-01 10:11:24
   ```

4. Note: The `Elapsed` field is intentionally omitted per spec because real-time tracking begins immediately after the banner.

### Test Plan

**Test File:** `test/buildgit_follow_banner.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `follow_mode_shows_banner_for_in_progress_build` | Verify banner is displayed when joining an in-progress build | Issue 1 |
| `follow_mode_banner_shows_job_name` | Verify job name appears in banner | Issue 1 |
| `follow_mode_banner_shows_build_number` | Verify build number appears in banner | Issue 1 |
| `follow_mode_banner_shows_current_stage` | Verify current stage is displayed in banner | Issue 1 |
| `follow_mode_banner_before_monitoring` | Verify banner appears before monitoring messages | Issue 1 |

**Mocking Requirements:**
- Mock `get_build_info()` to return JSON with `building: true`
- Mock `get_current_stage()` to return a stage name
- Mock `get_console_output()` to return sample console output
- Mock Jenkins API responses

**Dependencies:** Chunk A

---

- [x] **Chunk C: Implement Real-Time Progress Display**

### Description

Update the monitoring functions (`_follow_monitor_build`, `_push_monitor_build`, `_build_monitor`) to display real-time progress regardless of verbose mode. This includes stage completion messages and periodic elapsed time updates every 30 seconds.

### Spec Reference

See spec [Issue 3: No Real-Time Progress Display](./bug2026-02-01-buildgit-monitoring-spec.md#issue-3-no-real-time-progress-display).

### Dependencies

- Chunk A (verbose stderr fix) - must be completed first to avoid output corruption

### Produces

- `buildgit` (modified - three monitoring functions)
- `test/buildgit_realtime_progress.bats` (new test file)

### Implementation Details

1. Add a new essential logging function for progress updates:
   ```bash
   # PROGRESS level - Always output for real-time monitoring feedback
   # Use for: stage completions, elapsed time updates during monitoring
   bg_log_progress() {
       log_info "$@" >&2
   }
   ```
   Note: Uses stderr to avoid corrupting any command substitution, and always outputs regardless of VERBOSE_MODE.

2. Modify `_follow_monitor_build()` function (lines 342-399):
   - Track completed stages using a variable (e.g., `completed_stages=""`)
   - When `current_stage` changes and `last_stage` is not empty, output completion message:
     ```bash
     if [[ -n "$last_stage" && "$current_stage" != "$last_stage" ]]; then
         bg_log_progress "Stage completed: $last_stage"
     fi
     ```
   - Change elapsed time update from `bg_log_info` to `bg_log_progress`:
     ```bash
     bg_log_progress "Build in progress... (${elapsed}s elapsed)"
     ```

3. Modify `_push_monitor_build()` function (lines 694-752):
   - Apply the same stage completion tracking pattern
   - Change elapsed time update to use `bg_log_progress`

4. Modify `_build_monitor()` function (lines 965-1023):
   - Apply the same stage completion tracking pattern
   - Change elapsed time update to use `bg_log_progress`

5. Expected output format during monitoring:
   ```
   [10:13:30] ✓ Stage completed: Checkout
   [10:13:45] ✓ Stage completed: Build
   [10:14:00] ℹ Build in progress... (30s elapsed)
   [10:14:15] ✓ Stage completed: Unit Tests
   ```

6. Implementation note: The stage completion detection works by:
   - Saving the previous stage in `last_stage`
   - When stage changes, the previous stage has completed
   - Output uses `log_success` format for the checkmark (✓)

### Test Plan

**Test File:** `test/buildgit_realtime_progress.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `stage_completion_shown_without_verbose` | Verify stage completion messages appear in non-verbose mode | Issue 3 |
| `elapsed_time_shown_without_verbose` | Verify elapsed time updates appear in non-verbose mode | Issue 3 |
| `stage_completion_format_correct` | Verify stage completion message format matches spec | Issue 3 |
| `elapsed_time_every_30_seconds` | Verify elapsed time updates occur at 30-second intervals | Issue 3 |
| `progress_output_to_stderr` | Verify progress messages go to stderr (not stdout) | Issue 3 |
| `follow_monitor_shows_progress` | Verify `_follow_monitor_build` shows real-time progress | Issue 3 |
| `push_monitor_shows_progress` | Verify `_push_monitor_build` shows real-time progress | Issue 3 |
| `build_monitor_shows_progress` | Verify `_build_monitor` shows real-time progress | Issue 3 |

**Mocking Requirements:**
- Mock `get_build_info()` to simulate build progression
- Mock `get_current_stage()` to return changing stages over time
- Mock `sleep` command to avoid actual delays in tests
- Control `POLL_INTERVAL` for faster test execution

**Dependencies:** Chunk A

---

## Definition of Done

For each chunk:
1. All unit tests written as part of the chunk have been executed and pass
2. All existing unit tests in the project still pass
3. Code changes are limited to the files specified in the "Produces" section
4. Implementation matches the behavior specified in the bug spec

## Notes

- Chunks B and C both depend on Chunk A, but B and C are independent of each other
- Chunk A should be implemented first as it fixes a fundamental issue that affects all verbose logging
- The implementation preserves backward compatibility - non-verbose mode behavior is enhanced, not changed
- All changes are scoped to `buildgit` only; `jenkins-common.sh` is not modified per spec requirements
