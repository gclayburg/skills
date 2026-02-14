# Parallel Branch Downstream Mapping Fix
Date: 2026-02-14T00:00:00-0700
References: specs/done-reports/bug2026-02-14-parallel-jobs-should-show-all-stages-raw-bugreport.md, specs/bug-parallel-stages-display-spec.md
Supersedes: none (amends bug-parallel-stages-display-spec.md)

## Overview

In pipelines that run parallel branch stages (for example `Build Handle` and `Build SignalBoot`), `buildgit status` can incorrectly map one branch to the wrong downstream job when stage log extraction contains multiple `Starting building:` lines. This causes nested stages for one branch to be missing or replaced with stages from the other branch.

This spec formalizes the expected stage-to-downstream mapping behavior so all output modes show the correct nested stages for each parallel branch.

## Problem Statement

Observed behavior on `phandlemono-IT` build `#31`:
- Output showed `Build SignalBoot` completed, but nested stages did not match the actual SignalBoot downstream job.
- JSON stage data associated `Build SignalBoot` nested entries with `phandlemono-handle` instead of `phandlemono-signalboot`.
- As a result, users could not trust nested stage details for parallel branches.

## Root Cause

Downstream detection per stage used `detect_all_downstream_builds(stage_logs)` and selected the first match.

When extracted stage logs include multiple branch trigger lines, first-match selection can mis-associate a parallel branch with another branch's downstream job.

## Requirements

1. Stage-to-downstream mapping must select the downstream job/build that best matches the current stage name when multiple matches exist.
2. Mapping behavior must be consistent across:
- `buildgit status`
- `buildgit status --json`
- `buildgit status -f`
- `buildgit push` (monitoring path)
- `buildgit build` (monitoring path)
3. Parallel branch nested stages must be attributed to the correct downstream job and build.
4. Existing single-match behavior must remain unchanged.
5. If no confident match exists, fallback must be deterministic and stable.

## Solution

Add a stage-aware downstream selection helper that:
- Accepts stage name plus all downstream matches extracted from stage logs.
- Scores candidates by token overlap between stage name and job name.
- Uses build number as deterministic tiebreaker.
- Falls back to the last detected match when no token match exists.

Apply this helper in both snapshot mapping and monitoring mapping code paths.

## Scope

- Shell logic in shared Jenkins helpers used by both snapshot and monitoring output.
- Unit tests validating mapping behavior under ambiguous multi-match stage logs.

## Files Affected

| File | Expected change |
|------|------------------|
| `jbuildmon/skill/buildgit/scripts/lib/jenkins-common.sh` | Add stage-aware downstream selector and use it in snapshot + monitoring stage mapping. |
| `jbuildmon/test/nested_stages.bats` | Add regression test for ambiguous multi-match logs in parallel branches. |

## Acceptance Criteria

1. For `phandlemono-IT`-style parallel builds, `Build SignalBoot` maps to `phandlemono-signalboot` and `Build Handle` maps to `phandlemono-handle`.
2. `buildgit status --json` nested stage entries for each branch report correct `downstream_job` and `downstream_build` values.
3. Text output (`status`, `status -f`, monitoring paths) shows nested stages from the correct downstream build for each parallel branch.
4. Existing tests continue to pass.
5. Added regression test fails before the fix and passes after the fix.

## Notes

Per `specs/README.md` consistency rule, this bug fix applies to all status and monitoring output paths rather than a single command mode.
