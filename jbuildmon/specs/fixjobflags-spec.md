# Unified Job Name Handling for pushmon.sh and checkbuild.sh
Date: 2026-01-30

## Overview

This specification defines changes to unify how `pushmon.sh` and `checkbuild.sh` handle Jenkins job name resolution. Both scripts will use automatic job detection by default with an optional `--job` flag for manual override.

## Goals

1. Make `pushmon.sh` use the same automatic job detection as `checkbuild.sh`
2. Add `--job <job>` / `-j <job>` option to both scripts for manual override
3. Modernize `pushmon.sh` to use option-style arguments instead of positional arguments

## Non-Goals

- Backwards compatibility with old `pushmon.sh <job-name> <commit-message>` syntax
- Changes to the `discover_job_name()` function in jenkins-common.sh

---

## Section 1: Job Name Resolution Logic

### 1.1 Resolution Priority

Both scripts shall resolve the job name using the following priority:

1. **Explicit flag**: If `--job <job>` or `-j <job>` is provided, use that value and skip auto-detection entirely
2. **Auto-detection**: Call `discover_job_name()` from jenkins-common.sh

### 1.2 Auto-Detection Failure Handling

If auto-detection fails and no `--job` flag was provided, both scripts shall:

1. Exit with error code 1
2. Display an error message explaining how to resolve:
   - Option A: Add `JOB_NAME=<job-name>` to `AGENTS.md` in the repository root
   - Option B: Use the `--job <job>` or `-j <job>` command-line flag

Example error output:
```
ERROR: Could not determine Jenkins job name
To fix this, either:
  1. Add JOB_NAME=<job-name> to AGENTS.md in your repository root
  2. Use the --job <job> or -j <job> flag
```

---

## Section 2: checkbuild.sh Changes

### 2.1 New Command-Line Options

Add the following options while preserving existing options:

| Option | Short | Description |
|--------|-------|-------------|
| `--job <job>` | `-j <job>` | Specify Jenkins job name (overrides auto-detection) |
| `--json` | (none) | Existing option - output results in JSON format |
| `--help` | `-h` | Existing option - show usage information |

### 2.2 Updated Usage

```
Usage: checkbuild.sh [OPTIONS]

Options:
  -j, --job <job>   Specify Jenkins job name (overrides auto-detection)
  --json            Output results in JSON format
  -h, --help        Show this help message

If --job is not specified, the job name is auto-detected from:
  1. JOB_NAME=<value> in AGENTS.md
  2. Git origin URL
```

### 2.3 Argument Parsing Implementation

Update `parse_arguments()` to handle `--job` / `-j` with a required value argument.

---

## Section 3: pushmon.sh Changes

### 3.1 Remove Positional Arguments

Remove the current positional argument handling:
- ~~`<job-name>` (first positional argument)~~
- ~~`<commit-message>` (second positional argument)~~

### 3.2 New Command-Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--job <job>` | `-j <job>` | Specify Jenkins job name (overrides auto-detection) |
| `--msg <message>` | `-m <message>` | Git commit message for staged changes |
| `--help` | `-h` | Show usage information |

### 3.3 Updated Usage

```
Usage: pushmon.sh [OPTIONS]

Options:
  -j, --job <job>     Specify Jenkins job name (overrides auto-detection)
  -m, --msg <message> Git commit message (required if staged changes exist)
  -h, --help          Show this help message

If --job is not specified, the job name is auto-detected from:
  1. JOB_NAME=<value> in AGENTS.md
  2. Git origin URL
```

### 3.4 Commit Message Requirements

The `-m` / `--msg` option behavior:

1. **Staged changes exist + no `-m` provided**: Exit with error
   ```
   ERROR: Staged changes found but no commit message provided
   Use -m or --msg to specify a commit message
   ```

2. **Staged changes exist + `-m` provided**: Commit with the provided message

3. **No staged changes + unpushed commits**: Proceed without committing (message not required)

4. **No staged changes + no unpushed commits**: Exit with error (existing behavior)

### 3.5 Argument Parsing Implementation

Create new `parse_arguments()` function similar to checkbuild.sh:

```bash
parse_arguments() {
    JOB_NAME=""
    COMMIT_MESSAGE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--job)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires a job name"
                    exit 1
                fi
                JOB_NAME="$2"
                shift 2
                ;;
            -m|--msg)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires a commit message"
                    exit 1
                fi
                COMMIT_MESSAGE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}
```

### 3.6 Job Name Resolution in Main Flow

Update `main()` to resolve job name after argument parsing:

```bash
main() {
    parse_arguments "$@"

    # Resolve job name
    local job_name
    if [[ -n "$JOB_NAME" ]]; then
        job_name="$JOB_NAME"
        log_info "Using specified job: $job_name"
    else
        log_info "Discovering Jenkins job name..."
        if ! job_name=$(discover_job_name); then
            log_error "Could not determine Jenkins job name"
            log_info "To fix this, either:"
            log_info "  1. Add JOB_NAME=<job-name> to AGENTS.md in your repository root"
            log_info "  2. Use the --job <job> or -j <job> flag"
            exit 1
        fi
        log_success "Job name: $job_name"
    fi

    # ... rest of main flow
}
```

### 3.7 Staged Changes Validation

Update `check_for_changes()` or add validation after it:

```bash
# After check_for_changes()
if [[ "$HAS_STAGED_CHANGES" == true && -z "$COMMIT_MESSAGE" ]]; then
    log_error "Staged changes found but no commit message provided"
    log_info "Use -m or --msg to specify a commit message"
    exit 1
fi
```

---

## Section 4: Testing Requirements

### 4.1 checkbuild.sh Tests

1. Auto-detection works when no `--job` flag provided
2. `--job` flag overrides auto-detection
3. `-j` short form works identically to `--job`
4. Error message shown when auto-detection fails and no `--job` provided
5. Existing `--json` functionality unaffected

### 4.2 pushmon.sh Tests

1. Auto-detection works when no `--job` flag provided
2. `--job` / `-j` flag overrides auto-detection
3. `-m` / `--msg` flag sets commit message
4. Error when staged changes exist but no `-m` provided
5. Success when only unpushed commits exist (no `-m` required)
6. Error message shown when auto-detection fails and no `--job` provided
7. Help text displays correctly with `-h` / `--help`

---

## Section 5: Migration Notes

### 5.1 Breaking Changes

The following invocation patterns will no longer work:

```bash
# OLD (no longer supported)
pushmon.sh myjob "commit message"

# NEW (required)
pushmon.sh -m "commit message"              # with auto-detection
pushmon.sh -j myjob -m "commit message"     # with explicit job
```

### 5.2 User Communication

Users should be informed of the new syntax. The help text and error messages should clearly indicate the new option-based interface.
