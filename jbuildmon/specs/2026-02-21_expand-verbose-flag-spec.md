## Add `-v` short alias for `--verbose` global option

- **Date:** `2026-02-21T13:55:56-0700`
- **References:** `specs/done-reports/expand-verbose-flag`
- **Supersedes:** (none)
- **State:** `IMPLEMENTED`

## Background

The `buildgit` CLI currently supports `--verbose` as a global option to enable verbose/debug output. There is no `-v` short form, which is inconsistent with common CLI conventions (most tools accept `-v` as shorthand for `--verbose`).

## Specification

Add `-v` as a global-option alias for `--verbose` in `parse_global_options()`.

### Changes

1. **Global option parsing** (`parse_global_options` in `buildgit`):
   - Add `-v` to the existing `--verbose)` case arm so both `-v` and `--verbose` set `VERBOSE_MODE=true`.

2. **Help text** (`show_usage` in `buildgit`):
   - Update the `--verbose` line in the Global Options section to read:
     ```
     -v, --verbose                  Enable verbose output for debugging
     ```

3. **Usage-error handling**:
   - `-v` must no longer trigger the `_usage_error "Unknown global option"` path (already handled by adding it to the case arm).

### Scope

- `-v` is a **global option only** — accepted before the subcommand, in the same position as `--verbose`.
- It is **not** accepted as a subcommand-level option.

## Test Strategy

Add tests in a new or existing bats file:

1. **`-v` sets verbose mode** — run `buildgit -v status --help` (or similar) and confirm verbose output is produced (same behavior as `--verbose`).
2. **`-v` appears in help** — run `buildgit --help` and assert the output contains `-v, --verbose`.
3. **Existing `--verbose` tests still pass** — no regressions.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
