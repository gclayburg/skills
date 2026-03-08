## Display sub-stages within parallel branches with correct nesting, agents, and durations

- **Date:** `2026-03-07T09:15:00-0700`
- **References:** `specs/done-reports/display-completed-stages.md`, `jbuildmon/testcasedata/Jenkinsfile-panorama-integration-tests`
- **Supersedes:** none (amends `bug-parallel-stages-display-spec.md`, `feature2026-02-14-numbered-parallel-stage-display-spec.md`)
- **State:** `IMPLEMENTED`

## Background

When a Jenkins parallel branch contains a `stages {}` block with nested sequential stages, Jenkins wfapi returns all stages — both branches and their sub-stages — as flat siblings in the `stages[]` array. The current code only recognizes direct `(Branch: <name>)` entries as parallel branches. Sub-stages within branches are not associated with their parent branch, causing them to display as unrelated top-level stages outside the parallel block.

### Example pipeline (panorama_integration_tests)

```groovy
stage('parallel tests') {
    parallel {
        stage('policyStart bounce') {
            steps { ... }  // runs on inherited guthrie agent
        }
        stage('palmer tests') {
            agent { label 'palmeragent1' }
            stages {
                stage('batchrun') { steps { ... } }
            }
        }
        stage('guthrie tests') {
            // inherits pipeline-level guthrie agent
            stages {
                stage('synconsolemongo42') { steps { ... } }
                stage('bundletest') { steps { ... } }
                stage('TLSauth') { steps { ... } }
            }
        }
    }
}
```

### Current (incorrect) output

```
[15:52:25] ℹ   Stage: [agent6 guthrie] Declarative: Checkout SCM (<1s)
[15:53:34] ℹ   Stage:   ║1 [agent6 guthrie] policyStart bounce (57s)
[15:55:07] ℹ   Stage:   ║2 [agent6 guthrie] palmer tests (<1s)
[15:55:07] ℹ   Stage:   ║3 [agent1paton   ] guthrie tests (<1s)
[15:55:07] ℹ   Stage: [agent6 guthrie] parallel tests (57s)
[15:55:07] ℹ   Stage: [agent6 guthrie] synconsolemongo42 (40s)
[15:55:07] ℹ   Stage: [agent6 guthrie] batchrun (1m 35s)
[15:55:07] ℹ   Stage: [agent6 guthrie] bundletest (30s)
[15:55:07] ℹ   Stage: [agent6 guthrie] TLSauth (28s)
[15:55:07] ℹ   Stage: [agent6 guthrie] Declarative: Post Actions (<1s)
```

### Expected (correct) output

```
[15:52:25] ℹ   Stage: [agent6 guthrie] Declarative: Checkout SCM (<1s)
[15:53:34] ℹ   Stage:   ║1 [agent6 guthrie] policyStart bounce (57s)
[15:55:07] ℹ   Stage:   ║2 [agent1paton   ] palmer tests->batchrun (1m 35s)
[15:55:07] ℹ   Stage:   ║2 [agent1paton   ] palmer tests (1m 35s)
[15:55:07] ℹ   Stage:   ║3 [agent6 guthrie] guthrie tests->synconsolemongo42 (40s)
[15:55:07] ℹ   Stage:   ║3 [agent6 guthrie] guthrie tests->bundletest (30s)
[15:55:07] ℹ   Stage:   ║3 [agent6 guthrie] guthrie tests->TLSauth (28s)
[15:55:07] ℹ   Stage:   ║3 [agent6 guthrie] guthrie tests (1m 38s)
[15:55:07] ℹ   Stage: [agent6 guthrie] parallel tests (1m 38s)
[15:55:07] ℹ   Stage: [agent6 guthrie] Declarative: Post Actions (<1s)
```

Key differences from current output:
- Sub-stages display with `->` nesting under their parent branch name (same notation as downstream builds)
- Sub-stages carry their branch's parallel marker (`║2`, `║3`)
- Sub-stages appear before their parent branch summary line
- `palmer tests` and `guthrie tests` show correct agents (not swapped)
- Branch durations include sub-stage time (`palmer tests` = 1m 35s, `guthrie tests` = 1m 38s)
- `parallel tests` wrapper duration reflects the longest branch (1m 38s, not 57s)

## Root Cause Analysis

### Problem 1: Sub-stages not recognized as belonging to a parallel branch

`_detect_parallel_branches()` in `failure_analysis.sh:261` only detects direct branch names from `(Branch: <name>)` patterns. It does not detect that `batchrun` is a sub-stage of `palmer tests` or that `synconsolemongo42`, `bundletest`, `TLSauth` are sub-stages of `guthrie tests`.

