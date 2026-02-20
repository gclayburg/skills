# Feature: Separate Count Flag for Line Mode and Oldest-First Ordering

- **Date:** `2026-02-19T00:00:00-07:00`
- **References:** none
- **Supersedes:** `2026-02-15_quick-status-line-spec.md` (partially — replaces `--line=N` syntax and output ordering)
- **State:** `IMPLEMENTED`

## Overview

Two related changes to `buildgit status --line`:

1. **Remove `--line=N` syntax.** The count of builds to show is moved to a dedicated `-n <count>` flag. `--line` becomes a pure boolean mode flag with no value.
2. **Reverse output ordering.** Multi-build line mode currently prints newest-first. Change it to oldest-first (newest build on the last line), matching conventional log output. The exit code stays based on the newest build, which is now the last printed line.

## Current Syntax vs New Syntax

| Old | New |
|-----|-----|
| `buildgit status --line` | `buildgit status --line` (unchanged) |
| `buildgit status --line=5` | `buildgit status -n 5 --line` |
| `buildgit status --line=10` | `buildgit status -n 10 --line` |
| `buildgit status 41 --line=3` | `buildgit status 41 -n 3 --line` |

## Current Output vs New Output (for multi-build)

**Current** (`--line=3`, newest-first):
```text
SUCCESS     Job ralph1 #42 Tests=557/0/0 Took 4m 10s on 2026-02-15 (just now)
FAILURE     Job ralph1 #41 Tests=376/1/30 Took 3m 55s on 2026-02-15 (15 minutes ago)
SUCCESS     Job ralph1 #40 Tests=557/0/0 Took 6m 41s on 2026-02-13 (2 days ago)
```

**New** (`-n 3 --line`, oldest-first):
```text
SUCCESS     Job ralph1 #40 Tests=557/0/0 Took 6m 41s on 2026-02-13 (2 days ago)
FAILURE     Job ralph1 #41 Tests=376/1/30 Took 3m 55s on 2026-02-15 (15 minutes ago)
SUCCESS     Job ralph1 #42 Tests=557/0/0 Took 4m 10s on 2026-02-15 (just now)
```

The newest build is always the last line. Exit code is based on the last printed line (the newest build).

## Specification

### 1. Remove `--line=N` Syntax

`--line` no longer accepts an `=N` value. Any attempt to use `--line=<value>` is now a usage error:

```text
Error: --line does not accept a value; use -n <count> to specify number of builds
```

The `-l` short form continues to work as an alias for `--line` (boolean, no value).

### 2. New `-n <count>` Flag on `status`

`buildgit status` gains a new option:

```text
-n <count>    Number of builds to show in line mode (default: 1)
```

Rules:
- `<count>` must be a positive integer (`1, 2, 3, ...`)
- `-n` is only meaningful in line mode (`--line`). When used without `--line`, it is accepted but silently ignored (same as `--no-tests` with `--all`).
- `-n 1` is equivalent to plain `--line` (single build)
- When combined with a positional `[build#]`, `-n <count>` shows that build and the `<count>-1` builds before it (same anchor logic as before)

If `<count>` is missing or invalid:
- `Error: -n requires a positive integer argument`
- Exit non-zero

### 3. Oldest-First Output Ordering

Multi-build line mode (`-n N` where `N > 1`) changes from newest-first to oldest-first:

1. Fetch the `N` most recent builds (newest to oldest) as before
2. Reverse the list before printing
3. Print oldest build first, newest build last

Single-build mode (`--line` / `-n 1`) is unaffected (only one line).

### 4. Exit Code Update

With oldest-first ordering, the exit code is based on the **last** printed line (the newest build):
- `0` if newest build result is `SUCCESS`
- `1` otherwise (`FAILURE`, `UNSTABLE`, `ABORTED`, etc.)
- For in-progress builds, exit `0` (build is running)

This is consistent with the existing rule that exit code always reflects the newest/anchor build. Only the visual position changes (was first line, now last line).

### 5. Option Compatibility

`-n` shares the same compatibility rules as `--line`:

