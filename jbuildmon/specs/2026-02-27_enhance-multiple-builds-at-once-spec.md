# Enhancement: Queue Output Noise, QUEUED Build Display for All Commands, Flash Follow-up

- **Date:** `2026-02-27T00:00:00-0700`
- **References:** `specs/done-reports/enhance-multiple-builds-at-once.md`
- **Supersedes:** `2026-02-27_multiple-builds-at-once-spec.md` (sections: Queue Status Output for build/push, Applicable Modes for QUEUED builds)
- **State:** `IMPLEMENTED`

## Overview

Three refinements to the behavior specified in `2026-02-27_multiple-builds-at-once-spec.md`, observed after implementation:

1. **Queue output noise** — The queue wait phase prints a new `log_info` line on every poll cycle (every ~2 seconds), producing excessive output. Replace with a sticky progress bar line on TTY; throttle to every 30 seconds on non-TTY.
2. **All monitoring commands show QUEUED builds** — `buildgit push` and `buildgit build` only show the build they triggered. Any QUEUED build that appears after the primary build starts should also be shown in the multi-line progress bar, consistent with `status -f`.
3. **Flash follow-up** — The progress bar still flashes noticeably. Additional investigation and fixes may be needed beyond the single-`printf` approach in the previous spec.

---

## Problem 1: Queue Output Noise

### Observed (incorrect) behavior

```
$ buildgit --job ralph1 build
[18:12:51] ℹ Waiting for Jenkins build ralph1 to start...
[18:12:52] ℹ Build #226 is QUEUED — In the quiet period. Expires in 4.9 sec
[18:12:54] ℹ Build #226 is QUEUED — In the quiet period. Expires in 2.9 sec
[18:12:56] ℹ Build #226 is QUEUED — In the quiet period. Expires in 0.87 sec
[18:12:58] ℹ Build #226 is QUEUED — Finished waiting
[18:13:00] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 59 sec)
[18:13:02] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 57 sec)
... (one new line every 2 seconds)
```

A build that is queued for 5 minutes would emit ~150 lines of output.

### Specification: TTY Behavior

On a TTY, the queue wait phase uses a two-part output approach:

**Permanent log lines (printed once and scroll up):** A `log_info` line is printed when:
- The QUEUED state is first detected: `[HH:MM:SS] ℹ Build #226 is QUEUED`
- A **state transition** is detected (the `why` message changes to a meaningfully different phase — see State Transition Detection below): `[HH:MM:SS] ℹ Build #226 is QUEUED — Finished waiting`

**Sticky progress bar line (updated in-place on TTY):** Below the permanent log lines, one or two lines are updated in-place each poll cycle:

Phase 1 — quiet period (only the triggered build is queued, no other running build):
```
[18:12:52] ℹ Build #226 is QUEUED
Build #226 is QUEUED — In the quiet period. Expires in 0.87 sec
```
The bottom line is rewritten on each poll cycle using `\r`.