The Jenkins console output contains the hierarchy:

```
[Pipeline] { (Branch: guthrie tests)
[Pipeline] {
[Pipeline] { (synconsolemongo42)
...
[Pipeline] } // synconsolemongo42
[Pipeline] { (bundletest)
...
[Pipeline] } // bundletest
[Pipeline] { (TLSauth)
...
[Pipeline] } // TLSauth
[Pipeline] } // guthrie tests stages block
[Pipeline] } // end Branch: guthrie tests
```

The `{` / `}` depth tracking can determine which sub-stages are inside which branch.

### Problem 2: Sub-stage agents not inherited from parent branch

Since sub-stages are not associated with their branch, they don't inherit the branch's agent. Instead they get whatever `_build_stage_agent_map()` matches from the console — which may be wrong due to interleaved parallel output.

### Problem 3: Branch durations don't include sub-stage time

The wfapi reports `palmer tests` and `guthrie tests` with very short durations (just the setup time of the `stages {}` block). The sub-stage durations are on separate stage entries in the flat wfapi array. No code aggregates sub-stage durations back into their parent branch.

### Problem 4: Wrapper duration only counts direct branch durations

The existing wrapper aggregate formula `wrapper_api_duration + max(branch_durations)` uses each branch's raw wfapi duration. Since branches with sub-stages have near-zero wfapi durations, the wrapper aggregate is wrong — it only reflects branches without sub-stages (like `policyStart bounce` at 57s).

### Code locations

| Location | Role |
|----------|------|
| `failure_analysis.sh:261` `_detect_parallel_branches()` | Only detects direct branches, not sub-stages within them |
| `json_output.sh:429` `_build_stage_agent_map()` | Agent map doesn't account for branch-to-substage inheritance |
| `json_output.sh:550` `_get_nested_stages()` | Processes stages flat; doesn't associate sub-stages with branches or compute branch aggregate durations |

## Specification

### 1. Detect sub-stages within parallel branches

Add a new function `_detect_branch_substages()` that parses the console output and returns a mapping from branch name to an ordered list of sub-stage names contained within that branch.

**Input:** console output text, wrapper stage name
**Output:** JSON object mapping branch names to arrays of sub-stage names

```json
{
  "palmer tests": ["batchrun"],
  "guthrie tests": ["synconsolemongo42", "bundletest", "TLSauth"],
  "policyStart bounce": []
}
```

**Algorithm:**
1. Find the `[Pipeline] { (<wrapper_stage>)` block in the console
2. Within it, find `[Pipeline] parallel`
3. For each `[Pipeline] { (Branch: <name>)` block, track `{`/`}` depth
4. Any `[Pipeline] { (<stageName>)` that appears inside the branch block (at depth > 1) and whose `<stageName>` is not a `Branch:` prefix is a sub-stage of that branch
5. Normalize `Branch: <name>` to `<name>` for wfapi compatibility

This can be integrated into `_detect_parallel_branches()` or kept as a separate companion function.

### 2. Display sub-stages with branch nesting

In `_get_nested_stages()`, when processing stages that are identified as sub-stages of a parallel branch:

- **Name:** Display as `<branch_name>-><substage_name>` using the existing `->` nesting notation
- **Parallel marker:** Inherit the parent branch's parallel path number (e.g., `║2`, `║3`)
- **Ordering:** Sub-stages appear before their parent branch summary line (same pattern as downstream build stages appearing before their wrapper)
- **Indentation:** Same indentation level as the branch itself (2-space indent for first-level parallel)

### 3. Sub-stage agent inheritance

Sub-stages within a parallel branch should inherit their agent using this precedence:

1. **Per-stage agent from `_build_stage_agent_map()`** — if the sub-stage has its own `Running on` line in the console (e.g., it does its own `node {}`)
2. **Parent branch agent** — from the branch's `_build_stage_agent_map()` entry or the branch's `Running on` line
3. **Pipeline-scope agent** — the `_extract_pre_stage_agent_from_console()` fallback

This mirrors how `_get_nested_stages()` already handles downstream build stages — each stage tries its own agent first, then falls back.

### 4. Branch aggregate duration

For parallel branches that contain sub-stages, compute an aggregate duration:

```
branch_aggregate = branch_api_duration + sum(substage_durations)
```

This uses **sum** (not max) because sub-stages within a branch execute **sequentially**. This differs from the parallel wrapper formula which uses `max(branch_durations)` because branches run concurrently.

The branch summary line displays this aggregate duration.

### 5. Wrapper duration uses branch aggregates

The existing wrapper aggregate formula remains:

