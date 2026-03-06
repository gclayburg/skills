## Add `--threads` flag for live active-stage progress display during monitoring

- **Date:** `2026-03-05T09:12:00-0700`
- **References:** `specs/done-reports/threads-display-tty.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Background

During real-time monitoring (`buildgit push`, `buildgit build`, `buildgit status -f`), the TTY progress bar area shows only the overall build progress. There is no visibility into which individual pipeline stages are currently running, which agent is executing them, or how far along each stage is.

Users want to see live per-stage progress in the TTY status area so they can tell at a glance:
- Which stages are actively running right now
- Which agent is running each stage
- How far along each individual stage is relative to its expected duration

This is especially valuable for parallel builds where multiple agents run stages concurrently — each agent should get its own progress line.

## Specification

### 1. New `--threads` flag

Add a `--threads` global option to `buildgit`:

```
--threads    Show live active-stage progress lines during TTY monitoring
```

- Applicable to monitoring commands: `push`, `build`, `status -f`, `status -f --once`
- Requires TTY (stdout must be a terminal). If not a TTY, `--threads` is silently ignored.
- Can be combined with `--line` mode or full output mode.
- Has no effect on snapshot commands (`status`, `status --all`, `status --json`).

### 2. Active-stage progress lines

When `--threads` is active and a build is in progress, render one line per currently-running stage **above** the existing overall build progress bar. The overall build progress bar remains as the bottom line, unchanged.

**Per-stage line format:**
```
  [<agent-name>] <stage-name> [========>          ] <pct>% <elapsed> / ~<estimate>
```

**Layout example — sequential pipeline:**
```
  [agent6 guthrie] Build [===================>] 99% 3s / ~4s
IN_PROGRESS    Job ralph1 #42 [=>                   ] 8% 12s / ~2m 39s
```

**Layout example — parallel stages (4 agents):**
```
  [agent6 guthrie] Unit Tests A [========>          ] 65% 1m 30s / ~2m 18s
  [agent7 guthrie] Unit Tests B [=====>             ] 42% 38s / ~1m 29s
  [agent8 guthrie] Unit Tests C [==>                ] 18% 22s / ~2m 6s
  [agent9 guthrie] Unit Tests D [===>               ] 24% 36s / ~2m 25s
IN_PROGRESS    Job ralph1 #42 [=========>           ] 45% 3m 12s / ~7m 15s
```

**Formatting rules:**
- Agent name uses the same `[<agent-name>]` format as `print_stage_line()` (14-char padded field).
- Stage name matches the name shown in stage output lines (same naming scheme as existing stage log lines).
- Progress bar reuses the existing `_render_follow_line_progress_bar_determinate()` and `_render_follow_line_progress_bar_unknown()` functions.
- Each active-stage line is indented with 2 leading spaces to visually distinguish it from the overall build progress line.
- Lines are ordered by the stage's position in the pipeline (same order as `wfapi/describe`), not by agent name.

### 3. Per-stage time estimates

Fetch per-stage duration estimates from the last successful build's `wfapi/describe` endpoint:

- On monitoring start, call `wfapi/describe` for the last successful build (same build used for the overall estimate) and cache all stage durations keyed by stage name.
- When rendering an active-stage line, look up the stage name in the cached durations. If found, use that as the estimate and render a **determinate** progress bar with percentage.
- If a stage name is not found in the cache (new stage, renamed stage, etc.), render an **indeterminate** (oscillating) progress bar with elapsed time only:
  ```
    [agent6 guthrie] New Stage [<====>              ] 12s / ~unknown
  ```
- The estimate cache is fetched once at monitoring start and not refreshed.

### 4. Stage lifecycle and transitions

**Appearance:** A stage line appears when the stage's status transitions to `IN_PROGRESS` in the `wfapi/describe` data.

**Disappearance:** A stage line is removed immediately when the stage reaches a terminal status (`SUCCESS`, `FAILED`, `UNSTABLE`, `ABORTED`, `NOT_BUILT`). On the next poll/redraw cycle, the line is gone and replaced by whatever stage starts next on that agent (if any).

**Transition behavior:** Immediate switch — no completion flash or delay. When a stage completes and the next sequential stage starts on the same agent in the same poll cycle, the line switches directly to the new stage.

**Empty state:** If no stages are currently `IN_PROGRESS` (e.g. between stages, or during queue wait), no active-stage lines are shown. Only the overall build progress bar renders.

### 5. Integration with existing multi-line redraw

The active-stage lines integrate into the existing `_redraw_follow_line_progress_lines()` mechanism:

- Active-stage lines are prepended to the lines array before the overall build progress line.
- The existing ANSI cursor movement logic handles the variable number of lines (stages start, stages complete, parallel count changes).
- When `_clear_follow_line_progress()` is called at build completion, all active-stage lines are cleared along with the overall progress bar.
- Other running/queued build rows (from the multi-build display feature) appear after the overall build progress line, unchanged.

**Line ordering in the progress area:**
1. Active-stage lines (one per running stage, ordered by pipeline position)
2. Primary build overall progress bar (existing)
3. Other running build rows (existing, if any)
4. Queued build rows (existing, if any)

### 6. Edge cases

- **Many parallel agents:** If more than the terminal height allows, render only the first N stages that fit (leave room for the overall progress bar and at least one line of scrollback). N = `terminal_rows - 3` (reserves space for overall bar + one prior output line + one buffer line). Use `tput lines` or `$LINES` to detect terminal height; default to 24 if unavailable.
- **Stage names longer than terminal width:** Truncate the stage name (not the progress bar or agent) to fit within terminal width. Use `tput cols` or `$COLUMNS`; default to 80.
- **`--line` mode combination:** `--threads` works with `--line` mode. The active-stage lines render above the one-line progress bar, same as full mode.
- **Non-TTY:** `--threads` is silently ignored. No error or warning.
- **No stages yet:** During the initial "QUEUED" phase before any stage starts, no active-stage lines are shown.

### 7. Help text update

Add to `buildgit --help` under Global Options:
```
  --threads                      Show live active-stage progress during TTY monitoring
```

## Test Strategy

### Unit tests

1. **Flag parsing:** Verify `--threads` is accepted as a global option and stored in a variable. Verify it does not affect snapshot commands.
2. **Per-stage estimate caching:** Mock `wfapi/describe` for a last-successful-build with known stage durations. Verify the cache is populated with correct stage name → duration mappings.
3. **Estimate fallback:** Mock a cache missing a stage name. Verify indeterminate bar is rendered for that stage.
4. **Active-stage line rendering:** Mock a single IN_PROGRESS stage with known elapsed time and estimate. Verify the rendered line matches the expected format (agent name, stage name, progress bar, percentage, times).
5. **Parallel stage rendering:** Mock 3 concurrent IN_PROGRESS stages. Verify 3 active-stage lines are rendered in pipeline order, each with the correct agent.
6. **Stage lifecycle:** Mock a sequence of polls where a stage transitions IN_PROGRESS → SUCCESS. Verify the stage line appears on the first poll and disappears on the poll after terminal status.
7. **Integration with redraw:** Mock the lines array passed to `_redraw_follow_line_progress_lines()`. Verify active-stage lines appear before the overall progress bar line.
8. **Non-TTY silently ignored:** Mock non-TTY stdout. Verify no active-stage lines are rendered even with `--threads` set.
9. **Terminal overflow:** Mock `LINES=10` with 12 concurrent stages. Verify only 7 stage lines render (10 - 3 reserved).

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
