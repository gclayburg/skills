# Usage Help on Invalid Options and Subcommand Help
- **Date:** 2026-02-15T11:00:00-07:00
- **References:** specs/done-reports/usage-help.md
- **Supersedes:** none
- **State:** IMPLEMENTED

## Overview

When users provide unknown or invalid options, `buildgit` should consistently display the full usage help text alongside the error message. Additionally, `-h`/`--help` should be recognized as a valid help request on subcommands (`status`, `build`), not treated as an error.

## Problem Statement

Current behavior is inconsistent:
- `buildgit -garbage` prints an error and full usage (correct)
- `buildgit status -h`, `buildgit status --help`, and other unknown status options print only a one-line error with no usage text
- `buildgit build -h` is treated as an unknown option error with no usage text
- `buildgit status` argument validation errors (invalid build number, unexpected argument) print only a one-line error with no usage text

## Scope

In scope:
- Unknown global options (already partially working — needs stderr fix)
- Unknown `status` options
- Invalid `status` arguments (invalid build number, unexpected argument)
- Unknown `build` options
- `-h`/`--help` as a valid help request on `status` and `build` subcommands

Out of scope:
- `push` command — remains pass-through to git; no option validation changes
- Runtime errors (Jenkins failures, network errors, authentication failures, build not found)
- The existing `buildgit -h` / `buildgit --help` global help path (already correct)

## Specification

### 1. Subcommand Help (`-h`/`--help`)

`buildgit status -h`, `buildgit status --help`, `buildgit build -h`, and `buildgit build --help` must be recognized as valid help requests:
- Print full `show_usage()` output to **stdout**
- Exit 0
- No error message

### 2. Invalid Option/Argument Error Response

For any unknown option or invalid argument error in global parsing, `status`, or `build`:
1. Print the existing one-line error message to stderr (keep current wording)
2. Print a blank line to stderr
3. Print full `show_usage()` output to **stderr**
4. Exit non-zero

This applies to all error paths in option/argument parsing:
- Unknown options (`-*` flags not recognized)
- Invalid arguments (e.g., non-numeric build number for `status`)
- Unexpected arguments (e.g., extra positional args for `status`)
- Invalid option values (e.g., invalid `--console` mode)

### 3. Output Channel Rules

| Scenario | Usage output channel | Exit code |
|----------|---------------------|-----------|
| `-h`/`--help` (global or subcommand) | stdout | 0 |
| Unknown/invalid option or argument | stderr | non-zero |

### 4. Global Unknown Option Fix

The existing global unknown option path already shows error + usage. Update it to send the usage text to **stderr** instead of stdout, consistent with the error channel rules above.

### 5. Push Command — No Changes

The `push` command passes unrecognized options through to `git push`. This behavior is unchanged. No usage display is added for `push`.

### 6. Consistency Rule

Per `specs/README.md`, `buildgit status`, `buildgit status -f`, and `buildgit status --json` must remain consistent. This feature modifies only the option/argument parsing stage which is shared across all status modes, so consistency is maintained by design.

## Implementation Notes

- The `show_usage()` function currently prints to stdout. For error paths, redirect its output to stderr: `show_usage >&2`
- Consider a small helper like `_usage_error()` that prints the error, blank line, and usage to stderr, then exits — to avoid duplicating the pattern at every error site
- `_parse_status_options()` currently returns 1 on error; the caller will need to handle showing usage before exiting, or the function itself can call the helper and exit directly
- `_parse_build_options()` similarly returns 1 on error

## Files to Modify

| File | Changes |
|------|---------|
| `skill/buildgit/scripts/buildgit` | Add `-h`/`--help` handling to `_parse_status_options()` and `_parse_build_options()`. Update all error paths in these functions and global parsing to print `show_usage()` to stderr. Fix global unknown option path to send usage to stderr. |
| `test/buildgit_status.bats` | Add tests for `status -h`, `status --help` showing usage (exit 0). Update existing unknown-option test to assert usage text appears. Add tests for invalid build number and unexpected argument showing usage. |
| `test/buildgit_build.bats` or equivalent | Add tests for `build -h`, `build --help` showing usage (exit 0). Add test for unknown build option showing usage to stderr. |
| `test/buildgit.bats` or equivalent | Verify global unknown option still shows usage, now to stderr. |

## Acceptance Criteria

1. `buildgit status -h` prints full usage to stdout and exits 0.
2. `buildgit status --help` prints full usage to stdout and exits 0.
3. `buildgit build -h` prints full usage to stdout and exits 0.
4. `buildgit build --help` prints full usage to stdout and exits 0.
5. `buildgit status -junk` prints error + full usage to stderr and exits non-zero.
6. `buildgit status --garbage` prints error + full usage to stderr and exits non-zero.
7. `buildgit status abc` (invalid build number) prints error + full usage to stderr and exits non-zero.
8. `buildgit status 5 10` (unexpected argument) prints error + full usage to stderr and exits non-zero.
9. `buildgit build --junk` prints error + full usage to stderr and exits non-zero.
10. `buildgit -garbage` prints error + full usage to stderr and exits non-zero.
11. `buildgit push -h` is passed through to git (no change).
12. Valid command behavior is unchanged for all commands.