```
wrapper_aggregate = wrapper_api_duration + max(branch_aggregate_1, branch_aggregate_2, ...)
```

But now each `branch_aggregate` includes the sub-stage durations (from section 4), so the wrapper correctly reflects the longest branch's total time.

### 6. Sub-stages excluded from top-level display

Stages identified as sub-stages of a parallel branch must NOT appear as independent top-level stages. They should only appear within their branch's parallel block. This prevents the current duplicate display where sub-stages show up both as flat top-level stages and (after this fix) as nested branch stages.

### 7. Consistency across output modes

The sub-stage nesting fix must apply to all output modes:
- **Snapshot mode** (`status`, `status --all`): sub-stages shown nested within their branch
- **Monitoring mode** (`push`, `build`, `status -f`): sub-stages printed with branch parallel marker as they complete
- **JSON mode** (`status --json`): sub-stages include `parallel_branch` and `parallel_wrapper` fields, plus a `parent_branch_stage` field indicating they are local sub-stages (not downstream builds)
- **Threads mode** (`--threads`): active sub-stages shown with their branch's agent

### 8. JSON output for branch sub-stages

Sub-stages within parallel branches appear in JSON with these fields:

```json
{
  "name": "guthrie tests->synconsolemongo42",
  "status": "SUCCESS",
  "duration_ms": 40000,
  "agent": "agent6 guthrie",
  "parallel_branch": "guthrie tests",
  "parallel_wrapper": "parallel tests",
  "parallel_path": "3",
  "parent_branch_stage": "guthrie tests"
}
```

The `parent_branch_stage` field distinguishes local sub-stages from downstream build stages (which have `downstream_job` and `downstream_build` fields instead).

### 9. Edge cases

- **Branch with no sub-stages** (e.g., `policyStart bounce`): No change from current behavior. Displayed as a simple parallel branch.
- **Branch with both sub-stages and its own steps**: The branch's own steps don't create named stages in wfapi — only `stages {}` blocks do. So this case reduces to either having sub-stages or not.
- **Deeply nested parallel**: A sub-stage within a branch that itself contains a `parallel {}` block. The existing parallel detection already handles nested parallel with path notation (e.g., `║3.1`). Sub-stages at that level would inherit the nested path.
- **Sub-stage that triggers a downstream build**: A sub-stage like `batchrun` could itself contain `build job: ...`. The existing downstream nesting (`->`) composes with the branch nesting: `palmer tests->batchrun->DownstreamStage`.

## Test Strategy

### Unit tests

1. **Sub-stage detection**: Mock console output for the panorama_integration_tests pipeline. Verify `_detect_branch_substages()` returns `{"palmer tests": ["batchrun"], "guthrie tests": ["synconsolemongo42", "bundletest", "TLSauth"], "policyStart bounce": []}`.

2. **Sub-stage naming**: Verify sub-stages display as `<branch>-><substage>` in stage output (e.g., `guthrie tests->synconsolemongo42`).

3. **Sub-stage parallel markers**: Verify sub-stages carry their parent branch's parallel path (`║2` for `palmer tests` sub-stages, `║3` for `guthrie tests` sub-stages).

4. **Sub-stage ordering**: Verify sub-stages appear before their parent branch summary line in the output.

5. **Sub-stage agent inheritance**: Mock a branch with its own agent (`palmer tests` on `agent1paton`). Verify its sub-stage `batchrun` inherits `agent1paton`.

6. **Sub-stage agent inheritance — no branch agent**: Mock a branch with no explicit agent (`guthrie tests`). Verify sub-stages inherit `pipeline_scope_agent`.

7. **Branch aggregate duration**: Verify `guthrie tests` shows 1m 38s (sum of synconsolemongo42=40s + bundletest=30s + TLSauth=28s + guthrie_tests_api_duration).

8. **Wrapper aggregate with sub-stage branches**: Verify `parallel tests` shows 1m 38s (max of policyStart=57s, palmer=1m 35s, guthrie=1m 38s + wrapper_api_duration).

9. **Sub-stages excluded from top-level**: Verify `synconsolemongo42`, `batchrun`, `bundletest`, `TLSauth` do NOT appear as independent top-level stages outside the parallel block.

10. **Branch with no sub-stages**: Verify `policyStart bounce` displays identically to current behavior.

11. **JSON sub-stage fields**: Verify JSON output for sub-stages includes `parallel_branch`, `parallel_wrapper`, `parallel_path`, and `parent_branch_stage`.

12. **No parallel stages regression**: Verify a simple pipeline (no parallel blocks) displays identically to current behavior.

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