Phase 2 — blocked by running build (after quiet period, waiting for #225 to finish):
```
[18:12:52] ℹ Build #226 is QUEUED
[18:12:58] ℹ Build #226 is QUEUED — Finished waiting
Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 59 sec)
IN_PROGRESS Job ralph1 #225 [===========>        ] 64% 3m 44s / ~5m 49s
```
The bottom two lines are rewritten each poll cycle (multi-line atomic redraw per the previous spec). The log_info lines above are permanent.

When the queued build finally starts:
- The sticky lines are cleared.
- Normal monitoring output begins.

**The sticky bottom lines use the same multi-line atomic `printf` mechanism** specified in `2026-02-27_multiple-builds-at-once-spec.md` (no separate clear step).

**Plain-text format for the QUEUED sticky line:**

```
Build #<num> is QUEUED — <why-field-verbatim>
```

No progress bar brackets or percentage — this is a plain text line, not a `log_info` line (no timestamp prefix). It sits directly above the `IN_PROGRESS` bar line when the running build is also shown.

### State Transition Detection

The `why` field text falls into recognizable phases. A state transition is when the phase changes, not when a countdown value changes within the same phase.

Detection heuristic: compare the **leading text before the first digit** of the current and previous `why` values. If it differs, it is a state transition. Examples:
- `"In the quiet period. Expires in 4.9 sec"` → `"In the quiet period. Expires in 2.9 sec"`: same prefix `"In the quiet period. Expires in "` → **not a transition**
- `"In the quiet period. Expires in 0.87 sec"` → `"Finished waiting"`: prefix changed → **transition** → print new `log_info`
- `"Finished waiting"` → `"Build #225 is already in progress (ETA: 4 min 59 sec)"`: prefix changed → **transition** → print new `log_info`
- `"Build #225 is already in progress (ETA: 4 min 59 sec)"` → `"Build #225 is already in progress (ETA: 4 min 57 sec)"`: same prefix `"Build #225 is already in progress (ETA: "` → **not a transition**

### Specification: Non-TTY Behavior

On non-TTY, no sticky line is possible. Print a `log_info` line:
- When QUEUED first detected.
- On each state transition (same rules as TTY).
- Every **30 seconds** if no state transition has occurred (throttled update).
- When the build starts (clear queue state, normal monitoring begins).

```
[18:12:51] ℹ Waiting for Jenkins build ralph1 to start...
[18:12:52] ℹ Build #226 is QUEUED — In the quiet period. Expires in 4.9 sec
[18:12:56] ℹ Build #226 is QUEUED — In the quiet period. Expires in 0.87 sec
[18:12:58] ℹ Build #226 is QUEUED — Finished waiting
[18:13:00] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 59 sec)
[18:13:30] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 29 sec)
[18:14:00] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 3 min 59 sec)
```

The 30-second throttle applies only within the same phase. State transitions always print immediately.

---

## Problem 2: All Monitoring Commands Show QUEUED Builds

### Observed (incorrect) behavior

`buildgit push` monitors only the primary build. If a second build becomes QUEUED while the primary build is running, the `push` progress bar does not show it. Only `buildgit status -f` shows the QUEUED secondary build.

### Specification

**All monitoring commands** — `push`, `build`, and `status -f` — show new QUEUED builds that appear in the Jenkins queue for the same job while monitoring is active. This extends the multi-line progress bar from the previous spec to cover `push` and `build` as well.

On each poll cycle during active monitoring (primary build is running), check the Jenkins global queue for new items matching the job name. If found, add a `QUEUED` line to the progress bar:

```
IN_PROGRESS Job ralph1 #225 [===========>        ] 64% 3m 44s / ~5m 49s
QUEUED      Job ralph1 #226 [<===>               ] 34s in queue / ~5m 49s
```

This is identical in format and behavior to the `status -f` case specified in `2026-02-27_multiple-builds-at-once-spec.md`. The only change is that `push` and `build` now also perform this check.

**Important:** This is a different situation from Problem 1. Problem 1 covers the case where `push`/`build` is still *waiting for its own triggered build to start* (the triggered build is queued). Problem 2 covers the case where the *primary build is already running* and a *new, separate build* appears in the queue. They use the same QUEUED line format in the progress bar but are triggered by different conditions:

| Situation | Primary build state | What appears in queue |
|-----------|--------------------|-----------------------|
| Problem 1 | Not started yet (waiting) | The triggered build itself |
| Problem 2 | Running | A new, different build |

---

## Problem 3: Flash Follow-up

### Observed

The progress bar still flashes noticeably on `buildgit status -f` despite the `2026-02-27_multiple-builds-at-once-spec.md` fix. This suggests either:
- The single-`printf` fix was not fully applied to all code paths.
- The multi-line case introduces additional flash from cursor movement.
- Terminal buffering is causing partial renders despite the atomic write.

### Specification

Investigate and eliminate remaining flash. Specific areas to check:

1. **API calls between clear and draw** — The most likely source of flash: if the poll loop clears the progress bar, then makes Jenkins API calls, then redraws, the terminal shows a blank line for the full duration of the API round-trip (potentially 100–500ms). This would cause a visible flash even if the clear and draw are individually atomic. **The fix**: always complete all API calls *before* touching the progress bar. The correct order within each poll cycle is:
   1. Fetch all API data (build status, queue state, stage info)
   2. Compute new progress bar content from the fetched data
   3. Clear + draw in a single atomic `printf` (no API calls in between)

   Verify that no API call (`jenkins_api`, `get_build_info`, `get_console_output`, etc.) is issued between the clear and draw operations in any code path.

2. **Verify the single-`printf` fix is applied to all progress bar code paths** — including `_display_follow_line_progress()`, the sticky footer in `_monitor_build()`, and the new queue phase sticky lines from Problem 1. Any place that does a separate clear-then-draw is a flash source.

3. **Multi-line cursor movement** — When moving the cursor up N lines and redrawing, verify that the entire sequence (cursor-up + clear + content for each line) is issued in one `printf` call with no intermediate flushes.

4. **Consider `tput` alternatives** — If `printf '\r\033[K...'` still causes flash (due to terminal processing), consider writing to a temporary buffer and issuing a single `write()` syscall, or using `tput sc`/`tput rc` (save/restore cursor) which some terminals handle more atomically.

5. **Terminal line-discipline buffering** — Ensure stdout is not line-buffered when writing progress bar updates (it should not be by default for TTY output in bash, but verify).

Document the root cause found and the fix applied in the implementation notes section of the spec when marking it IMPLEMENTED.

---

## Relationship to Previous Spec

This spec **refines** the following sections of `2026-02-27_multiple-builds-at-once-spec.md`:

| Previous spec section | Change |
|-----------------------|--------|
| §3 Queue Status Output for build/push | Superseded: replace per-poll log_info with sticky line (TTY) / 30s throttle (non-TTY) |
| §2 Applicable Modes | Extended: push and build now also show QUEUED secondary builds |
| §1 Flash Fix | Follow-up investigation required |

All other sections of the previous spec remain in force.

---

## Acceptance Criteria

1. On TTY, `buildgit build` waiting for a queued build prints at most one `log_info` per state transition, not one per poll cycle.
2. On TTY, the current queue `why` text is shown as a sticky line that updates in-place each poll cycle.
3. On TTY, when a queued build is blocked by a running build, both a queue sticky line and a running build `IN_PROGRESS` bar appear together, updated atomically.
4. On non-TTY, queue status is printed at most every 30 seconds (plus on state transitions).
5. State transitions (phase changes in `why` text) always print a `log_info` line immediately, on both TTY and non-TTY.
6. `buildgit push` and `buildgit build` show a `QUEUED` line in the multi-line progress bar when a new build appears in the queue while the primary build is running.
7. The `QUEUED` secondary-build line for `push`/`build` matches the format used by `status -f`.
8. No additional `log_info` lines are printed for queue state while `push`/`build` is in active monitoring mode (only the sticky progress bar updates).
9. Progress bar flash is visibly eliminated or substantially reduced.
10. `buildgit push` behavior during Problem 1 (waiting for its own queued build) and Problem 2 (primary running, secondary queued) are correctly distinguished and independently handled.

---

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `queue_tty_single_loginfo_on_detect` | First QUEUED detection prints exactly one `log_info` line |
| `queue_tty_no_loginfo_on_countdown` | Countdown-only `why` changes do not print new `log_info` |
| `queue_tty_loginfo_on_state_transition` | Phase change in `why` prints new `log_info` |
| `queue_tty_sticky_line_updated` | Sticky QUEUED line is rewritten in place (no newline appended) |
| `queue_tty_running_build_bar_shown` | When queued build is blocked by running build, IN_PROGRESS bar appears in sticky area |
| `queue_non_tty_30s_throttle` | On non-TTY, log_info not printed more often than every 30s within same phase |
| `queue_non_tty_transition_immediate` | On non-TTY, state transitions print immediately regardless of throttle |
| `push_shows_queued_secondary` | `push` monitoring primary build shows QUEUED secondary build in progress bar |
| `build_shows_queued_secondary` | `build` monitoring primary build shows QUEUED secondary build in progress bar |
| `push_queued_secondary_format` | `push` QUEUED secondary line matches `status -f` QUEUED line format |
| `queue_wait_vs_secondary_independent` | Problem 1 (waiting for own build) and Problem 2 (secondary queued) handled independently |
| `flash_no_api_call_between_clear_draw` | No Jenkins API call is issued between the clear and draw operations in the poll cycle |
| `flash_single_printf_all_paths` | All progress bar rendering uses single `printf` (no separate clear step) |

---

## Implementation Notes

- Root cause of queue noise was per-poll `log_info` writes in queue wait code paths; fix was transition-aware phase detection (`why` prefix before first digit), sticky TTY queue redraw lines, and 30-second non-TTY throttling
- Root cause of missing queued secondary lines in `push`/`build` was that those monitor calls explicitly disabled queue-line rendering (`include_queue_lines=false`); fix was enabling queue-line rendering for both full and line monitoring paths
- Root cause of remaining flash in full monitor mode was clear-before-output sequencing around deferred header/stage updates; fix was collecting deferred/stage output first, then clearing and redrawing so API work no longer occurs between clear and draw in the render path

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
