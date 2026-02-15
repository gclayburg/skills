# Monitoring Mode Missing Stages and Premature Wrapper/Branch Printing
Date: 2026-02-14T19:15:00-0700
References: none
Supersedes: none (amends bug-parallel-stages-display-spec.md, nested-jobs-display-spec.md, feature2026-02-14-numbered-parallel-stage-display-spec.md)

## Overview

Monitoring mode (`buildgit build`, `buildgit push`, `buildgit status -f`) produces significantly different stage output compared to snapshot mode (`buildgit status`) for the same completed build. Many downstream job stages are missing entirely, wrapper stages print too early with incorrect durations, and parallel branch summary stages appear before their children.

## Problem Statement

Comparing build #1999 of the `visualsync` job between monitoring (`status -f`) and snapshot (`status`) reveals three categories of bugs:

### Bug 1: Missing Downstream Job Stages in Monitoring Mode

Many stages from downstream jobs are never printed during monitoring. For example, within `synconsole build->back front tests`, snapshot mode shows all of these stages but monitoring mode omits them entirely:

- `synconsolemongo42` (1m 5s)
- `batchrun` (1m 35s)
- `bundletest` (38s)
- `TLSauth` (27s)

The same pattern repeats for `panorama`, `backend tests`, and all `visualsync track` downstream sub-stages. Also missing: `frontend tests` and `backend tests` duration summary lines.

Snapshot mode shows ~95 stage lines for this build; monitoring mode shows ~65 — roughly 30 stages are lost.

### Bug 2: Wrapper Stage Prints Too Early with Wrong Duration

The `parallel build test` wrapper stage appears almost immediately in monitoring output with a 2-second duration:

```
[18:59:14] i   Stage: [agent6        ] parallel build test (2s)
```

Snapshot mode correctly shows it after all children complete with the aggregate duration:

```
[19:10:15] i   Stage: [agent6        ] parallel build test (4m 5s)
```

### Bug 3: Parallel Branch Summary Stages Print Too Early

Branch summary lines appear before their nested downstream stages have been fetched:

```
[18:59:14] i   Stage:   ║2 [agent6        ] visualsync track (<1s)
[18:59:14] i   Stage: [agent6        ] parallel build test (2s)
[18:59:22] i   Stage:   ║1 [agent7        ] synconsole build->Declarative: Checkout SCM (<1s)
```

Here `visualsync track` and the wrapper print first, then `synconsole build` nested stages start appearing — the ordering is inverted compared to snapshot mode.

## Root Cause Analysis

### Missing stages: Console output timing

`_get_nested_stages()` maps parent stages to downstream builds by parsing console output (`get_console_output()`). In monitoring mode, early polling calls happen before Jenkins has written console output to the API, so `stage_downstream_map` stays empty `{}` and downstream builds are never recursively fetched.

Once a stage is marked as "already printed" in the monitoring tracker's state, it is never re-evaluated — even after console output becomes available in later polls. This means downstream stages that were invisible during the first poll remain invisible forever.

Key code path: `_get_nested_stages()` fetches console output at approximately line 3262 in `jenkins-common.sh`. When this returns empty, `_map_stages_to_downstream()` produces an empty mapping and downstream recursion is skipped.

### Premature wrapper/branch printing: No deferral in monitoring path

`_track_nested_stage_changes()` (approximately line 2113-2125 in `jenkins-common.sh`) prints any stage the moment it reaches terminal status (SUCCESS/FAILED/UNSTABLE). There is no deferral logic for wrapper stages or branch summaries in the monitoring code path.

The snapshot path has deferred wrapper logic (`deferred_wrappers` at approximately line 3460-3491), but this is only used by `_display_nested_stages_json()` in the snapshot code path — `_track_nested_stage_changes()` does not use it.

### Incomplete banner baseline

The banner calls `_display_stages()` with `--completed-only` before adequate console output is available. This creates an incomplete baseline state (`_BANNER_STAGES_JSON`) that the monitoring loop inherits and never recovers from.

## Scope

Applies to all monitoring mode commands:
- `buildgit build`
- `buildgit push`
- `buildgit status -f`

Snapshot mode (`buildgit status`) and JSON mode (`buildgit status --json`) are not affected — they already work correctly.

## Solution

### Fix 1: Re-evaluate downstream mapping on each poll

When `_track_nested_stage_changes()` calls `_get_nested_stages()`, stages that previously had no downstream mapping (because console output was unavailable) must be re-evaluated if console output has since become available. The monitoring state must not permanently mark a stage as "no downstream" after a single failed lookup.

Specifically:
- Track which parent stages have been successfully mapped to downstream builds
- On each poll, re-attempt downstream mapping for any unmapped parent stages
- When a previously unmapped stage gains a downstream mapping, fetch and display those nested stages as new transitions

### Fix 2: Defer wrapper and branch summary printing in monitoring mode

Port the deferred wrapper logic from the snapshot path into the monitoring path:
- When a wrapper stage reaches terminal status, do **not** print it immediately
- Only print the wrapper after all its parallel branch stages (and their nested downstream stages) have reached terminal status
- Similarly, defer branch summary printing until that branch's downstream stages have all been fetched and printed
- Calculate aggregate duration using the existing formula: `wrapper_api_duration + max(branch_durations)`

### Fix 3: Refresh banner baseline when downstream data becomes available

When the monitoring loop's first successful downstream fetch returns stages that were not in the banner baseline, treat those as new stage transitions and print them. Do not suppress them just because the parent stage was already printed in the banner.

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/lib/jenkins-common.sh` | Update `_track_nested_stage_changes()` to re-evaluate downstream mapping for unmapped stages on each poll; add deferred printing logic for wrapper and branch summary stages in monitoring mode; fix banner baseline refresh when downstream data becomes available |
| `skill/buildgit/scripts/buildgit` | Any wiring needed so the monitoring loop passes state about which stages need downstream re-evaluation |
| `test/parallel_stages.bats` | Add tests for monitoring mode producing consistent output with snapshot mode for completed builds with parallel/nested stages |

## Acceptance Criteria

1. Monitoring mode prints the same set of downstream stages as snapshot mode for the same completed build (stage names and nesting match; timestamps and interleaving order may differ due to real-time nature)
2. Wrapper stages are not printed until all parallel branches and their nested downstream stages have completed
3. Wrapper stages show aggregate duration, not premature API-only duration
4. Branch summary stages are not printed before their downstream nested stages
5. Stages that were not fetchable in early polls (due to unavailable console output) are fetched and printed when console output becomes available in later polls
6. No regression for builds without parallel stages or without downstream jobs
7. `buildgit status` (snapshot), `buildgit status --json` continue to work unchanged

## Test Strategy

- Add bats test(s) that mock a monitoring sequence where console output becomes available partway through — verify all downstream stages are eventually printed
- Add bats test(s) that verify wrapper deferred printing in monitoring mode (wrapper not printed before children)
- Regression tests for simple (non-parallel, non-nested) builds
- Manual comparison of `buildgit --job visualsync build` vs `buildgit --job visualsync status` to confirm stage parity
