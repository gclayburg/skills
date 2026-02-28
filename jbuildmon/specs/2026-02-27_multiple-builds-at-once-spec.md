# Feature: Progress Bar Flash Fix, Multiple Concurrent Builds, and Queue State Display

- **Date:** `2026-02-27T00:00:00-0700`
- **References:** `specs/done-reports/multiple-builds-at-once.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Overview

Three related improvements to the progress bar display and build-start waiting logic:

1. **Flash fix** — Eliminate the brief blank-line flash when the progress bar redraws on each poll cycle.
2. **Multiple concurrent builds** — When multiple builds are in progress simultaneously for the same job, show a progress bar line for each build.
3. **Queue state display** — When a build cannot start because of a concurrent-build restriction, detect and display the `QUEUED` state rather than silently waiting until timeout.

## Problem Statement

### 1. Progress Bar Flash

The progress bar clears (`\r\033[K`) and redraws the new line in two separate `printf` calls. The brief interval between clear and draw causes a visible black flash on each poll cycle.

### 2. Multiple Concurrent Builds Not Shown

`buildgit status -f` tracks exactly one build. If a second build starts concurrently for the same job, it is not reflected in the progress bar. The user sees only the primary build.

### 3. Queue Timeout Instead of Queue Status

When a job has "do not allow concurrent builds" enabled and a build is triggered while another is running, `buildgit build` and `buildgit push` time out after 120 seconds with an error:

```
[16:49:03] ℹ Waiting for Jenkins build ralph1 to start...
[16:51:06] ✗ Timeout: Build did not start within 120 seconds
[16:53:07] ✗ Timeout: No build started within 120 seconds
[16:53:07] ✗ Build did not start within timeout
Suggestion: Check Jenkins queue at http://...
```

Jenkins knows the build is queued and can provide ETA information (`why` field: "Build #218 is already in progress  ETA: 1m 34s"), but this information is not surfaced to the user.

---

## Specification

### 1. Progress Bar Flash Fix

**Root cause:** `_clear_follow_line_progress()` issues `printf '\r\033[K'` (clear), then `_display_follow_line_progress()` issues a separate `printf` for the new content. The OS may schedule a render between these two writes, producing a blank frame.

**Fix:** Combine clear and draw into a single atomic `printf` call. The clear escape sequence (`\r\033[K`) and the new line content are written together with no opportunity for a blank frame in between.

**Single-line (current case):**
```bash
printf '\r\033[K%s' "$line"
```

**Multi-line (when N > 1 progress bars are shown):**
All N lines are cleared and redrawn in a single `printf` call using cursor-up escape sequences:
```bash
# For N lines: move cursor up (N-1) lines, clear+draw each, no separate clear step
printf '\r\033[K%s\n\033[K%s' "$line1" "$line2"   # example for N=2
```

On the first draw (no existing bar to clear), write all lines with `\n` separators. On subsequent redraws, move the cursor up N lines and overwrite in place — all in one `printf`.

### 2. Multiple Concurrent Builds in Progress Bar

#### Detection

On each poll cycle (when already monitoring a build), query the Jenkins builds list for all currently-running builds:

```
GET /job/{name}/api/json?tree=builds[number,building,timestamp,result]{0,10}
```

Filter for entries with `building=true`. This returns all concurrently-running builds. If more than one is found, display a progress bar line for each.

#### Display Format

Each in-progress build gets its own line in the same format as the existing single-line bar:

```
IN_PROGRESS Job ralph1 #218 [=========>          ] 45% 2m 41s / ~6m 15s
IN_PROGRESS Job ralph1 #219 [=>                  ]  8% 30s / ~6m 15s
```

Rules:
- Lines are ordered by build number ascending (oldest build first, newest last).
- Each build uses the same estimate source (`_get_last_successful_build_duration()`).
- Each build's elapsed time is computed from its own `timestamp` field.
- The primary build (the one `status -f` originally started following) is always displayed first.
- When a secondary build completes, its line is removed and the remaining bar(s) redraw to fill the space.
- When all builds complete, the progress bar is cleared entirely and normal completion output follows for the primary build.

#### Multi-line Clear/Redraw

The clear+draw mechanism (Section 1) is extended to handle N lines atomically. Track `_PROGRESS_BAR_LINE_COUNT` (number of lines currently drawn) so the next redraw knows how many lines to clear upward.

#### Applicable Modes

Multiple-build detection applies to all monitoring contexts that show the progress bar:
- `buildgit status -f` (full and `--line` modes)
- `buildgit push` (full and `--line` modes)
- `buildgit build` (full and `--line` modes)

### 3. Queue State Detection and Display

#### Jenkins Queue API

When a build cannot start, it appears in the Jenkins queue at:

```
GET /queue/api/json
```

Each queue item has:
- `task.name`: job name
- `blocked` (boolean): true when blocked by a concurrency restriction
- `buildable` (boolean): true when ready to run but waiting for executor
- `stuck` (boolean): true when stuck too long
- `why` (string): human-readable reason, e.g., `"Build #218 is already in progress  ETA: 1m 34s"`
- `inQueueSince` (timestamp ms): when the item entered the queue
- `executable.number`: build number, populated once the build actually starts
- `id`: queue item ID
- `cancelled` (boolean): true if the item was cancelled

The queue item URL (returned as the `Location` header from `POST /job/{name}/build`) gives direct access:

```
GET /queue/item/{id}/api/json
```

#### Status Label: `QUEUED`

The status label for a queued build is `QUEUED`. This matches:
- Jenkins Blue Ocean REST API's `queued` build state
- The existing `QUEUED` state already defined in `skill/buildgit/SKILL.md`

No distinction between `blocked` and `buildable` sub-states is shown in the label — both display as `QUEUED`.

#### Timeout Behavior Change

Current behavior: 120s timeout regardless of queue state.

New behavior:
- **If a queue item is found** for the job (`task.name` matches, not cancelled): wait indefinitely — the build is confirmed pending in Jenkins. The 120s `BUILD_START_TIMEOUT` does not apply.
- **If no queue item is found** after `BUILD_START_TIMEOUT` seconds: emit the existing timeout error. This covers cases where the build was rejected outright, the job was disabled, or Jenkins lost the trigger.

The `wait_for_queue_item()` function (already implemented) handles polling the queue item URL when a `Location` header was returned. Its internal timeout should be removed (or set to a very large value) when a valid queue item is confirmed.

For `cmd_push()` (SCM-triggered, no `Location` header): detect the queue item via the global `/queue/api/json` by matching `task.name` to the job name, then switch to indefinite waiting once found.

#### Queue Status Output for `build` and `push` Commands

When a build is detected in the queue, replace the generic "Waiting for Jenkins build to start…" with informational output using `log_info`:

```
[16:49:03] ℹ Waiting for Jenkins build ralph1 to start...
[16:49:08] ℹ Build #219 is QUEUED — Build #218 is already in progress  ETA: 1m 34s
```

- The `why` field from the Jenkins queue item is shown verbatim after the `QUEUED —` prefix.
- This line is printed once when the queue state is first detected, and **updated** (overwritten in place on TTY, or re-printed on non-TTY) on each poll cycle while the build remains queued, so the ETA stays current.
- When the build finally starts, the queue line is cleared and monitoring proceeds normally.

#### Queue Progress Bar for `status -f`

When `status -f` detects a queued build (a build that is in the queue but not yet running), display it in the progress bar with an **indeterminate animation** (since the queue wait time is unknown):

```
IN_PROGRESS Job ralph1 #218 [=========>          ] 45% 2m 41s / ~6m 15s
QUEUED      Job ralph1 #219 [<===>               ] 34s in queue / ~6m 15s
```

Format for the queued-build line:
```
QUEUED      Job <job> #<num> [<indeterminate-bar>] <elapsed-queue-time> in queue / ~<build-estimate>
```

- `<elapsed-queue-time>`: time since `inQueueSince` (how long this build has been waiting).
- `<build-estimate>`: the standard estimate from `_get_last_successful_build_duration()` (how long the build will take once it starts), formatted with `~`.
- `<indeterminate-bar>`: same pulsing animation as the existing `~unknown` case (bouncing `<===>` pattern).

`QUEUED` is fixed-width padded to match `IN_PROGRESS` alignment (11 characters, using spaces): `QUEUED     ` → pad to same field width as `IN_PROGRESS`.

#### Detection of Queued Builds for `status -f`

On each poll cycle, in addition to checking for running builds, check the global queue for items matching the job name. A queue item that has not yet received a build number (`executable.number` is null/empty) is a queued-but-not-started build. Show it in the progress bar as `QUEUED`.

---

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Flash fix: merge clear+draw into single `printf`. Multi-line tracking variable. Multiple build detection in poll loop. Queue detection in `_wait_for_build_start()`. Queue progress bar line in `_display_follow_line_progress()`. |
| `skill/buildgit/scripts/lib/jenkins-common.sh` | `wait_for_queue_item()`: remove finite timeout when queue item is confirmed valid. Update to return queue item metadata (`why`, `inQueueSince`) for status display. |
| `test/buildgit_status.bats` or `test/buildgit_push.bats` | New unit tests per Test Strategy. |
| `skill/buildgit/SKILL.md` | Document `QUEUED` state in progress bar and queue display behavior. |

---

## Acceptance Criteria

1. No visible flash when progress bar updates on each poll cycle.
2. When two builds are in progress concurrently, two `IN_PROGRESS` lines appear in the progress bar.
3. When a second build completes, its line is removed and the remaining bar redraws cleanly.
4. `buildgit build` does not time out when a build is queued due to concurrency restriction — it waits indefinitely.
5. `buildgit push` does not time out when a build is queued — it waits indefinitely.
6. While waiting, a `[timestamp] ℹ Build #N is QUEUED — <why>` message is shown and kept current.
7. The 120s timeout still applies when no queue item is found (build never triggered).
8. `buildgit status -f` shows a `QUEUED` progress bar line for builds waiting in queue.
9. The `QUEUED` bar uses an indeterminate animation.
10. The `QUEUED` bar shows elapsed queue wait time (`Xs in queue`) and the build's estimated duration (`~Ym Zs`).
11. All multi-line progress bar updates (clear + draw) happen atomically in a single `printf` call.
12. Queue detection works for both `build` (has queue URL from `Location` header) and `push` (must detect via global queue API).

---

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `progress_bar_no_flash` | Clear and draw are issued in single write (mock TTY, verify single printf call) |
| `multi_build_two_bars` | Two in-progress builds produce two `IN_PROGRESS` lines in output |
| `multi_build_single_after_complete` | When second build completes, only one bar line remains |
| `multi_build_ordered_ascending` | Multiple bars ordered by build number ascending |
| `queue_build_no_timeout` | `build` command does not exit on timeout when queue item found |
| `queue_push_no_timeout` | `push` command does not exit on timeout when queue item found |
| `queue_why_displayed` | Queue `why` field shown in `QUEUED` status message |
| `queue_timeout_still_applies` | 120s timeout still fires when no queue item found |
| `queue_bar_indeterminate` | `QUEUED` bar uses indeterminate (pulsing) animation |
| `queue_bar_elapsed_queue_time` | `QUEUED` bar shows time since `inQueueSince` + `in queue` label |
| `queue_bar_build_estimate` | `QUEUED` bar shows build estimate from last successful build |
| `queue_transitions_to_in_progress` | Once queued build starts, its bar switches to `IN_PROGRESS` |
| `queue_status_f_detection` | `status -f` detects queue item via global `/queue/api/json` |
| `queue_label_alignment` | `QUEUED` label is padded to same field width as `IN_PROGRESS` |

---

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
