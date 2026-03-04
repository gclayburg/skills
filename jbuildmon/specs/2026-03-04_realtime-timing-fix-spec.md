## Fix monitoring mode stage timing and ordering for parallel branches

- **Date:** `2026-03-04T15:57:39-0700`
- **References:** `specs/done-reports/realtime-timing-fix.md`
- **Supersedes:** none
- **State:** `DRAFT`

## Background

When using monitoring mode (`buildgit build`, `buildgit push`, `buildgit status -f`), parallel pipeline stages display with incorrect timing, wrong ordering, and missing stages compared to the correct output from snapshot mode (`buildgit status --all`).

### Monitoring mode output (WRONG):
```
Stage: [agent6 guthrie] Build (4s)
Stage:   ║1 [agent6 guthrie] Unit Tests A (<1s)      ← should be 2m 18s
Stage:   ║2 [agent7 guthrie] Unit Tests B (1m 29s)
Stage: Unit Tests (1m 30s)                             ← printed too early, before C and D
Stage:   ║3 [agent7 guthrie] Unit Tests C (2m 6s)     ← printed AFTER wrapper
Stage:   ║4 [agent6 guthrie] Unit Tests D (2m 25s)    ← printed AFTER wrapper
                                                        ← Deploy stage missing entirely
```

### Snapshot mode output (CORRECT):
```
Stage: [agent6 guthrie] Build (4s)
Stage:   ║1 [agent6 guthrie] Unit Tests A (2m 18s)
Stage:   ║2 [agent7 guthrie] Unit Tests B (1m 29s)
Stage:   ║3 [agent7 guthrie] Unit Tests C (2m 6s)
Stage:   ║4 [agent6 guthrie] Unit Tests D (2m 25s)
Stage: Unit Tests (2m 25s)
Stage: [agent7 guthrie] Deploy (3s)
```

## Root Cause Analysis

There are four distinct but related problems, all in the monitoring code path.

### Bug 1: Parallel branch stages print with wrong duration

**Location:** `_track_nested_stage_changes()` in `jenkins-common.sh` (~line 2403)

When a parallel branch stage (e.g. "Unit Tests A") first transitions to a terminal status (SUCCESS), `_track_nested_stage_changes` prints it immediately with whatever `durationMillis` the Jenkins API reported at that poll. During a live build, Jenkins often reports a near-zero `durationMillis` for a parallel branch coordinator entry in `wfapi/describe` before the actual execution time is finalized. Snapshot mode works correctly because by the time it runs on a completed build, the API has the final duration.

The existing deferral logic (`is_pw` check) only applies to **wrapper** stages, not to individual parallel **branch** stages. There is no mechanism to defer printing a branch stage until its duration is finalized.

### Bug 2: Wrapper stage prints before all branches finish

**Location:** `_get_nested_stages()` parallel detection + `_track_nested_stage_changes()` wrapper deferral check

The wrapper deferral asks "are all parallel branches terminal?" by looking up branches listed in `parallel_branches`. This list is built by `_detect_parallel_branches()` from console output parsing. During a live build, the console output is **incomplete** — if only "Unit Tests A" and "Unit Tests B" have appeared in the console `[Pipeline] { (Branch: ...)` markers at that poll, then `parallel_branches` is `["Unit Tests A", "Unit Tests B"]`. When both are terminal, `pw_all_terminal=true` and the wrapper prints — even though C and D haven't been seen yet.

### Bug 3: Late-arriving branches print after the wrapper

**Consequence of Bug 2.** After the wrapper is printed and marked `terminal: true` in `printed_state`, subsequent polls discover "Unit Tests C" and "Unit Tests D" as new stages. They get printed in natural order — which is now chronologically after the wrapper line.

### Bug 4: Deploy stage missing from monitoring output

The "Deploy" stage runs after the parallel block finishes. If the build completes very quickly after Deploy starts, the main monitoring loop sees `building=false` and enters the settle loop. The settle loop runs `_track_nested_stage_changes` but either:
- Deploy hasn't appeared in `wfapi/describe` yet at the first settle iteration
- The settle loop reaches stable state (3 identical polls) before Deploy's terminal status appears
- The settle loop exits and returns before Deploy can be printed

## Specification

### 1. Defer parallel branch stage printing until duration is finalized

In `_track_nested_stage_changes`, add deferral logic for parallel **branch** stages (not just wrapper stages):

- When a parallel branch stage transitions to terminal status, check if its `durationMillis` is suspiciously low (less than 1000ms) AND the build is still in progress.
- If so, defer printing until the next poll when the duration may be updated.
- If after 2 consecutive polls the duration remains the same (i.e. Jenkins has finalized it), print it regardless — some stages genuinely take `<1s`.
- Alternatively (simpler approach): **do not print any parallel branch stage until ALL sibling branches in the same parallel block have reached terminal status.** This ensures:
  - All durations are finalized
  - Branches can be printed in their natural `║1`, `║2`, `║3`, `║4` order
  - The wrapper can print immediately after all branches

**Recommended approach:** Defer all parallel branch and wrapper stage printing until all sibling branches are terminal. Print them as a batch in `║` order, with the wrapper last. This matches snapshot mode behavior exactly.

### 2. Use `wfapi/describe` stage count to validate parallel branch completeness

The wrapper deferral must not rely solely on `_detect_parallel_branches()` (which parses incomplete console output). Instead:

- Use the `wfapi/describe` response to count how many stages exist between the parallel wrapper's first branch and the wrapper itself in the stages array.
- Compare this count against the number of branches found by `_detect_parallel_branches`.
- Only consider the branch list complete when the `wfapi/describe` stage array shows the wrapper's children are stable (same count for 2+ consecutive polls).
- Alternatively, track `parallel_branches` count growth across polls — if it increased since the last poll, more branches may still appear. Only consider the list final when it's stable across polls.

### 3. Ensure the settle loop captures all remaining stages

In `_monitor_build`, the settle loop after `building=false`:

- Increase the settle stability requirement: require stages to be stable (not just the state fingerprint) before exiting. Specifically, do not exit the settle loop until all stages in `wfapi/describe` have been processed and printed.
- After the settle loop exits, do one final `_track_nested_stage_changes` call and print any remaining unprinteed stages (including Deploy and any other stages that appeared late).
- Ensure stderr output from `_track_nested_stage_changes` in the settle loop is visible to the user (not swallowed by TTY/progress bar rendering).

### 4. Consistency rule

The final monitoring output for a completed build must contain the same stages (with the same durations) as `buildgit status --all` for the same build. Differences in formatting (timestamps, progress bars) are acceptable, but stage names, agent names, durations, and ordering must match.

## Test Strategy

### Unit tests

1. **Parallel branch batch printing**: Mock a 4-branch parallel block. Simulate polls where branches complete one at a time. Verify that no branch stage is printed until ALL branches are terminal, then all are printed in `║` order followed by the wrapper.
2. **Duration finalization**: Mock a branch that shows `durationMillis: 0` on first terminal poll, then `durationMillis: 138000` on the next. Verify the printed duration is `2m 18s`, not `<1s`.
3. **Incomplete console branch detection**: Mock console output that only shows 2 of 4 branches initially. Verify the wrapper is NOT printed until all 4 branches appear and are terminal.
4. **Settle loop captures late stages**: Mock a build where "Deploy" appears in `wfapi/describe` only during the settle loop. Verify Deploy is printed before the monitor exits.
5. **Monitoring vs snapshot consistency**: Run a full monitoring simulation, then verify the printed stages match what snapshot mode would produce for the same completed build data.

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