| Option | Compatible with `-n` | Behavior |
|--------|----------------------|----------|
| `--line` / `-l` | Yes | Required to activate line mode |
| `--all` / `-a` | No — error if `-n` is combined with `--all` explicitly | See error below |
| `--json` | No — error | See error below |
| `-f` / `--follow` | No — error | See error below |
| `[build#]` positional | Yes | Anchor; show that build and previous `N-1` builds |
| `--no-tests` | Yes | Skip test API calls |
| `--job <name>` | Yes | Use specified job |

Error messages for incompatible combinations involving `-n`:
- `-n` with `--all`: `Error: Cannot use -n with --all`
- `-n` with `--json`: `Error: Cannot use -n with --json`
- `-n` with `--follow`: `Error: Cannot use -n with --follow`

### 6. Help Text Update

Update `show_usage()`:

```text
Commands:
  status [build#] [-f|--follow] [--once] [--json] [--line] [-n <count>] [--all] [--no-tests]
                      Display Jenkins build status (latest or specific build)
                      Default: full output on TTY, one-line on pipe/redirect
```

Update examples:

```text
  buildgit status --line           # One-line status with test results
  buildgit status -n 5 --line      # Last 5 builds, oldest first, one line each
  buildgit status -n 10 --no-tests # Last 10 builds, skip test fetch
  buildgit status --all | less     # Full status piped to pager
```

### 7. Consistency Rule

Per `CLAUDE.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must be consistent. This change only affects the line mode snapshot path. Full status, follow, and JSON modes are unchanged.

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Update `_parse_status_options()`: remove `--line=*` case, add `-n <count>` parsing with validation, reject `--line=<value>` with error. Update `_status_line_check()`: reverse build order before printing. Update exit code logic to use last-printed build. Update `show_usage()`. |
| `test/buildgit_status.bats` | Update tests for old `--line=N` to use `-n N --line`. Add tests for: oldest-first ordering with `-n 3`, exit code based on last line, `-n` without `--line` is silently ignored, `--line=5` is an error, `-n` with invalid argument is an error. |

## Acceptance Criteria

1. `buildgit status --line` works unchanged for single-build output.
2. `buildgit status -l` is unchanged.
3. `buildgit status -n 5 --line` prints 5 builds, oldest first, one line each.
4. `buildgit status -n 1 --line` is equivalent to `buildgit status --line`.
5. `buildgit status 41 -n 3 --line` prints builds #39, #40, #41 (oldest first).
6. `buildgit status --line=5` produces an error with a message directing the user to use `-n`.
7. `-n` without `--line` is silently accepted (no output change; line mode not active).
8. `-n 0`, `-n -1`, `-n abc` all produce a usage error and non-zero exit.
9. `-n` without an argument produces a usage error and non-zero exit.
10. Exit code is `0` when the last printed line (newest build) is `SUCCESS`, else `1`.
11. Help text documents `-n <count>` and shows the new example syntax.
12. All existing tests continue to pass with updated syntax.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `status_line_n_flag_basic` | `-n 3 --line` prints 3 lines oldest-first |
| `status_line_n_flag_ordering` | Verify build numbers in output are ascending (oldest first) |
| `status_line_n_one_is_same` | `-n 1 --line` output matches `--line` alone |
| `status_line_n_with_build_number` | `status 41 -n 3 --line` prints builds 39, 40, 41 in that order |
| `status_line_exit_code_newest_last` | When newest build fails and older ones pass, exit code is 1 (based on last line) |
| `status_line_exit_code_newest_success` | When newest build succeeds and older ones fail, exit code is 0 |
| `status_line_equals_syntax_error` | `--line=5` produces error referencing `-n` flag |
| `status_line_n_no_arg_error` | `-n` with no following argument produces usage error |
| `status_line_n_invalid_zero` | `-n 0` produces usage error |
| `status_line_n_invalid_negative` | `-n -1` produces usage error |
| `status_line_n_invalid_text` | `-n abc` produces usage error |
| `status_line_n_without_line_mode` | `-n 5` without `--line` is silently ignored; full output shown on TTY |
| `status_line_n_rejects_all` | `-n 5 --all` produces error |
| `status_line_n_rejects_json` | `-n 5 --json` produces error |
| `status_line_n_rejects_follow` | `-n 5 -f` produces error |
