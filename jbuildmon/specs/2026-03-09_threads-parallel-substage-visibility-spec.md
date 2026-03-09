## Fix `--threads` to show active sub-stages within parallel branches

- **Date:** `2026-03-09T10:33:00-06:00`
- **References:** `specs/done-reports/threads-display-accuracy.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Background

The `--threads` flag (spec: `2026-03-05_threads-display-tty-spec.md`) shows live per-stage progress lines during monitoring. When a parallel block runs multiple branches, each branch should get its own progress line. This works for simple parallel branches (direct `steps {}` blocks), but **fails** for parallel branches that contain nested `stages {}` blocks.

## Problem Statement

### Observed behavior

When monitoring `panorama_integration_tests` with `buildgit --job panorama_integration_tests --threads build`, only **one** of three parallel branches appears in the threads display:

```
[10:19:31] ℹ   Stage: [agent6 guthrie] Declarative: Checkout SCM (<1s)
  [agent6 guthrie] policyStart bounce [========>           ] 48% 28s / ~57s
IN_PROGRESS Job panorama_integration_tests #1783 [====>               ] 29% 30s / ~1m 44s
```

The "palmer tests" branch (running on `palmeragent1` with nested sub-stages `batchrun`) and the "guthrie tests" branch (running nested sub-stages `synconsolemongo42`, `bundletest`, `TLSauth`) are both missing from the threads display — even though they are actively running in parallel.

### Expected behavior

All three parallel branches should show their currently-active stage:

```
[10:19:31] ℹ   Stage: [agent6 guthrie] Declarative: Checkout SCM (<1s)
  [agent6 guthrie] policyStart bounce [========>           ] 48% 28s / ~57s
  [palmeragent1] palmer tests->batchrun [==>                ] 15% 8s / ~39s
  [agent6 guthrie] guthrie tests->synconsolemongo42 [====>             ] 32% 12s / ~37s
IN_PROGRESS Job panorama_integration_tests #1783 [====>               ] 29% 30s / ~1m 44s
```

### Pipeline pattern that triggers the bug

The `panorama_integration_tests` Jenkinsfile (reference copy: `jbuildmon/testcasedata/Jenkinsfile-panorama-integration-tests`) uses this pattern:

```groovy
stage('parallel tests') {
    parallel {
        stage('policyStart bounce') {       // ← simple steps, SHOWS in --threads
            steps { sh 'sleep 30 && ...' }
        }
        stage('palmer tests') {             // ← nested stages, MISSING from --threads
            agent { label 'palmeragent1' }
            stages {
                stage('batchrun') {
                    steps { sh './gradlew ...' }
                }
            }
        }
        stage('guthrie tests') {            // ← nested stages, MISSING from --threads
            stages {
                stage('synconsolemongo42') {
                    steps { sh './gradlew ...' }
                }
                stage('bundletest') { ... }
                stage('TLSauth') { ... }
            }
        }
    }
}
```

### Root cause analysis

The bug is in `_get_follow_active_stages()` in `follow_progress_core.sh` (lines ~150-278).

**How it works today:**

1. Calls `_get_nested_stages()` to fetch all stages from wfapi — this returns a flat array including sub-stages like `batchrun`, `synconsolemongo42`, etc. (**works correctly**)
2. Calls `_detect_parallel_branches()` to find branch names by parsing console output — returns `["policyStart bounce", "palmer tests", "guthrie tests"]` (**works correctly**)
3. Loops through detected branch names to synthesize entries for branches not yet in the result — creates synthetic `IN_PROGRESS` entries for direct branches (**partially works**)
4. **Bug:** When "batchrun" is the actively-running stage (status `IN_PROGRESS` in wfapi), it appears in the nested stages array. But `_get_follow_active_stages()` only looks for stages whose names match the direct branch names. "batchrun" is NOT a branch name — it's a sub-stage within the "palmer tests" branch. So it never gets a synthetic entry and never appears in the threads display.

**The gap:** The snapshot code path (`_get_nested_stages()`) correctly detects sub-stages via `_detect_branch_substages()` and builds `_substage_to_branch` mappings. But the follow/threads code path (`_get_follow_active_stages()`) does **not** use these mappings. It only processes direct branch names.

## Specification

### 1. Fix: `_get_follow_active_stages()` must detect active sub-stages

When iterating wfapi stages, `_get_follow_active_stages()` must also check:

- If an `IN_PROGRESS` stage name matches a known sub-stage of a parallel branch (using the substage-to-branch mapping from `_detect_branch_substages()`)
- If so, synthesize a thread entry for that sub-stage with:
  - `name`: `<branch-name>-><sub-stage-name>` (matching the `->` notation used in snapshot mode)
  - `agent`: the sub-stage's own agent (or inherited from the branch/pipeline agent)
  - `parallel_branch`: the parent branch name
  - `parallel_wrapper`: the wrapper stage name
  - `status`: `IN_PROGRESS`

This brings the follow mode's sub-stage awareness in line with the snapshot mode's existing handling.

### 2. Sub-stage duration estimates

When looking up per-stage duration estimates from the last successful build's wfapi data:

- Look up `<sub-stage-name>` (e.g., "batchrun") in the cached stage durations
- If found, use that as the estimate for the progress bar
- If not found, show an indeterminate progress bar (same as existing behavior for unknown stages)

### 3. Thread line rendering for sub-stages

Sub-stage thread lines use the same format as existing thread lines:

```
  [<agent-name>] <branch-name>-><sub-stage-name> [========>          ] <pct>% <elapsed> / ~<estimate>
