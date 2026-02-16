# Feature: Line Mode Status Column Alignment and Color

- **Date:** `2026-02-15T16:32:39-07:00`
- **References:** `specs/done-reports/line-jobs-enhance.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Overview

Enhance `buildgit status --line` output to align the status result field to a fixed width and apply color coding. This makes multi-line output (`--line=N`) visually consistent and easier to scan. Colors follow the existing Jenkins result color rules and are suppressed when stdout is not a TTY.

## Problem Statement

Current `--line=10` output has ragged alignment because result strings vary in length (`SUCCESS` = 7, `UNSTABLE` = 8, `FAILURE` = 7, `IN_PROGRESS` = 11):

```text
UNSTABLE Job ralph1 #176 completed in 4m 37s on 2026-02-15 (42 minutes ago)
SUCCESS Job ralph1 #174 completed in 4m 32s on 2026-02-14 (19 hours ago)
```

## Specification

### 1. Fixed-Width Status Field

The result field in line mode output is padded or truncated to exactly **11 characters** (accommodating the longest standard status, `IN_PROGRESS`).

- Pad with trailing spaces when the result is shorter than 11 characters
- Truncate to 11 characters if the result exceeds that width (no known Jenkins result does, but this is a safety guard)

Before:
```text
UNSTABLE Job ralph1 #176 completed in 4m 37s on 2026-02-15 (42 minutes ago)
SUCCESS Job ralph1 #174 completed in 4m 32s on 2026-02-14 (19 hours ago)
```

After:
```text
UNSTABLE    Job ralph1 #176 completed in 4m 37s on 2026-02-15 (42 minutes ago)
SUCCESS     Job ralph1 #174 completed in 4m 32s on 2026-02-14 (19 hours ago)
IN_PROGRESS Job ralph1 #177 running for 1m 22s (started 2026-02-15 16:30)
```

Implementation: use `printf "%-11.11s"` to left-align, pad, and truncate in a single operation.

### 2. Color Coding the Status Field

Apply color to the result field using the same color mapping already used in `print_finished_line()` in `jenkins-common.sh`:

| Result | Color |
|--------|-------|
| `SUCCESS` | Green (`COLOR_GREEN`) |
| `FAILURE` | Red (`COLOR_RED`) |
| `NOT_BUILT` | Red (`COLOR_RED`) |
| `UNSTABLE` | Yellow (`COLOR_YELLOW`) |
| `ABORTED` | Dim (`COLOR_DIM`) |
| `IN_PROGRESS` | Blue (`COLOR_BLUE`) |
| Other/unknown | Red (`COLOR_RED`) |

The color wraps only the result field, not the rest of the line:

```text
<color><padded_result><reset> Job <job_name> #<build_number> ...
```

### 3. TTY-Aware Color Suppression

Colors are already initialized by `_init_colors()` in `jenkins-common.sh`, which sets all `COLOR_*` variables to empty strings when stdout is not a TTY, `NO_COLOR` is set, or the terminal supports fewer than 8 colors.

No additional TTY detection is needed — the existing `_init_colors()` mechanism handles this automatically. When colors are suppressed, only the padded plain-text result field is printed.

### 4. Scope

This change applies only to `_status_line_for_build_json()`. It affects all line mode outputs:
- `buildgit status --line`
- `buildgit status --line=N`
- `buildgit status -l`
- TTY-auto-detected line mode (non-TTY default)

Full status mode (`--all`), JSON mode, and follow mode are **not affected**.

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Update `_status_line_for_build_json()` to format the result field with `printf "%-11.11s"` and wrap it with the appropriate `COLOR_*` / `COLOR_RESET` pair |
| `test/buildgit_status.bats` | Add/update tests for padded alignment and color output (when applicable) |

## Acceptance Criteria

1. The result field in line mode output is always exactly 11 characters wide (padded or truncated).
2. All lines in `--line=N` output are column-aligned after the result field.
3. The result field is colored according to the color mapping table when stdout is a TTY.
4. Colors are not present when stdout is not a TTY (existing `_init_colors` behavior).
5. `IN_PROGRESS` fits within the 11-character field without truncation.
6. Single-line mode (`--line` / `-l`) also uses the padded, colored format.
7. Full status mode, JSON mode, and follow mode output are unchanged.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `status_line_aligned_output` | `--line=N` output has fixed-width result fields — all "Job" tokens start at the same column |
| `status_line_result_padded` | A `SUCCESS` result is padded to 11 characters with trailing spaces |
| `status_line_in_progress_no_truncate` | `IN_PROGRESS` result is exactly 11 characters — no truncation |
| `status_line_no_color_in_pipe` | When stdout is not a TTY, output contains no ANSI escape sequences |
