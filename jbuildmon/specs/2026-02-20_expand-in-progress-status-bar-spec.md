# Feature: Expand In-Progress Status Bar to All Build-Monitoring Commands

- **Date:** `2026-02-20T13:48:07-0700`
- **References:** `specs/todo/expand-in-progress-status-bar.md`
- **Supersedes:** (none — extends `2026-02-20_add-f-option-to-line-status-spec.md`)
- **State:** `DRAFT`

## Overview

Expand the animated in-progress progress bar (currently only shown during `status -f --line` on a TTY) to all build-monitoring commands: `push`, `build`, and `status -f` (regular follow mode). Additionally, add a `--line` flag to `push` and `build` to enable a compact output mode matching `status --line`.

When on a TTY, any command that monitors a build should show the progress bar as the last line of output. When not on a TTY, the progress bar is suppressed (existing behavior).

## Problem Statement

The in-progress progress bar with estimated completion time is currently limited to `status -f --line`. Users running `buildgit push` or `buildgit build` — the most common build-monitoring workflows — see stage-by-stage output but have no visual indication of overall progress or estimated time remaining. This feature brings the progress bar to all monitoring contexts.

## Specification

### 1. Add `--line` Flag to `push` and `build` Commands

Add a `--line` option to both `push` and `build` commands. When present:

- **During monitoring:** Show only the animated progress bar (same format as `status -f --line`) — no build banner, no stage tracking, no verbose output.
- **On completion:** Print a single `--line` format summary (e.g., `SUCCESS Job ralph1 #42 Tests=557/0/0 Took 4m 10s on 2026-02-20 (just now)`). No failure diagnostics or additional output — keep it compact.
- **Non-TTY:** No progress bar. Wait silently, then print the single `--line` summary on completion.

The `--line` flag is compatible with `--no-follow`:
- `push --line --no-follow`: Push only, no monitoring, no output change (same as `push --no-follow`).
- `build --line --no-follow`: Trigger only, no monitoring (same as `build --no-follow`).

Option parsing changes:
- `_parse_push_options()`: Add `--line` → sets `PUSH_LINE_MODE=true`.
- `_parse_build_options()`: Add `--line` → sets `BUILD_LINE_MODE=true`.

### 2. Progress Bar as Sticky Footer for `push`, `build`, and `status -f` (Full Output Mode)

When monitoring a build on a TTY **without** `--line`, the progress bar appears as a sticky footer — the last line of output that persists below all other monitoring output (build banner, stage changes, deferred header fields).

**Rendering rules:**

1. The progress bar is rendered after each poll cycle in `_monitor_build()`, as the final line of output.
2. When new content is printed above (stage change, deferred header field), the progress bar is first cleared (`\r\033[K`), the content is printed normally, and then the progress bar is re-rendered on the new last line.
3. The progress bar uses the same format as `status -f --line`:
   ```
   IN_PROGRESS Job ralph1 #42 [=====>          ] 35% 1m 24s / ~4m 10s
   ```
4. When the build completes, the progress bar is cleared and **not** replaced — the existing completion output (`_handle_build_completion`) follows.

**Conditions for showing the sticky footer progress bar:**
- stdout is a TTY (`_status_stdout_is_tty`)
- A build is currently in progress (`building == true`)
- `--line` is **not** active (line mode has its own output path)

### 3. Progress Bar in `status -f` (Regular Follow, Without `--line`)

Currently, `status -f` without `--line` uses `_monitor_build` for in-progress builds. With this change, `_monitor_build` gains the sticky footer progress bar (Section 2), so `status -f` automatically benefits.

No special handling needed — `status -f` already calls `_monitor_build`, which will now render the progress bar.

### 4. Estimate Source (Unchanged)

Same as `2026-02-20_add-f-option-to-line-status-spec.md`: the estimate comes from the last successful build's duration via `_get_last_successful_build_duration()`. This function is already implemented; reuse it in `_monitor_build`.

### 5. Non-TTY Behavior