```

Examples:
```
  [palmeragent1] palmer tests->batchrun [==>                ] 15% 8s / ~39s
  [agent6 guthrie] guthrie tests->synconsolemongo42 [====>  ] 32% 12s / ~37s
```

### 4. Ordering

Sub-stage lines appear in pipeline order (same order as wfapi returns them), consistent with existing thread line ordering rules from the `--threads` spec.

### 5. Transition behavior

When a branch's sub-stage completes and the next sub-stage starts:
- The old sub-stage line disappears (its status is no longer `IN_PROGRESS`)
- The new sub-stage line appears
- This matches the existing stage transition behavior

When all sub-stages in a branch complete, the branch's thread line disappears — the branch itself is no longer `IN_PROGRESS`.

### 6. Fix: Eliminate redraw flash in `--threads` display

The `--threads` display has a visible flash/blank period between erasing the old status lines and drawing the new ones. This is distracting and should be fixed.

#### Root cause

In `_display_follow_line_progress()` (`follow_progress_core.sh`, lines ~599-664), the redraw sequence is:

1. Fetch running builds via Jenkins API (`_get_running_builds_for_progress()`, line ~612)
2. Fetch active stages via Jenkins API + console parsing (`_render_follow_thread_progress_lines()` → `_get_follow_active_stages()`, line ~619)
3. Fetch queued builds via Jenkins API (`_get_queued_builds_for_progress()`, line ~650)
4. Format all data into `lines=()` array with jq processing (lines ~634-660)
5. Call `_redraw_follow_line_progress_lines()` which erases old content and prints new content (line ~663)

The erase+redraw in step 5 is itself atomic (it builds a single `printf` payload). However, the **previous poll cycle's content was already on screen** during steps 1-4. The flash occurs because the terminal cursor positioning in `_redraw_follow_line_progress_lines()` moves the cursor up and clears lines as part of building the payload — but by the time this executes, the old content has been visible for the entire duration of steps 1-4 (50-500ms of API calls + jq processing).

The actual issue is that `_redraw_follow_line_progress_lines()` handles both the erase of old lines AND the print of new lines in one `printf` call — which IS atomic. But between successive calls to `_redraw_follow_line_progress_lines()`, the old content from the previous cycle remains on screen during all the API and processing work. The perceived "flash" happens when the number of lines changes between redraws (e.g., a thread line disappears), causing the cursor-up count to differ and briefly leaving artifacts.

#### Fix

Ensure the erase-and-redraw is truly flicker-free:

1. **Build the complete output buffer first** — all API calls, jq processing, and line formatting must complete before any terminal manipulation begins.
2. **Use a single atomic write** — the existing `_redraw_follow_line_progress_lines()` already does this via one `printf '%b'` call. Verify this remains the case after changes.
3. **Track previous line count accurately** — when the number of thread lines changes between redraws (stages starting/completing), the cursor-up count must match the exact number of lines previously printed, not the current number. A stale or incorrect line count causes the cursor to move to the wrong position, leaving old content visible or overwriting log lines.
4. **Minimize the window** — if any API calls currently happen inside the erase-to-print window, move them before the erase. All data collection must be complete before the terminal escape sequence begins.

## Integration Test

### New integration test pipeline

Create a new test pipeline `Jenkinsfile-parallel-nested-threads` in `jbuildmon/test/integration/` that exercises the specific pattern that triggers the bug:

```groovy
pipeline {
    agent {
        docker {
            image 'registry:5000/shell-jenkins-agent:latest'
            alwaysPull true
            label 'fastnode'
        }
    }
    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 5, unit: 'MINUTES')
    }
    stages {
        stage('Init') {
            steps {
                echo 'Starting parallel nested threads test'
                sleep 7
            }
        }
        stage('Parallel Work') {
            parallel {
                stage('Simple Branch') {
                    steps {
                        echo 'Simple branch with direct steps'
                        sleep 12
                    }
                }
                stage('Nested Branch') {
                    agent {
                        label 'slownode'
                    }
                    stages {
                        stage('Step A') {
                            steps {
                                echo 'Nested sub-stage A on slownode'
                                sleep 8
                            }
                        }
                        stage('Step B') {
                            steps {
                                echo 'Nested sub-stage B on slownode'
                                sleep 8
                            }
                        }
                    }
                }
                stage('Default Nested') {
                    stages {
                        stage('Step X') {
                            steps {
                                echo 'Nested sub-stage X on default agent'
                                sleep 6
                            }
                        }
                        stage('Step Y') {
                            steps {
                                echo 'Nested sub-stage Y on default agent'
                                sleep 6
                            }
                        }
                    }
                }
            }
        }
        stage('Done') {
            steps {
                echo 'All parallel nested work complete'
                sleep 1
            }
        }
    }
}
```

**Design notes:**
- Sleep durations (6-12s) are well above the poll interval (~5s) so `--threads` has multiple poll cycles to observe each running sub-stage
- Three parallel branches: one simple (direct steps), one nested with a different agent (`slownode`), one nested inheriting the default agent — matches the `panorama_integration_tests` pattern
- Total runtime ~18s for the parallel block (longest branch = `Nested Branch` at ~16s), keeping the test fast

### New Jenkins multibranch job

A new multibranch pipeline job named `buildgit-integration-test-threads`:

- **Type:** Multibranch Pipeline
- **Branch source:** Git, same repository as `ralph1`
- **Script path:** `jbuildmon/test/integration/Jenkinsfile-parallel-nested-threads`
- **Accessible** via the same `JENKINS_URL`, `JENKINS_USER_ID`, `JENKINS_API_TOKEN` credentials

### Integration test bats file

Add a new test file `jbuildmon/test/integration/threads_integration_tests.bats` (or add tests to the existing `integration_tests.bats`) with the following approach:

**Red-green workflow:**

1. **Red phase (before code fix):** The integration test triggers the build, monitors with `--threads`, and captures the thread lines. It asserts that sub-stage lines appear (e.g., `Nested Branch->Step A`). This test **should fail** before the code fix, proving the bug exists.
2. **Green phase (after code fix):** After implementing the fix in `_get_follow_active_stages()`, the same test passes.

**Test cases:**

#### Test: Threads show all active parallel branches including nested sub-stages

1. Trigger `buildgit-integration-test-threads/<branch>` with `buildgit build --no-follow`
2. Monitor with `buildgit --threads status -f --once=120` and capture stderr (thread lines are written to TTY/stderr)
3. Wait for build to complete
4. Assert the captured monitoring output contains thread lines for:
   - `Simple Branch` (direct steps branch)
   - `Nested Branch->Step A` or `Nested Branch->Step B` (nested sub-stages on `slownode`)
   - `Default Nested->Step X` or `Default Nested->Step Y` (nested sub-stages on default agent)

#### Test: Nested sub-stage on different agent shows correct agent name

1. From the captured monitoring output, extract the agent name shown for `Nested Branch->Step A`
2. Assert it differs from the agent shown for `Simple Branch` (different agent labels: `slownode` vs `fastnode`)

#### Test: Snapshot output matches expected structure

1. After build completes, run `buildgit status --all --job buildgit-integration-test-threads/<branch>`
2. Assert stage output includes:
   - `║1 [*] Simple Branch`
   - `║2 [*] Nested Branch->Step A`
   - `║2 [*] Nested Branch->Step B`
   - `║2 [*] Nested Branch`
   - `║3 [*] Default Nested->Step X`
   - `║3 [*] Default Nested->Step Y`
   - `║3 [*] Default Nested`
   - `Parallel Work`

### Jenkinsfile integration stage

Add the new integration test to the `Integration Tests` stage in the root `Jenkinsfile`, or run it as a separate step alongside the existing integration test. Both integration test pipelines can run in parallel since they use different Jenkins jobs.

## Test Strategy

### Unit tests

New unit tests in an appropriate existing or new bats file:

- `threads_substage_detection` — mock wfapi data with a parallel wrapper containing branches with nested sub-stages. Verify `_get_follow_active_stages()` returns entries for the active sub-stages (not just direct branches).
- `threads_substage_agent_attribution` — verify that sub-stage thread entries carry the correct agent (from the sub-stage's own agent, or inherited from the branch agent, not the pipeline default).
- `threads_substage_naming` — verify sub-stage thread entries use `<branch>-><substage>` naming convention.
- `threads_substage_transition` — verify that when one sub-stage completes and the next starts, the thread display transitions correctly.
- `threads_redraw_no_intermediate_clears` — verify that `_redraw_follow_line_progress_lines()` produces a single `printf` payload with no intermediate screen clears. Capture the escape sequences and assert the erase+redraw is one atomic write.
- `threads_redraw_line_count_tracks_previous` — verify that when thread lines change count (e.g., 3 lines → 2 lines), the cursor-up count matches the previous line count, not the current one.

### Existing tests

All existing unit tests and integration tests must continue to pass. The fix must not change snapshot output behavior (which already handles sub-stages correctly).

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
