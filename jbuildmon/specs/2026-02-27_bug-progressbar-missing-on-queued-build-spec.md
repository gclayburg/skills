# Bug: Progress Bar Missing on Queued Build (TTY check broken inside command substitution)

- **Date:** `2026-02-27T22:00:00-0700`
- **References:** `specs/done-reports/enhance-multiple-builds-at-once.md`, `specs/done-reports/bug-progressbar-missing-on-queued-build.md`
- **Supersedes:** none (bug fix only; existing specs remain correct as-is)
- **State:** `IMPLEMENTED`

## Observed Behavior

When `buildgit build` or `buildgit push` triggers a build that enters the Jenkins queue, the output on a TTY looks like this:

```
$ buildgit --job ralph1 build
[19:40:41] ℹ Waiting for Jenkins build ralph1 to start...
[19:40:41] ℹ Build #232 is QUEUED — In the quiet period. Expires in 4.9 sec
[19:40:47] ℹ Build #232 is QUEUED — Finished waiting
[19:40:52] ℹ Build #232 is QUEUED — Build #231 is already in progress (ETA: 2 min 28 sec)
```

This is the **non-TTY** output path (plain `log_info` lines to stderr). On a real TTY, the spec (`2026-02-27_enhance-multiple-builds-at-once-spec.md`) requires:
- A sticky progress bar line updated in-place each poll cycle
- An `IN_PROGRESS` bar for the blocking build when one is detected
- Only permanent `log_info` lines on state transitions

None of the sticky/animated behavior appears.

## Expected Behavior

On a TTY, the output should match the spec:

```
[18:12:52] ℹ Build #226 is QUEUED
[18:12:58] ℹ Build #226 is QUEUED — Finished waiting
Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 59 sec)
IN_PROGRESS Job ralph1 #225 [===========>        ] 64% 3m 44s / ~5m 49s
```

Where the last two lines are sticky (rewritten in-place each poll cycle).

## Root Cause Analysis

### The bug: `_status_stdout_is_tty()` always returns false inside `_wait_for_build_start()`

`_status_stdout_is_tty()` (line 724) checks `[[ -t 1 ]]` — whether **stdout** (fd 1) is a terminal.

Both callers of `_wait_for_build_start()` invoke it inside a **command substitution** `$()`:

```bash
# cmd_push(), line 2803:
new_build_number=$(_wait_for_build_start "$job_name" "$baseline_build" "")

# cmd_build(), line 2956:
build_number=$(_wait_for_build_start "$job_name" "$baseline_build" "$queue_url")
```

Command substitution runs the function in a **subshell with stdout connected to a pipe** (so the shell can capture the output into the variable). Inside this subshell, `[[ -t 1 ]]` always returns **false**, regardless of whether the parent shell's stdout is a real TTY.

The function communicates its result (the build number) via `echo "$current"` on stdout (line 2565), which is why stdout must be captured. All UI output (log_info, sticky lines) correctly goes to stderr — the problem is only with the TTY **detection**, not the output destination.

### Impact

Two TTY checks inside `_wait_for_build_start()` are broken:

1. **Line 2554** — `queue_estimate_ms` is never fetched on "TTY" because the check fails. The queue wait display always omits the estimated build time.
2. **Line 2610** — The sticky queue-wait display (`_redraw_queue_wait_sticky_lines`) never runs. The code always falls into the non-TTY `log_info` branch.

### Full audit of `_status_stdout_is_tty()` call sites

| Line | Containing Function | Called inside `$()`? | Verdict |
|------|---------------------|---------------------|---------|
| 1052 | `_monitor_build_line_mode` | No (direct call) | **SAFE** |
| 1532 | `_monitor_build` | No (direct call) | **SAFE** |
| 2554 | `_wait_for_build_start` | Yes (via callers at 2803, 2956) | **BUG** |
| 2610 | `_wait_for_build_start` | Yes (via callers at 2803, 2956) | **BUG** |

Other inline `[[ -t 1 ]]` checks (line 2334 in `cmd_status`, line 31 in `jenkins-common.sh`) are safe — they are called directly, not inside `$()`.

## Specification

### Fix: Return build number via global variable instead of stdout

Change `_wait_for_build_start()` to return the build number through a **global variable** (`_WAIT_FOR_BUILD_RESULT`) instead of echoing it on stdout. This allows the function to be called directly (not inside `$()`), preserving the real TTY on fd 1.

Note: `local -n` (nameref) was initially considered but rejected because macOS ships bash 3.2 which does not support namerefs (`local -n` requires bash 4.3+). A global variable is portable across all bash versions.

#### Current pattern (broken):
```bash
_wait_for_build_start() {
    ...
    echo "$current"   # returns build number on stdout
    return 0
}

# Caller:
build_number=$(_wait_for_build_start "$job_name" "$baseline_build" "$queue_url")
```

#### New pattern (fixed):
```bash
_WAIT_FOR_BUILD_RESULT=""

_wait_for_build_start() {
    local job_name="$1"
    local baseline="$2"
    local queue_url="${3:-}"
    _WAIT_FOR_BUILD_RESULT=""
    ...
    _WAIT_FOR_BUILD_RESULT="$current"   # return via global, not echo
    return 0
}

# Caller:
if ! _wait_for_build_start "$job_name" "$baseline_build" "$queue_url"; then
    ...error handling...
fi
local build_number="$_WAIT_FOR_BUILD_RESULT"
```

### Changes required

1. **`_wait_for_build_start()`** (line 2538): Add global `_WAIT_FOR_BUILD_RESULT=""` before the function. Replace all `echo "$build_number"` lines with `_WAIT_FOR_BUILD_RESULT=` assignment. Remove the `echo` calls.

2. **`cmd_push()` caller** (line 2803): Call directly (no `$()`), read `_WAIT_FOR_BUILD_RESULT` after success.

3. **`cmd_build()` caller** (line 2956): Same transformation.

4. **No other changes needed.** The `_status_stdout_is_tty()` function itself is correct. The monitoring functions (`_monitor_build`, `_monitor_build_line_mode`) are already called directly and are unaffected.

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `queue_wait_global_var_returns_build_number` | `_wait_for_build_start` returns build number via `_WAIT_FOR_BUILD_RESULT` global variable, not stdout |
| `queue_wait_tty_sticky_lines_shown` | On TTY (`BUILDGIT_FORCE_TTY=1`), `_wait_for_build_start` outputs sticky progress bar lines to stderr (contains `\r` or cursor-up escape sequences) and shows `IN_PROGRESS` bar for blocking build |
| `queue_wait_tty_estimate_fetched` | On TTY, `_wait_for_build_start` fetches `queue_estimate_ms` from `_get_last_successful_build_duration` |

### Regression coverage

Existing tests in `buildgit_build.bats` and `buildgit_push.bats` that test queue wait behavior were updated to use the new global variable pattern and continue to pass.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
