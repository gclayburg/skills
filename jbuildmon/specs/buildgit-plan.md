# Implementation Plan: buildgit

**Spec:** [buildgit-spec.md](./buildgit-spec.md)
**Date:** 2026-01-31

---

## Contents

- [x] **Chunk 1: Script skeleton and global argument parsing**
- [x] **Chunk 2: Verbosity control infrastructure**
- [x] **Chunk 3: Command routing and git passthrough**
- [x] **Chunk 4: Status command - basic functionality**
- [x] **Chunk 5: Status command - follow mode**
- [x] **Chunk 6: Push command**
- [x] **Chunk 7: Build command (trigger and monitor)**
- [x] **Chunk 8: Error handling and edge cases**

---

## Chunk Detail

---

- [x] **Chunk 1: Script skeleton and global argument parsing**

### Description

Create the main `buildgit` script with global option parsing. Global options (`-j/--job`, `-h/--help`, `--verbose`) must appear before the command name and are extracted before delegating to command handlers.

### Spec Reference

See spec [Global Options](./buildgit-spec.md#global-options) and [Command Syntax Summary](./buildgit-spec.md#command-syntax-summary).

### Dependencies

- None (first chunk)

### Produces

- `buildgit` (main script)
- `test/buildgit_args.bats`

### Implementation Details

1. Create `buildgit` script with shebang and `set -euo pipefail`:
   - Source `lib/jenkins-common.sh` for shared functionality
   - Define global variables: `JOB_NAME`, `VERBOSE_MODE`, `COMMAND`, `COMMAND_ARGS`

2. Implement `parse_global_options()` function:
   - Loop through arguments until a non-option (command) is found
   - Handle `-j|--job <name>` - store in `JOB_NAME`
   - Handle `-h|--help` - show usage and exit
   - Handle `--verbose` - set `VERBOSE_MODE=true`
   - Stop parsing at first non-option argument (the command)
   - Store remaining arguments in `COMMAND_ARGS` array

3. Implement `show_usage()` function:
   - Display help text matching spec Command Syntax Summary
   - Include all global options, commands, and examples

4. Implement `main()` function:
   - Call `parse_global_options "$@"`
   - If no command provided, show usage and exit 1
   - Placeholder for command routing (implemented in Chunk 3)

### Test Plan

**Test File:** `test/buildgit_args.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `parse_global_job_short_flag` | `-j myjob status` extracts job name correctly | Global Options |
| `parse_global_job_long_flag` | `--job myjob status` extracts job name correctly | Global Options |
| `parse_global_verbose_flag` | `--verbose status` sets verbose mode | Global Options |
| `parse_global_help_short` | `-h` shows usage and exits 0 | Global Options |
| `parse_global_help_long` | `--help` shows usage and exits 0 | Global Options |
| `parse_global_multiple_options` | `-j myjob --verbose status` parses all options | Global Options |
| `parse_global_no_command` | No command shows usage and exits 1 | Command Syntax |
| `parse_global_options_before_command` | Options after command are passed through | Command Syntax |
| `parse_job_missing_value` | `-j` without value shows error | Global Options |

**Mocking Requirements:**
- None for argument parsing tests

**Dependencies:** None

---

- [x] **Chunk 2: Verbosity control infrastructure**

### Description

Implement verbose/quiet mode logging. Default is quiet mode (suppresses informational messages). `--verbose` enables all messages. Create wrapper functions around `jenkins-common.sh` logging that respect verbosity setting.

### Spec Reference

See spec [Verbosity Behavior](./buildgit-spec.md#verbosity-behavior).

### Dependencies

- Chunk 1 (script skeleton with `VERBOSE_MODE` variable)

### Produces

- Updates to `buildgit` (add logging wrappers)
- `test/buildgit_verbosity.bats`

### Implementation Details

1. Add verbosity-aware logging wrapper functions to `buildgit`:
   - `bg_log_info()` - Only output if `VERBOSE_MODE=true`
   - `bg_log_success()` - Only output if `VERBOSE_MODE=true`
   - `bg_log_warning()` - Always output (warnings are important)
   - `bg_log_error()` - Always output (errors are critical)
   - `bg_log_essential()` - Always output (git output, build results, test failures)

2. Define which messages are suppressed in quiet mode:
   - Suppressed: "Connected to Jenkins", "Found job name", "Analyzing build details...", "Waiting for build to start...", "Verifying Jenkins connectivity...", "Verifying job exists..."
   - Shown: git command output, build results, errors/failures, test failure details

3. Implement message categorization:
   - Essential messages use `bg_log_essential()`
   - Informational messages use `bg_log_info()` or `bg_log_success()`

### Test Plan

**Test File:** `test/buildgit_verbosity.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `quiet_mode_suppresses_info` | Info messages hidden without --verbose | Verbosity Behavior |
| `quiet_mode_shows_errors` | Error messages shown without --verbose | Verbosity Behavior |
| `quiet_mode_shows_warnings` | Warning messages shown without --verbose | Verbosity Behavior |
| `verbose_mode_shows_info` | Info messages shown with --verbose | Verbosity Behavior |
| `quiet_mode_shows_build_results` | Build results shown without --verbose | Verbosity Behavior |
| `quiet_mode_shows_git_output` | Git command output shown without --verbose | Verbosity Behavior |

**Mocking Requirements:**
- Mock logging functions to capture output

**Dependencies:** Chunk 1

---

- [x] **Chunk 3: Command routing and git passthrough**

### Description

Implement command routing in `main()` to dispatch to appropriate handlers. Unknown commands pass through to git.

### Spec Reference

See spec [Commands](./buildgit-spec.md#commands) and [Unknown Commands](./buildgit-spec.md#unknown-commands).

### Dependencies

- Chunk 1 (script skeleton)
- Chunk 2 (verbosity control)

### Produces

- Updates to `buildgit` (command routing logic)
- `test/buildgit_routing.bats`

### Implementation Details

1. Implement command routing in `main()`:
   ```bash
   case "$COMMAND" in
       status) cmd_status "${COMMAND_ARGS[@]}" ;;
       push)   cmd_push "${COMMAND_ARGS[@]}" ;;
       build)  cmd_build "${COMMAND_ARGS[@]}" ;;
       *)      cmd_passthrough "$COMMAND" "${COMMAND_ARGS[@]}" ;;
   esac
   ```

2. Implement `cmd_passthrough()` function:
   - Execute `git "$@"` with all provided arguments
   - Return git's exit code
   - No Jenkins interaction

3. Add placeholder stub functions for `cmd_status`, `cmd_push`, `cmd_build`:
   - Each prints "Not implemented" and exits 1
   - Will be implemented in subsequent chunks

### Test Plan

**Test File:** `test/buildgit_routing.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `route_status_command` | `buildgit status` routes to status handler | Commands |
| `route_push_command` | `buildgit push` routes to push handler | Commands |
| `route_build_command` | `buildgit build` routes to build handler | Commands |
| `passthrough_log` | `buildgit log` passes to git log | Unknown Commands |
| `passthrough_diff` | `buildgit diff HEAD~1` passes to git diff | Unknown Commands |
| `passthrough_checkout` | `buildgit checkout -b feature` passes to git | Unknown Commands |
| `passthrough_preserves_args` | Arguments preserved in passthrough | Unknown Commands |
| `passthrough_exit_code` | Git exit code returned from passthrough | Unknown Commands |

**Mocking Requirements:**
- Mock git command for passthrough tests
- Create a test git repository

**Dependencies:** Chunk 1, Chunk 2

---

- [x] **Chunk 4: Status command - basic functionality**

### Description

Implement `buildgit status` to display combined git status and Jenkins build status. Reuses display logic from `checkbuild.sh`.

### Spec Reference

See spec [`buildgit status`](./buildgit-spec.md#buildgit-status) and [Output Format](./buildgit-spec.md#output-format).

### Dependencies

- Chunk 1 (script skeleton)
- Chunk 2 (verbosity control)
- Chunk 3 (command routing)
- `jenkins-common.sh` (existing functions)

### Produces

- Updates to `buildgit` (implement `cmd_status`)
- `test/buildgit_status.bats`

### Implementation Details

1. Implement `cmd_status()` function:
   - Parse status-specific options: `--json`, `-f/--follow`, pass others to git
   - Separate buildgit options from git options

2. Implement status display sequence:
   - Execute `git status` with any passthrough options, display output
   - Print blank line separator
   - Perform Jenkins status check (reuse logic from checkbuild.sh)

3. Reuse existing Jenkins functions from `jenkins-common.sh`:
   - `validate_environment()`, `validate_dependencies()`
   - `discover_job_name()` or use `JOB_NAME` if provided via `-j`
   - `verify_jenkins_connection()`, `verify_job_exists()`
   - `get_last_build_number()`, `get_build_info()`
   - `display_success_output()`, `display_failure_output()`, `display_building_output()`
   - `output_json()` for `--json` mode

4. Implement `--json` mode:
   - Git status output first (plain text)
   - Blank line
   - JSON build status (using `output_json()`)

5. Handle exit codes per spec:
   - Exit 0 if build successful
   - Exit 1 if build failed
   - Exit 2 if build in progress (match checkbuild.sh behavior)

### Test Plan

**Test File:** `test/buildgit_status.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `status_shows_git_status` | Output includes git status | buildgit status |
| `status_shows_jenkins_status` | Output includes Jenkins build info | buildgit status |
| `status_git_options_passthrough` | `-s` passed to git status | Options |
| `status_json_output` | `--json` outputs JSON build status | Options |
| `status_with_job_flag` | `--job` overrides auto-detection | Global Options |
| `status_exit_code_success` | Exit 0 for successful build | Exit Codes |
| `status_exit_code_failure` | Exit 1 for failed build | Exit Codes |
| `status_exit_code_building` | Exit 2 for in-progress build | Exit Codes |
| `status_jenkins_unavailable` | Shows git status, error for Jenkins | Error Handling |

**Mocking Requirements:**
- Mock `jenkins_api()` to return canned responses
- Mock git commands
- Create test fixtures for build JSON responses

**Dependencies:** Chunk 1, 2, 3

---

- [x] **Chunk 5: Status command - follow mode**

### Description

Implement `buildgit status -f/--follow` to continuously monitor builds. Monitor current build if in progress, then wait for subsequent builds indefinitely.

### Spec Reference

See spec [`buildgit status` Options](./buildgit-spec.md#buildgit-status) - the `-f, --follow` option.

### Dependencies

- Chunk 4 (basic status command)

### Produces

- Updates to `buildgit` (add follow mode to `cmd_status`)
- `test/buildgit_status_follow.bats`

### Implementation Details

1. Add follow mode parsing to `cmd_status()`:
   - Detect `-f` or `--follow` option
   - Set `FOLLOW_MODE=true`

2. Implement follow mode loop:
   ```bash
   while true; do
       # Get current build info
       # If building, monitor until complete
       # Display result
       # Display "Waiting for next build of <job>..."
       # Poll for new build (compare build numbers)
       # When new build detected, continue loop
   done
   ```

3. Reuse monitoring logic from `pushmon.sh`:
   - `monitor_build()` for tracking in-progress builds
   - `handle_build_result()` for displaying results

4. Implement interrupt handler for Ctrl+C:
   - Clean exit with message about how to resume monitoring

5. Display "Waiting for next build of <job>..." between builds:
   - Use `bg_log_essential()` for this message (always shown)

### Test Plan

**Test File:** `test/buildgit_status_follow.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `follow_monitors_current_build` | Monitors in-progress build to completion | Options |
| `follow_waits_for_next_build` | Shows waiting message after build completes | Options |
| `follow_detects_new_build` | Detects and monitors new build | Options |
| `follow_ctrl_c_exits_cleanly` | Ctrl+C exits with appropriate message | Options |
| `follow_displays_results` | Each build result displayed | Options |

**Mocking Requirements:**
- Mock `jenkins_api()` to simulate build lifecycle
- Mock sleep/poll timing for faster tests
- Use timeout in tests to prevent infinite loops

**Dependencies:** Chunk 4

---

- [x] **Chunk 6: Push command**

### Description

Implement `buildgit push` to push commits and monitor the resulting Jenkins build. Supports `--no-follow` to skip monitoring.

### Spec Reference

See spec [`buildgit push`](./buildgit-spec.md#buildgit-push).

### Dependencies

- Chunk 1-3 (script infrastructure)
- Chunk 4 (status display for build results)
- `jenkins-common.sh` and patterns from `pushmon.sh`

### Produces

- Updates to `buildgit` (implement `cmd_push`)
- `test/buildgit_push.bats`

### Implementation Details

1. Implement `cmd_push()` function:
   - Parse `--no-follow` option
   - Separate buildgit options from git push options

2. Implement push sequence:
   - Validate environment and Jenkins connection
   - Execute `git push` with passthrough arguments
   - Capture git push output and exit code
   - If git push fails, exit with git's exit code
   - If "nothing to push" (git exit 0 with appropriate message), exit 0

3. Implement build monitoring (unless `--no-follow`):
   - Record baseline build number before push
   - Wait for new build to start (reuse `wait_for_build_start()` from pushmon.sh pattern)
   - Monitor build until completion (reuse `monitor_build()` pattern)
   - Display build result
   - Exit with appropriate code (0 success, non-zero failure)

4. Handle `--no-follow` mode:
   - Push only, then exit with git's exit code
   - Do not wait for or monitor Jenkins build

### Test Plan

**Test File:** `test/buildgit_push.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `push_executes_git_push` | Runs git push with args | buildgit push |
| `push_monitors_build` | Monitors Jenkins build after push | buildgit push |
| `push_no_follow_skips_monitor` | `--no-follow` skips monitoring | Options |
| `push_nothing_to_push` | Exits cleanly when nothing to push | Notes |
| `push_git_failure_exit_code` | Returns git exit code on failure | Exit Code |
| `push_build_failure_exit_code` | Returns non-zero on build failure | Exit Code |
| `push_passthrough_args` | `origin feature` passed to git push | Examples |
| `push_with_job_flag` | `-j myjob` specifies job | Global Options |

**Mocking Requirements:**
- Mock git push command
- Mock Jenkins API for build detection and monitoring
- Create test git repository with remote

**Dependencies:** Chunk 1-4

---

- [x] **Chunk 7: Build command (trigger and monitor)**

### Description

Implement `buildgit build` to trigger a Jenkins build and monitor it. This is equivalent to pressing "Build Now" in Jenkins.

### Spec Reference

See spec [`buildgit build`](./buildgit-spec.md#buildgit-build).

### Dependencies

- Chunk 1-3 (script infrastructure)
- Chunk 4 (status display)
- `jenkins-common.sh`

### Produces

- Updates to `buildgit` (implement `cmd_build`)
- Updates to `lib/jenkins-common.sh` (add `trigger_build()` function if not exists)
- `test/buildgit_build.bats`

### Implementation Details

1. Implement `cmd_build()` function:
   - Parse `--no-follow` option
   - Require job name (error if not specified and auto-detection fails)

2. Add `trigger_build()` function to `jenkins-common.sh`:
   - POST to `/job/{job}/build` endpoint
   - Return queue item URL from Location header
   - Handle authentication and errors

3. Implement build trigger sequence:
   - Validate environment and Jenkins connection
   - Verify job exists
   - Trigger build via Jenkins API
   - Display "Build triggered" confirmation

4. Implement build monitoring (unless `--no-follow`):
   - Wait for build to move from queue to execution
   - Monitor build until completion
   - Display build result
   - Exit with appropriate code

5. Implement `--no-follow` mode:
   - Trigger build and confirm queued
   - Exit immediately without monitoring

6. Error handling:
   - If `--job` not specified and auto-detection fails, error out with descriptive message
   - Handle trigger API failures

### Test Plan

**Test File:** `test/buildgit_build.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `build_triggers_jenkins` | Triggers build via Jenkins API | buildgit build |
| `build_monitors_to_completion` | Monitors triggered build | buildgit build |
| `build_no_follow_exits_early` | `--no-follow` exits after trigger | Options |
| `build_success_exit_code` | Exit 0 on successful build | Exit Code |
| `build_failure_exit_code` | Exit non-zero on failed build | Exit Code |
| `build_requires_job_name` | Error if job not specified/detected | Error Handling |
| `build_with_job_flag` | `-j myjob` specifies job | Global Options |
| `build_trigger_api_failure` | Handles API errors gracefully | Error Handling |

**Mocking Requirements:**
- Mock Jenkins API for trigger and monitoring
- Mock build queue and execution states

**Dependencies:** Chunk 1-4

---

- [x] **Chunk 8: Error handling and edge cases**

### Description

Implement comprehensive error handling for all edge cases: Jenkins unavailable, non-git directory, job detection failure. Ensure graceful degradation where possible.

### Spec Reference

See spec [Error Handling](./buildgit-spec.md#error-handling).

### Dependencies

- All previous chunks (1-7)

### Produces

- Updates to `buildgit` (error handling logic throughout)
- `test/buildgit_errors.bats`

### Implementation Details

1. Handle Jenkins unavailable:
   - For `status`: Show git status, then display Jenkins connectivity error
   - For `push`: Complete git push, then show Jenkins error and exit non-zero
   - For `build`: Fail immediately with descriptive error

2. Handle non-git directory:
   - Git commands produce stderr and non-zero exit codes (let git handle this)
   - Still attempt Jenkins operations if `--job` is provided
   - Display git's error message

3. Handle job detection failure:
   - For `status`: Show git status, display error for Jenkins portion
   - For `build`: Exit with error and descriptive message
   - For `push`: Complete git push, display error about Jenkins monitoring

4. Implement graceful error messages:
   - Include actionable suggestions (e.g., "Use --job to specify job name")
   - Distinguish between recoverable and fatal errors

5. Ensure exit codes match spec:
   - Git failure: git's exit code
   - Jenkins build failure: non-zero
   - Jenkins unavailable during push: non-zero (after git completes)

### Test Plan

**Test File:** `test/buildgit_errors.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `error_jenkins_unavailable_status` | Status shows git, then Jenkins error | Jenkins Unavailable |
| `error_jenkins_unavailable_push` | Push completes, shows Jenkins error | Jenkins Unavailable |
| `error_jenkins_unavailable_build` | Build fails immediately | Jenkins Unavailable |
| `error_non_git_directory_status` | Shows git error, attempts Jenkins | Non-Git Directory |
| `error_non_git_directory_with_job` | Uses --job when not in git repo | Non-Git Directory |
| `error_job_detection_failure_status` | Shows git status, Jenkins error | Job Detection Failure |
| `error_job_detection_failure_build` | Build exits with error message | Job Detection Failure |
| `error_actionable_messages` | Error messages include suggestions | Error Handling |

**Mocking Requirements:**
- Mock Jenkins API to return errors/timeouts
- Test outside of git repository
- Mock job name detection failure

**Dependencies:** Chunks 1-7

---

## Definition of Done

For each chunk:
1. All unit tests written as part of this task have been executed and pass
2. All existing unit tests of the entire project still pass
3. Code follows existing patterns in the codebase
4. Documentation in script header and usage output matches spec
5. Exit codes match specification