When stdout is not a TTY:
- No progress bar is shown in any mode.
- `push --line` / `build --line`: Wait silently, print `--line` summary on completion.
- `push` / `build` / `status -f` (without `--line`): Existing behavior unchanged (full output without progress bar).

### 6. `push --line` Flow

```
$ buildgit push --line
Pushing to remote...
To github.com:user/repo.git
   abc1234..def5678  main -> main
IN_PROGRESS Job ralph1 #43 [=====>          ] 35% 1m 24s / ~4m 10s
```
↓ (build completes, progress bar cleared, replaced with:)
```
$ buildgit push --line
Pushing to remote...
To github.com:user/repo.git
   abc1234..def5678  main -> main
SUCCESS     Job ralph1 #43 Tests=557/0/0 Took 4m 10s on 2026-02-20 (just now)
```

Note: The git push output lines are always shown (they come from git itself). Only the monitoring portion changes.

### 7. `build --line` Flow

```
$ buildgit build --line
Triggering build for job 'ralph1'...
Build triggered successfully
IN_PROGRESS Job ralph1 #43 [=====>          ] 35% 1m 24s / ~4m 10s
```
↓ (build completes:)
```
$ buildgit build --line
Triggering build for job 'ralph1'...
Build triggered successfully
SUCCESS     Job ralph1 #43 Tests=557/0/0 Took 4m 10s on 2026-02-20 (just now)
```

### 8. `push` / `build` Full Output with Sticky Footer

```
$ buildgit push
Pushing to remote...
To github.com:user/repo.git
   abc1234..def5678  main -> main
Waiting for Jenkins build ralph1 to start...
Build #43 started
──────────────────────────────────────────
 Build     ralph1 #43
 Pipeline  Jenkinsfile
 Commit    def5678 Fix authentication bug
──────────────────────────────────────────
  ✓ Build        12s
  ✓ Test         2m 5s
  → Deploy       (running)
IN_PROGRESS Job ralph1 #43 [============>       ] 60% 2m 30s / ~4m 10s
```

The progress bar is cleared when the build completes, and normal completion output follows.

### 9. `status -f` Full Output with Sticky Footer

Same as Section 8 but without the git push preamble. The progress bar appears at the bottom of the monitoring output during `_monitor_build`.

### 10. Help Text Updates

Update `show_usage()`:

```text
Commands:
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests]
                      Display Jenkins build status (latest or specific build)
                      Default: full output on TTY, one-line on pipe/redirect
  push [--no-follow] [--line] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] [--line]
                      Trigger and monitor Jenkins build
```

Add examples:

```text
  buildgit push --line           # Push + compact one-line monitoring with progress bar
  buildgit build --line          # Trigger + compact one-line monitoring with progress bar
```

### 11. Option Compatibility

| Command | `--line` | `--no-follow` | `--line --no-follow` |
|---------|----------|---------------|----------------------|
| `push`  | Compact monitoring + progress bar | No monitoring | No monitoring (same as `--no-follow` alone) |
| `build` | Compact monitoring + progress bar | No monitoring | No monitoring (same as `--no-follow` alone) |

### 12. Exit Codes

Exit codes follow existing conventions and are unchanged by this feature:
- `push`: 0 on SUCCESS, 1 on non-SUCCESS or monitoring failure
- `build`: 0 on SUCCESS, 1 on non-SUCCESS or monitoring failure
- `status -f`: existing behavior unchanged

### 13. Implementation Approach

The core change is in `_monitor_build()` — add progress bar rendering to the existing poll loop:

1. **`_monitor_build()` changes:**
   - Accept a new parameter or check a global flag for TTY + progress bar display.
   - On each poll cycle, after stage tracking, if TTY and building: clear and re-render the progress bar.
   - Before printing any other output (stage changes, deferred headers), clear the progress bar first.
   - On build completion, clear the progress bar.

2. **`cmd_push()` changes:**
   - Add `--line` to `_parse_push_options()`.
   - When `PUSH_LINE_MODE=true`: skip `_display_build_in_progress_banner`, skip `_monitor_build`'s normal output, use line-mode monitoring (progress bar only), print `--line` summary on completion.

