# Unified Build Monitoring Output Implementation Plan

Implementation plan for [unify-follow-log-spec.md](./unify-follow-log-spec.md)

## Contents

- [x] **Chunk A: print_finished_line() Function**
- [x] **Chunk B: Refactor display_building_output() to Unified Header Format**
- [x] **Chunk C: Consolidate Duplicate Monitor Functions**
- [x] **Chunk D: Build Header Integration and Elapsed Suffix Wiring**
- [x] **Chunk E: Replace Post-Completion Display with Finished Line**

---

## Chunk Detail

---

- [x] **Chunk A: print_finished_line() Function**

### Description

Create a new `print_finished_line()` function in `lib/jenkins-common.sh` that outputs the final build status line `Finished: <STATUS>` with appropriate ANSI color coding. This replaces the current behavior where post-completion output re-displays the full build banner and all metadata.

### Spec Reference

See spec [Build Completion](./unify-follow-log-spec.md#4-build-completion) and [Final Status Line Colors](./unify-follow-log-spec.md#final-status-line-colors).

### Dependencies

- None

### Produces

- `lib/jenkins-common.sh` (add `print_finished_line` function)
- `test/finished_line.bats`

### Implementation Details

1. Create `print_finished_line` function in `lib/jenkins-common.sh`:
   - Input: build result string (SUCCESS, FAILURE, UNSTABLE, ABORTED, or other)
   - Output to stdout: `Finished: <STATUS>` with ANSI color
   - Color mapping:
     - SUCCESS → `${COLOR_GREEN}`
     - FAILURE → `${COLOR_RED}`
     - UNSTABLE → `${COLOR_YELLOW}`
     - ABORTED → `${COLOR_DIM}` (gray/dim)
     - Other → no color
   - Function signature:
     ```bash
     # Print the final build status line with color
     # Usage: print_finished_line "SUCCESS"
     # Output: "Finished: SUCCESS" in green
     # Spec: unify-follow-log-spec.md, Section 4 (Build Completion)
     print_finished_line() {
         local result="$1"
         # Implementation...
     }
     ```

2. Place function near the existing `log_banner()` function in the logging/display section of `jenkins-common.sh`.

### Test Plan

**Test File:** `test/finished_line.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `finished_line_success_text` | Outputs "Finished: SUCCESS" text | 4 |
| `finished_line_failure_text` | Outputs "Finished: FAILURE" text | 4 |
| `finished_line_unstable_text` | Outputs "Finished: UNSTABLE" text | 4 |
| `finished_line_aborted_text` | Outputs "Finished: ABORTED" text | 4 |
| `finished_line_success_green` | SUCCESS line uses green color code | Final Status Line Colors |
| `finished_line_failure_red` | FAILURE line uses red color code | Final Status Line Colors |
| `finished_line_unstable_yellow` | UNSTABLE line uses yellow color code | Final Status Line Colors |
| `finished_line_aborted_dim` | ABORTED line uses dim/gray color code | Final Status Line Colors |

**Mocking Requirements:**
- Source `lib/jenkins-common.sh` directly to access color constants and function
- No external dependencies to mock

**Dependencies:** None

---

- [x] **Chunk B: Refactor display_building_output() to Unified Header Format**

### Description

Refactor `display_building_output()` in `lib/jenkins-common.sh` to match the unified header format from the spec. The current function shows stages before metadata and lacks the Build Info section. The new format shows the banner, then build metadata fields, then the Build Info section (Started by, Agent, Pipeline), then the Console URL. Stages are removed from this function entirely—they will be streamed separately by the monitoring loop.

### Spec Reference

See spec [Build Header](./unify-follow-log-spec.md#2-build-header-displayed-immediately), [Field Descriptions](./unify-follow-log-spec.md#field-descriptions), [Elapsed Time Display](./unify-follow-log-spec.md#elapsed-time-display).

### Dependencies

- None (modifies existing library function)

### Produces

- `lib/jenkins-common.sh` (modify `display_building_output` function)
- `test/unified_header.bats`

### Implementation Details

1. Update `display_building_output()` function signature to accept two additional parameters:
   - `console_output` (10th param) — needed to extract Build Info (Started by, Agent, Pipeline)
   - `elapsed_suffix` (11th param, optional, default empty) — "(so far)" for status -f mode
   ```bash
   display_building_output() {
       local job_name="$1"
       local build_number="$2"
       local build_json="$3"
       local trigger_type="$4"
       local trigger_user="$5"
       local commit_sha="$6"
       local commit_msg="$7"
       local correlation_status="$8"
       local current_stage="${9:-}"
       local console_output="${10:-}"
       local elapsed_suffix="${11:-}"
       # ...
   }
   ```

2. Restructure the output order to match spec:
   - a. Display banner via `log_banner "building"` (unchanged)
   - b. Display build detail fields: Job, Build, Status, Trigger, Commit (with correlation), Started, Elapsed (with optional suffix)
   - c. Display Build Info section using `display_build_metadata "$console_output"` (only if console_output is non-empty)
   - d. Display Console URL after Build Info section
   - e. **Remove** the `_display_all_stages` call (stages are now streamed by the monitor loop, not shown in the header)

3. Elapsed time formatting:
   - Current: `Elapsed:    $(format_duration "$elapsed_ms")`
   - New: `Elapsed:    $(format_duration "$elapsed_ms")${elapsed_suffix:+ $elapsed_suffix}`
   - For push/build: elapsed_suffix is empty → `Elapsed:    5s`
   - For status -f: elapsed_suffix is "(so far)" → `Elapsed:    1m 17s (so far)`

4. Ensure backward compatibility: existing callers that don't pass the new parameters still work (defaults to empty).

### Test Plan

**Test File:** `test/unified_header.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `header_shows_banner` | Output contains BUILD IN PROGRESS banner | 2 |
| `header_shows_job_field` | Output contains "Job:" field | 2 Field Descriptions |
| `header_shows_build_number` | Output contains "Build: #N" field | 2 Field Descriptions |
| `header_shows_status_building` | Output contains "Status: BUILDING" | 2 Field Descriptions |
| `header_shows_trigger_automated` | Output contains "Trigger: Automated (git push)" for automated trigger | 2 Trigger Types |
| `header_shows_trigger_manual` | Output contains "Trigger: Manual" for manual trigger | 2 Trigger Types |
| `header_shows_commit` | Output contains commit short hash and message | 2 Field Descriptions |
| `header_shows_correlation` | Output contains commit correlation indicator | 2 Field Descriptions |
| `header_shows_started_time` | Output contains "Started:" field | 2 Field Descriptions |
| `header_shows_elapsed_time` | Output contains "Elapsed:" field | 2 Field Descriptions |
| `header_elapsed_no_suffix` | Elapsed field has no suffix when elapsed_suffix is empty | 2 Elapsed Time Display |
| `header_elapsed_so_far_suffix` | Elapsed field shows "(so far)" when elapsed_suffix passed | 2 Elapsed Time Display |
| `header_shows_build_info_section` | Output contains "=== Build Info ===" section when console_output provided | 2 |
| `header_shows_console_url_after_build_info` | Console URL appears after Build Info section | 2 |
| `header_does_not_show_stages` | Output does NOT contain stage lines | 2 |
| `header_without_console_output` | Works correctly when console_output is empty (no Build Info section) | 2 |

**Mocking Requirements:**
- Mock `jq` or provide fixture JSON for `build_json` parameter
- Mock `display_build_metadata` or provide fixture console output
- Provide test values for all parameters

**Dependencies:** None

---

- [x] **Chunk C: Consolidate Duplicate Monitor Functions**

### Description

The three monitoring functions `_follow_monitor_build()`, `_push_monitor_build()`, and `_build_monitor()` in `buildgit` are nearly identical (same polling loop, stage tracking, timeout logic). Consolidate them into a single `_monitor_build()` function to eliminate code duplication. The only current differences are: (1) minor timeout message wording, and (2) `_push_monitor_build`/`_build_monitor` include an extra `bg_log_info` about checking Jenkins console. The consolidated function should handle both cases.

### Spec Reference

See spec [Implementation Requirements](./unify-follow-log-spec.md#implementation-requirements) — "Ensure all commands use consistent stage tracking."

### Dependencies

- None (refactoring existing code)

### Produces

- `buildgit` (replace three monitor functions with one `_monitor_build`)
- `test/monitor_consolidation.bats`

### Implementation Details

1. Create `_monitor_build()` in `buildgit` that combines the common logic:
   ```bash
   # Unified build monitoring loop
   # Arguments: job_name, build_number
   # Returns: 0 when build completes, 1 on timeout/error
   # Spec: unify-follow-log-spec.md, Section 3 (Stage Output)
   _monitor_build() {
       local job_name="$1"
       local build_number="$2"
       local elapsed=0
       local consecutive_failures=0
       local last_time_report=0
       local stage_state="[]"

       bg_log_info "Monitoring build #${build_number}..."

       while [[ $elapsed -lt $MAX_BUILD_TIME ]]; do
           # ... common polling, stage tracking, timeout logic ...
       done

       bg_log_error "Build timeout: exceeded ${MAX_BUILD_TIME} seconds"
       bg_log_info "Build may still be running - check Jenkins console" >&2
       return 1
   }
   ```

2. Replace all three existing functions:
   - `_follow_monitor_build()` → `_monitor_build()`
   - `_push_monitor_build()` → `_monitor_build()`
   - `_build_monitor()` → `_monitor_build()`

3. Update all call sites:
   - `_cmd_status_follow()` line ~534: `_follow_monitor_build` → `_monitor_build`
   - `cmd_push()` line ~951: `_push_monitor_build` → `_monitor_build`
   - `cmd_build()` line ~1199: `_build_monitor` → `_monitor_build`

4. Remove the three original functions after replacement.

### Test Plan

**Test File:** `test/monitor_consolidation.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `monitor_build_function_exists` | _monitor_build function is defined in buildgit | Implementation Requirements |
| `old_follow_monitor_removed` | _follow_monitor_build function no longer exists | Implementation Requirements |
| `old_push_monitor_removed` | _push_monitor_build function no longer exists | Implementation Requirements |
| `old_build_monitor_removed` | _build_monitor function no longer exists | Implementation Requirements |
| `monitor_returns_0_on_completion` | Returns 0 when build completes (building=false, result=SUCCESS) | 3 |
| `monitor_returns_1_on_timeout` | Returns 1 when MAX_BUILD_TIME exceeded | 3 |
| `monitor_tracks_stages` | Calls track_stage_changes during monitoring | 3 Stage Output |
| `monitor_handles_api_failure` | Retries on API failure, fails after 5 consecutive failures | 3 |

**Mocking Requirements:**
- Mock `get_build_info` to return controlled responses (building=true then building=false)
- Mock `track_stage_changes` to return stage state
- Set small `MAX_BUILD_TIME` and `POLL_INTERVAL` for fast test execution
- Use `_BUILDGIT_TESTING=1` to source buildgit without running main

**Dependencies:** None

---

- [x] **Chunk D: Build Header Integration and Elapsed Suffix Wiring**

### Description

Wire the unified build header into all three command paths (push, build, status -f) so all commands display the same header format before monitoring begins. Currently only `_cmd_status_follow()` calls `_display_build_in_progress_banner()`. The push and build commands skip the header entirely and go straight to monitoring. This chunk also wires the `elapsed_suffix` parameter so that `status -f` shows "(so far)" while push/build do not.

### Spec Reference

See spec [Command-Specific Behavior](./unify-follow-log-spec.md#5-command-specific-behavior), [Elapsed Time Display](./unify-follow-log-spec.md#elapsed-time-display).

### Dependencies

- Chunk B (`display_building_output` updated signature with `console_output` and `elapsed_suffix` parameters)
- Chunk C (consolidated `_monitor_build` function)

### Produces

- `buildgit` (modify `cmd_push`, `cmd_build`, `_cmd_status_follow`, `_display_build_in_progress_banner`)
- `test/header_integration.bats`

### Implementation Details

1. Update `_display_build_in_progress_banner()` to:
   - Accept an optional `elapsed_suffix` parameter (3rd argument):
     ```bash
     _display_build_in_progress_banner() {
         local job_name="$1"
         local build_number="$2"
         local elapsed_suffix="${3:-}"
         # ...
     }
     ```
   - Fetch console_output (already done) and pass it to `display_building_output` as the 10th param
   - Pass `elapsed_suffix` to `display_building_output` as the 11th param:
     ```bash
     display_building_output "$job_name" "$build_number" "$build_json" \
         "$trigger_type" "$trigger_user" \
         "$commit_sha" "$commit_msg" \
         "$correlation_status" "$current_stage" \
         "$console_output" "$elapsed_suffix"
     ```

2. Display initial completed stages after the header:
   - After calling `display_building_output`, call `_display_all_stages "$job_name" "$build_number"` to show any stages that completed before monitoring began
   - This ensures the flow is: header → already-completed stages → streaming new stages

3. Update `cmd_push()`:
   - After the build starts (after `_push_wait_for_build_start`), add a call to `_display_build_in_progress_banner "$job_name" "$new_build_number"` (no elapsed_suffix)
   - This goes before `_monitor_build` so the header appears before stage streaming

4. Update `cmd_build()`:
   - After `_build_wait_for_start`, add a call to `_display_build_in_progress_banner "$job_name" "$build_number"` (no elapsed_suffix)
   - This goes before `_monitor_build`

5. Update `_cmd_status_follow()`:
   - Pass "(so far)" as elapsed_suffix to `_display_build_in_progress_banner`:
     ```bash
     _display_build_in_progress_banner "$job_name" "$build_number" "(so far)"
     ```

### Test Plan

**Test File:** `test/header_integration.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `push_shows_header_before_monitoring` | cmd_push displays BUILD IN PROGRESS banner before monitor loop | 5 buildgit push |
| `build_shows_header_before_monitoring` | cmd_build displays BUILD IN PROGRESS banner before monitor loop | 5 buildgit build |
| `status_follow_shows_header` | status -f displays BUILD IN PROGRESS banner | 5 buildgit status -f |
| `push_header_no_so_far` | Push header elapsed time has no "(so far)" suffix | Elapsed Time Display |
| `build_header_no_so_far` | Build header elapsed time has no "(so far)" suffix | Elapsed Time Display |
| `status_follow_header_so_far` | Status -f header elapsed time shows "(so far)" | Elapsed Time Display |
| `banner_shows_initial_stages` | After header, already-completed stages are displayed | 3 Initial Display |
| `push_git_output_before_banner` | Git push output appears before BUILD IN PROGRESS banner | 5 buildgit push |

**Mocking Requirements:**
- Mock all Jenkins API calls (get_build_info, get_console_output, get_all_stages, get_last_build_number, verify_jenkins_connection, verify_job_exists, etc.)
- Mock `git push` for push tests
- Mock `trigger_build` for build tests
- Use `_BUILDGIT_TESTING=1` to source buildgit
- Set small timeouts for fast test execution

**Dependencies:** Chunk B (display_building_output updated signature), Chunk C (_monitor_build)

---

- [x] **Chunk E: Replace Post-Completion Display with Finished Line**

### Description

Replace the current post-monitoring flow that calls `_jenkins_status_check()` (which re-displays the entire build banner, all stages, and all metadata) with a minimal completion display: test failure details (if applicable) followed by a single `Finished: <STATUS>` line. This is the core behavioral change of the spec—after monitoring streams stages in real-time, the completion output should not re-display everything.

### Spec Reference

See spec [Build Completion](./unify-follow-log-spec.md#4-build-completion), [Complete Example Output](./unify-follow-log-spec.md#complete-example-output).

### Dependencies

- Chunk A (`print_finished_line` function)
- Chunk D (build header displayed before monitoring, so post-completion doesn't need to show it again)

### Produces

- `buildgit` (modify `_push_handle_build_result`, `_build_handle_result`, `_cmd_status_follow` post-monitoring logic)
- `test/build_completion.bats`

### Implementation Details

1. Create a shared `_handle_build_completion()` function in `buildgit`:
   ```bash
   # Handle build completion display
   # Called after _monitor_build() returns 0
   # Arguments: job_name, build_number
   # Spec: unify-follow-log-spec.md, Section 4 (Build Completion)
   _handle_build_completion() {
       local job_name="$1"
       local build_number="$2"

       # Fetch final build info
       local build_json
       build_json=$(get_build_info "$job_name" "$build_number")
       local result
       result=$(echo "$build_json" | jq -r '.result // "UNKNOWN"')

       # Display test failure details if applicable (UNSTABLE or FAILURE)
       if [[ "$result" == "UNSTABLE" || "$result" == "FAILURE" ]]; then
           local test_results_json
           test_results_json=$(fetch_test_results "$job_name" "$build_number")
           if [[ -n "$test_results_json" ]]; then
               display_test_results "$test_results_json"
           fi
       fi

       # Print final status line
       echo ""
       print_finished_line "$result"

       # Return appropriate exit code
       if [[ "$result" == "SUCCESS" ]]; then
           return 0
       else
           return 1
       fi
   }
   ```

2. Replace `_push_handle_build_result()`:
   - Current: calls `_jenkins_status_check "$job_name" "false"` which re-displays everything
   - New: calls `_handle_build_completion "$job_name" "$new_build_number"`
   - Update the call in `cmd_push()` around line ~959

3. Replace `_build_handle_result()`:
   - Current: calls `_jenkins_status_check "$job_name" "false"` which re-displays everything
   - New: calls `_handle_build_completion "$job_name" "$build_number"`
   - Update the call in `cmd_build()` around line ~1207

4. Update `_cmd_status_follow()` post-monitoring logic:
   - Current (lines ~537-539):
     ```bash
     echo ""  # Separator before each build result
     _jenkins_status_check "$job_name" "$json_mode" || true
     ```
   - New:
     ```bash
     _handle_build_completion "$job_name" "$build_number" || true
     ```
   - Note: JSON mode for status -f is a separate concern and can remain handled differently if needed

5. The `_jenkins_status_check()` function itself is NOT deleted—it is still used by `cmd_status()` (non-follow mode, i.e., `buildgit status` without `-f`) for one-shot status display.

### Test Plan

**Test File:** `test/build_completion.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `completion_success_shows_finished` | Successful build shows "Finished: SUCCESS" | 4 |
| `completion_failure_shows_finished` | Failed build shows "Finished: FAILURE" | 4 |
| `completion_unstable_shows_finished` | Unstable build shows "Finished: UNSTABLE" | 4 |
| `completion_failure_shows_test_results` | Failed/unstable build shows test results before Finished line | 4 |
| `completion_success_no_test_results` | Successful build does NOT show test results section | 4 |
| `completion_no_re_display_banner` | Post-completion does NOT re-display BUILD SUCCESSFUL/FAILED banner | 4 |
| `completion_no_re_display_stages` | Post-completion does NOT re-display all stages | 4 |
| `completion_returns_0_for_success` | Returns exit code 0 for SUCCESS | 4 |
| `completion_returns_1_for_failure` | Returns exit code 1 for FAILURE | 4 |
| `push_completion_uses_finished_line` | cmd_push post-monitoring shows "Finished:" not full banner | 5 buildgit push |
| `build_completion_uses_finished_line` | cmd_build post-monitoring shows "Finished:" not full banner | 5 buildgit build |
| `follow_completion_uses_finished_line` | status -f post-monitoring shows "Finished:" not full banner | 5 buildgit status -f |

**Mocking Requirements:**
- Mock `get_build_info` to return completed build JSON with various results
- Mock `fetch_test_results` and `display_test_results` for failure scenarios
- Mock `print_finished_line` or verify its output
- Use `_BUILDGIT_TESTING=1` to source buildgit

**Dependencies:** Chunk A (print_finished_line function), Chunk D (header integration so the header is shown before monitoring, not after)

---

## Definition of Done

For each chunk:
- All unit tests written as part of the chunk have been executed and they pass
- All existing unit tests for the entire project still pass (`./test/bats/bin/bats test/`)
- If the new feature causes an existing test to fail, examine and fix either the implementation or the test as appropriate

## Testing Notes

- **bats-core location:** Use `./test/bats/bin/bats` (bundled in repo), NOT any system bats
- **Test framework:** bats-core for all bash shell tests
- **Test helper:** Load `test_helper` in each test file for shared setup utilities
- **Sourcing buildgit:** Use `_BUILDGIT_TESTING=1` to source buildgit without executing main
- **Spec references:** Each test case must document the spec name and section it validates
