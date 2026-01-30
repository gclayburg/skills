# Implementation Plan: Unified Job Name Handling

Spec: [fixjobflags-spec.md](./fixjobflags-spec.md)

## Contents

- [x] **Chunk A: Add --job/-j flag to checkbuild.sh**
- [x] **Chunk B: Modernize pushmon.sh argument handling**

---

## Chunk Detail

- [x] **Chunk A: Add --job/-j flag to checkbuild.sh**

### Description

Add the `--job <job>` / `-j <job>` command-line option to `checkbuild.sh` to allow manual override of the auto-detected Jenkins job name. Update the error handling to display a helpful message when auto-detection fails.

### Spec Reference

See spec [Section 2: checkbuild.sh Changes](./fixjobflags-spec.md#section-2-checkbuildsh-changes) and [Section 1: Job Name Resolution Logic](./fixjobflags-spec.md#section-1-job-name-resolution-logic).

### Dependencies

- None

### Produces

- `checkbuild.sh` (modified)
- `test/checkbuild_job_flag.bats`

### Implementation Details

1. Update `parse_arguments()` in `checkbuild.sh`:
   - Add `JOB_NAME=""` initialization at the start
   - Add case handling for `-j|--job` with required value validation
   - Export `JOB_NAME` alongside `JSON_OUTPUT_MODE`

2. Update `show_usage()` in `checkbuild.sh`:
   - Add `-j, --job <job>` option to help text
   - Add explanation that auto-detection is used when `--job` is not specified
   - Match the format shown in spec Section 2.2

3. Update `main()` in `checkbuild.sh`:
   - After `parse_arguments()`, check if `JOB_NAME` is set from command line
   - If set, use it directly and skip `discover_job_name()` call
   - If not set, call `discover_job_name()` as currently done
   - On auto-detection failure, display the enhanced error message per spec Section 1.2

### Test Plan

**Test File:** `test/checkbuild_job_flag.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `job_flag_overrides_autodetection` | Verify `--job myjob` uses provided job name instead of calling discover_job_name | 2.1, 1.1 |
| `job_short_flag_works` | Verify `-j myjob` works identically to `--job myjob` | 2.1 |
| `job_flag_missing_value_errors` | Verify `--job` without value shows error and exits 1 | 2.3 |
| `job_flag_empty_value_errors` | Verify `--job ""` shows error for empty value | 2.3 |
| `autodetect_failure_shows_help_message` | When no `--job` and auto-detection fails, verify error message mentions both AGENTS.md and --job flag | 1.2 |
| `json_flag_still_works_with_job_flag` | Verify `--job myjob --json` works correctly | 4.1.5 |
| `help_shows_job_option` | Verify `-h` output includes `--job` option description | 2.2 |

**Mocking Requirements:**
- Mock `discover_job_name()` to control auto-detection behavior
- Mock Jenkins API calls (`jenkins_api`, `get_build_info`) to avoid network calls
- Use `create_mock_git_repo` from test_helper.bash

**Dependencies:** None

---

- [x] **Chunk B: Modernize pushmon.sh argument handling**

### Description

Replace `pushmon.sh` positional argument handling with modern option-style arguments. Add `--job/-j` for job name override, `--msg/-m` for commit message, and `--help/-h` for usage. Implement job name resolution with auto-detection fallback and commit message validation for staged changes.

### Spec Reference

See spec [Section 3: pushmon.sh Changes](./fixjobflags-spec.md#section-3-pushmonsh-changes) and [Section 1: Job Name Resolution Logic](./fixjobflags-spec.md#section-1-job-name-resolution-logic).

### Dependencies

- None (can be implemented independently of Chunk A)

### Produces

- `pushmon.sh` (modified)
- `test/pushmon_args.bats`

### Implementation Details

1. Remove `validate_arguments()` function:
   - Delete the function that checks for 2 positional arguments

2. Create new `parse_arguments()` function:
   - Initialize `JOB_NAME=""` and `COMMIT_MESSAGE=""`
   - Add case handling for `-j|--job` with required value
   - Add case handling for `-m|--msg` with required value
   - Add case handling for `-h|--help` that calls `usage` and exits 0
   - Add default case that errors on unknown options
   - Use `shift 2` pattern for options with values
   - Reference implementation in spec Section 3.5

3. Update `usage()` function:
   - Replace positional argument documentation with option-style format
   - Add `-j, --job <job>` option
   - Add `-m, --msg <message>` option
   - Add `-h, --help` option
   - Add note about auto-detection when `--job` not specified
   - Match format shown in spec Section 3.3

4. Update `main()` function for job resolution:
   - Replace `validate_arguments "$@"` with `parse_arguments "$@"`
   - Remove `local job_name="$1"` and `local commit_message="$2"` lines
   - Add job resolution block per spec Section 3.6:
     - If `JOB_NAME` is set, use it directly with log message "Using specified job: $job_name"
     - If not set, call `discover_job_name()` with log message "Discovering Jenkins job name..."
     - On auto-detection failure, show error message per spec Section 1.2 and exit 1
   - Replace `$commit_message` references with `$COMMIT_MESSAGE`

5. Add staged changes validation after `check_for_changes()`:
   - If `HAS_STAGED_CHANGES == true` and `COMMIT_MESSAGE` is empty, exit with error
   - Error message per spec Section 3.4:
     ```
     ERROR: Staged changes found but no commit message provided
     Use -m or --msg to specify a commit message
     ```
   - This replaces the previous unconditional use of positional `$commit_message`

6. Update `commit_changes()` call:
   - Change from `commit_changes "$commit_message"` to `commit_changes "$COMMIT_MESSAGE"`

### Test Plan

**Test File:** `test/pushmon_args.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `job_flag_sets_job_name` | Verify `--job myjob` sets JOB_NAME correctly | 3.2 |
| `job_short_flag_works` | Verify `-j myjob` works identically to `--job` | 3.2 |
| `msg_flag_sets_commit_message` | Verify `--msg "my message"` sets COMMIT_MESSAGE | 3.2 |
| `msg_short_flag_works` | Verify `-m "my message"` works identically to `--msg` | 3.2 |
| `help_flag_shows_usage` | Verify `--help` displays usage and exits 0 | 3.2, 4.2.7 |
| `help_short_flag_works` | Verify `-h` works identically to `--help` | 3.2 |
| `unknown_option_errors` | Verify unknown options like `--foo` exit with error | 3.5 |
| `job_flag_missing_value_errors` | Verify `--job` without value shows error | 3.5 |
| `msg_flag_missing_value_errors` | Verify `--msg` without value shows error | 3.5 |
| `positional_args_rejected` | Verify old-style `pushmon.sh myjob "msg"` is rejected | 5.1 |
| `autodetect_used_when_no_job_flag` | When no `--job`, verify `discover_job_name()` is called | 1.1 |
| `autodetect_failure_shows_help_message` | When no `--job` and auto-detection fails, verify error message | 1.2 |
| `staged_changes_without_msg_errors` | Staged changes + no `-m` exits with specific error | 3.4.1 |
| `staged_changes_with_msg_succeeds` | Staged changes + `-m` provided proceeds to commit | 3.4.2 |
| `unpushed_commits_no_msg_succeeds` | No staged changes + unpushed commits works without `-m` | 3.4.3 |
| `combined_flags_work` | Verify `-j myjob -m "message"` works together | 3.2 |

**Mocking Requirements:**
- Mock `discover_job_name()` to control auto-detection behavior
- Mock `check_for_changes()` to control `HAS_STAGED_CHANGES` state
- Mock git operations (`git diff --cached`, `git commit`, `git push`) to avoid side effects
- Mock Jenkins API calls to avoid network calls
- Use `create_mock_git_repo` from test_helper.bash

**Dependencies:** None