3. **`cmd_build()` changes:**
   - Add `--line` to `_parse_build_options()`.
   - Same line-mode flow as `cmd_push`.

4. **Shared line-mode monitoring function:**
   - Extract a `_monitor_build_line_mode()` or reuse the existing `status -f --line` polling loop from `_cmd_status_follow()` for the `push --line` and `build --line` paths.

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Add `--line` to push/build option parsers. Add progress bar rendering to `_monitor_build()` for sticky footer. Add line-mode monitoring path to `cmd_push()`/`cmd_build()`. Update `show_usage()`. |
| `test/buildgit_status.bats` | Add tests per Test Strategy below. |
| `skill/buildgit/SKILL.md` | Document `push --line` and `build --line` options. |

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)

## Acceptance Criteria

1. `buildgit push --line` shows the progress bar during monitoring and a single `--line` summary on completion.
2. `buildgit build --line` shows the progress bar during monitoring and a single `--line` summary on completion.
3. `buildgit push` (full output, TTY) shows the progress bar as a sticky footer below stage tracking.
4. `buildgit build` (full output, TTY) shows the progress bar as a sticky footer below stage tracking.
5. `buildgit status -f` (full output, TTY) shows the progress bar as a sticky footer below stage tracking.
6. The progress bar format is identical to `status -f --line`: `IN_PROGRESS Job <name> #<num> [<bar>] <pct>% <elapsed> / ~<estimate>`.
7. The progress bar estimate is based on the last successful build's duration (reuses `_get_last_successful_build_duration`).
8. When no prior successful build exists, the bar shows `~unknown` with indeterminate animation.
9. On non-TTY, no progress bar is shown in any mode.
10. `push --line` on non-TTY waits silently and prints `--line` summary on completion.
11. `build --line` on non-TTY waits silently and prints `--line` summary on completion.
12. `push --line --no-follow` behaves the same as `push --no-follow` (no monitoring).
13. `build --line --no-follow` behaves the same as `build --no-follow` (no monitoring).
14. The sticky footer progress bar is cleared before any other output (stage changes, deferred headers) is printed.
15. The sticky footer progress bar is cleared when the build completes (not left on screen).
16. Help text is updated with `--line` option for `push` and `build` commands.
17. Exit codes are unchanged.
18. All `specs/CLAUDE.md` rules are followed for implementing this DRAFT spec.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `push_line_option_accepted` | `push --line` is accepted without error (mock git push + Jenkins) |
| `build_line_option_accepted` | `build --line` is accepted without error (mock trigger + Jenkins) |
| `push_line_completed_output` | After build completes, `push --line` output ends with standard `--line` format |
| `build_line_completed_output` | After build completes, `build --line` output ends with standard `--line` format |
| `push_line_no_banner` | `push --line` does not show the build banner (no `──────` separator lines) |
| `build_line_no_banner` | `build --line` does not show the build banner |
| `push_line_no_follow_unchanged` | `push --line --no-follow` behaves identically to `push --no-follow` |
| `build_line_no_follow_unchanged` | `build --line --no-follow` behaves identically to `build --no-follow` |
| `push_line_non_tty` | `push --line` on non-TTY: no progress bar, only `--line` summary on completion |
| `build_line_non_tty` | `build --line` on non-TTY: no progress bar, only `--line` summary on completion |
| `push_line_progress_bar_format` | `push --line` on TTY shows progress bar matching expected format (TTY mock) |
| `build_line_progress_bar_format` | `build --line` on TTY shows progress bar matching expected format (TTY mock) |
| `monitor_build_sticky_footer_tty` | `_monitor_build` on TTY renders progress bar as last line of output |
| `monitor_build_no_footer_non_tty` | `_monitor_build` on non-TTY does not render progress bar |
| `push_line_exit_code_success` | `push --line` returns 0 when build succeeds |
| `push_line_exit_code_failure` | `push --line` returns 1 when build fails |
