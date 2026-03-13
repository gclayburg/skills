# Live Bug Report: Build Optimization Diagnostics — Real Jenkins Testing

**Spec:** `jbuildmon/specs/2026-03-11_build-optimization-diagnostics-spec.md`
**Plan:** `jbuildmon/specs/2026-03-11_build-optimization-diagnostics-plan.md`
**Branch:** `optimize-diag-v4`
**Date:** 2026-03-12
**Jenkins:** Build #6 on ralph1/optimize-diag-v4 (854 tests, 4m 10s)

All findings below are from executing `buildgit` against the live Jenkins server.

---

## Bug 1: Per-node test results endpoint returns 404 for all nodes — Features 1 & 4 non-functional

**Severity: HIGH (10 points)**

**Spec Requirement:**

Feature 1 (`--by-stage`) and Feature 4 (`pipeline testSuites`) both depend on per-stage test correlation via the shared `fetch_stage_test_suites` library (Chunk 1). The spec says: "Stage association can be derived by correlating test suite names with the stage that published them, or by querying per-stage test report endpoints if available."

**Actual behavior:**

Both features produce **completely empty results** when run against real Jenkins:

```
$ buildgit timing --tests --by-stage
Build #6 - total 4m 10s
Sequential stages:
  Build  4s  agent6 guthrie
  All Tests  <1s
  Deploy  4s  agent8_sixcore
Parallel group: All Tests (wall 3m 59s, bottleneck: Integration Tests)
  Unit Tests A  1m 35s  agent7 guthrie
  ...
```

The "Test suite timing by stage:" section is completely absent. The JSON output confirms:

```
$ buildgit timing --tests --by-stage --json | jq '.testsByStage'
{}
```

Pipeline enrichment is equally empty:

```
$ buildgit pipeline --json | jq '[.. | objects | select(has("testSuites")) | .name]'
[]
```

**Root cause:** `fetch_stage_test_suites` calls `get_all_stages` to get stage IDs from the wfapi/describe endpoint, then queries `/execution/node/<id>/wfapi/testResults` for each stage. On the real Jenkins server, **every node ID returns HTTP 404** — neither wfapi stage IDs nor Blue Ocean node IDs nor inner step IDs have test results at this endpoint.

Probed all node types:

| ID Source | Example IDs | Test Results |
|-----------|-------------|--------------|
| wfapi stages | 6, 33, 47, 49, 51, 53, 55, 57, 258 | All 404 |
| Blue Ocean nodes | 6, 33, 40, 41, 42, 43, 44, 45, 258 | All 404 |
| Blue Ocean steps | 70, 88, 104, 117, 151, 160, 164, 173, 214 | All 404 |
| Broad scan | 1-260 | All 404 |

Meanwhile, the build-level test report works fine:
```
$ # /testReport/api/json → HTTP 200, returns all 854 test results
```

The spec acknowledged this possibility with "if available" but the implementation provides **no fallback**. The alternative approach mentioned in the spec — "correlating test suite names with the stage that published them" — was never implemented.

**Impact:** Features 1 and 4 are dead code. They pass unit tests only because the test fixtures mock the per-node endpoint returning 200 with test data, which doesn't match real Jenkins behavior.

**Files affected:**
- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/stage_test_correlation.sh` — `_fetch_node_test_results` / `fetch_stage_test_suites`
- All test fixtures that mock the per-node test results endpoint with 200 responses

---

## Bug 2: `--compare` and `-n N` table omit stages within parallel groups

**Severity: HIGH (10 points)**

**Spec Requirement (Feature 3):**

The spec shows `--compare` output with per-stage deltas including children of parallel groups (Unit Tests A-D, Integration):

```
Total                 4m 33s     4m 21s     -12s
  All Tests           4m 22s     4m 10s     -12s
    Unit Tests A        48s        51s       +3s
    Unit Tests B      2m 4s      1m 50s     -14s
```

**Actual behavior:**

```
$ buildgit timing --compare 5 6
Timing comparison: Build #5 vs #6
                               #5         #6      Delta
Total                      3m 56s     4m 10s       +14s
  Build                        4s         4s       +<1s
  All Tests                   <1s        <1s       +<1s
  Deploy                       4s         4s       +<1s
```

Individual test stages (Unit Tests A-E, Integration Tests) are **completely absent**. The entire purpose of the compare view — seeing which test stages improved or regressed — is missing.

The `-n N` table has the same problem:

```
$ buildgit timing -n 3
Build    Total      Build        All Tests    Deploy
#4       4m 10s     4s           <1s          4s
#5       3m 56s     4s           <1s          4s
#6       4m 10s     4s           <1s          4s
```

Only 3 columns (Build, All Tests, Deploy) instead of 8 (Build, Unit Tests A-E, Integration Tests, Deploy). The useful data is invisible.

**Root cause:** `_collect_timing_entry_names` filters `select(.parallelGroup == null)`, excluding all stages within parallel groups. `_timing_value_for_entry` has the same filter.

**Files affected:** `cmd_timing.sh` — `_collect_timing_entry_names`, `_timing_value_for_entry`, `_render_timing_compare_human`, `_render_timing_compare_json`, `_render_timing_multi_table_human`.

---

## Bug 3: Human compare shows wrapper duration, JSON shows wall time — inconsistent output

**Severity: HIGH (10 points)**

**Spec Requirement:** `--compare` human and JSON output should represent the same data consistently.

**Actual behavior:**

The "All Tests" parallel group appears as BOTH a sequential wrapper stage (durationMillis=206ms) and a parallel group (wallDurationMillis=239149ms=3m 59s). The human and JSON compare use **different values**:

| Format | All Tests #5 | All Tests #6 | Delta |
|--------|-------------|-------------|-------|
| Human | <1s (wrapper: 205ms) | <1s (wrapper: 206ms) | +<1s |
| JSON | wall: 225055ms | wall: 239149ms | **+14094ms (≈14s)** |

Proof:
```
$ buildgit timing --compare 5 6       # Human says: All Tests +<1s
$ buildgit timing --compare 5 6 --json | jq '.deltas.stages["All Tests"]'
14094                                   # JSON says: +14s
```

The same query produces contradictory answers. The human output suggests virtually no change in the test phase, while the JSON shows a 14-second increase in wall time.

**Root cause:** `_timing_value_for_entry` (used by human render) matches "All Tests" as a sequential stage first (`select(.parallelGroup == null)`), returning the wrapper's 206ms. But `_render_timing_compare_json` uses `from_entries` on an array containing both `{key: "All Tests", value: 206}` (from stages) and `{key: "All Tests", value: 239149}` (from parallelGroups) — `from_entries` takes the last duplicate key, accidentally using the wall time.

**Files affected:** `cmd_timing.sh` — `_timing_value_for_entry` vs `_render_timing_compare_json` (inconsistent value selection for duplicate-named entries).

---

## Bug 4: Pipeline test stages classified as PARALLEL — testSuites enrichment/rendering broken

**Severity: MEDIUM (5 points)**

**Spec Requirement (Feature 4):**

The spec says `testSuites` should appear on test stages:
```json
{"name": "Unit Tests B", "type": "parallel", "testSuites": [...]}
```

And human output should show:
```
Unit Tests B  (fastnode)  6 suites, 156 tests, 5m 24s cumulative
```

**Actual behavior:**

The real Jenkins Blue Ocean API returns parallel branches as `type: "PARALLEL"`, not `type: "STAGE"`:

```json
{"id": "40", "displayName": "Unit Tests A", "type": "PARALLEL", "firstParent": "33"}
```

But the test fixtures model them as `type: "STAGE"`:

```json
{"id": "20", "displayName": "Unit Tests", "type": "STAGE", "firstParent": "10"}
```

This mismatch means:

1. **Enrichment skips PARALLEL nodes.** `_enrich_pipeline_stages_with_tests` only adds `testSuites` to non-parallel nodes:
   ```jq
   if ($node.type // "") == "parallel" then
       $node + { branches: [...] }   # no testSuites added
   else
       ... + { testSuites: ... }     # only here
   end
   ```

2. **Rendering shows them as "(0 branches)" instead of test summaries:**
   ```
   ├─ Unit Tests A -- parallel fork (0 branches)
   ├─ Unit Tests B -- parallel fork (0 branches)
   ```
   Instead of the spec's:
   ```
   Unit Tests B  (fastnode)  6 suites, 156 tests, 5m 24s cumulative
   ```

Even if Bug 1 (404 test endpoint) were fixed, testSuites would still never appear on test stages because they're type=PARALLEL.

**Files affected:**
- `cmd_pipeline.sh` — `_enrich_pipeline_stages_with_tests` and `_render_pipeline_node_human` (both skip PARALLEL nodes for testSuites)
- Test fixture `pipeline_blue_nodes_42.json` — uses `"type": "STAGE"` for test stages, doesn't match real Jenkins

---

## Bug 5: `--by-stage` shows agent names instead of agent labels

**Severity: MEDIUM (5 points)**

**Spec Requirement (Feature 1):**

The spec uses agent **labels** in the by-stage output:
```
Unit Tests A (wall 51s, sixcore):
```

Where "sixcore" is a label (from `agents --nodes`: `agent8_sixcore` has label `sixcore`).

**Actual behavior:**

The implementation uses agent **names** from console text parsing. Although the by-stage section is empty on the real server (Bug 1), the code and test assertions confirm agent names are used:

```
# From unit test assertion:
assert_output --partial "Unit Tests (wall 1m 0s, agent-a):"
```

Compare with what the spec would show: `Unit Tests (wall 1m 0s, sixcore):`

The real `timing --tests` output confirms agent names are used throughout:
```
Unit Tests A  1m 35s  agent7 guthrie    # agent name, not label "fastnode"
Unit Tests C  1m 37s  agent8_sixcore    # happens to match a label, but it's the agent name
```

**Root cause:** `_render_timing_by_stage_human` reads the agent from `timing_json.stages[].agent`, populated by `_build_stage_agent_map` from console text ("Running on agent-a in ..."). The Jenkinsfile label used to select the agent (e.g., `agent { label 'fastnode' }`) is not captured.

**Files affected:** `cmd_timing.sh` — `_render_timing_by_stage_human`.

---

## Summary

| # | Severity | Points | Description |
|---|----------|--------|-------------|
| 1 | HIGH     | 10     | Per-node test endpoint 404 for all nodes — Features 1 & 4 non-functional |
| 2 | HIGH     | 10     | `--compare` and `-n N` table omit stages within parallel groups |
| 3 | HIGH     | 10     | Human compare shows wrapper duration (<1s) while JSON shows wall time delta (14s) |
| 4 | MEDIUM   | 5      | Pipeline test stages are type=PARALLEL — testSuites enrichment/rendering skipped |
| 5 | MEDIUM   | 5      | `--by-stage` shows agent names instead of agent labels |
| **Total** | | **40** | |

### Verified Working (No Bugs Found)

- **Feature 2** (`agents --nodes`): Fully functional against real Jenkins. Output matches spec format, labels sorted alphabetically, executor counts accurate, JSON structure correct. All 8 nodes displayed properly.
- **Feature 3 core mechanics**: `--compare` relative build numbers (`-1`, `0`) resolve correctly. Delta formatting (+/-/0s) works. `--compare --json` has correct `builds[]` array. The issues are specifically about parallel group handling, not the compare framework itself.
- **Feature 3 `-n N --tests`**: Multi-build table correctly precedes detailed output for the latest build only. The table columns are just incomplete (missing parallel children).

### Key Insight from Live Testing

The most impactful finding is **Bug 1** — it was invisible in unit tests because all test fixtures mock the per-node test endpoint with 200 responses. Against the real Jenkins server (v2.541.2), this endpoint returns 404 for every node ID. Two entire features (by-stage test grouping and pipeline test enrichment) produce zero output on the actual target system.

---

## Fixes Applied (2026-03-13)

### Bug 2 — Fixed (prior to this session)

`_collect_timing_entry_names` was rewritten in the working tree to collect parallel group members hierarchically. `_render_timing_compare_human` updated to indent child members. `_render_timing_compare_json` updated to include all stages regardless of `parallelGroup`. New tests added: `timing_compare_parallel_members_shown_under_group`, `timing_compare_json_includes_parallel_member_deltas`.

### Bug 3 — Fixed

**Root cause confirmed:** `_timing_value_for_entry` checked `stages[]` first, returning the wrapper stage duration (e.g., 206ms) for "All Tests" instead of the parallel group wall time (239s). Human and JSON outputs were inconsistent.

**Fix:** Swapped lookup order in `_timing_value_for_entry` to check `parallelGroups[]` (wall time) before `stages[]`.

**New fixture:** `timing_wfapi_parallel_wrapper_42.json` — models the real Jenkins structure where the parallel group wrapper ("Tests", 2s) also appears as a wfapi stage alongside its parallel branch members.

**New tests:** `timing_compare_uses_wall_time_not_wrapper_for_parallel_group`, `timing_compare_json_uses_wall_time_for_parallel_group`.

### Bug 4 — Fixed

**Root cause confirmed:** `_enrich_pipeline_stages_with_tests` used `$enriched` only for the `sequential` branch of the `if/else`, leaving `parallel` type nodes unenriched. Additionally, `_render_pipeline_node_human` always showed `parallel fork (N branches)` for `parallel` type nodes, even when they had test suite data.

**Fix:** Rewrote `enrich()` in `_enrich_pipeline_stages_with_tests` to capture the recursed node as `$enriched` after both branches of the `if/else`, then apply the testSuites check regardless of node type. Updated `_render_pipeline_node_human` to check for `testSuites` on `parallel` type nodes and show suite count/test count/cumulative duration instead of "parallel fork".

**New fixture:** `pipeline_blue_nodes_parallel_stages_42.json` — Blue Ocean nodes with `type: "PARALLEL"` test stages (matching real Jenkins behavior).

**New tests:** `pipeline_json_testSuites_on_parallel_type_nodes`, `pipeline_human_parallel_type_test_node_shows_suite_info`.

### Bugs 1 and 5 — Not Fixed

**Bug 1** (per-node test endpoint 404): No reliable alternative Jenkins API exists to correlate test suites to pipeline stages. The current behavior (returning `{}`) is correct. This remains a known limitation.

**Bug 5** (agent names vs labels): The Jenkinsfile label used in `agent { label 'xxx' }` is not exposed by any currently-queried API. The agent name (from console parsing) is the best available data. This remains a known limitation.

### Test Results

All **857 tests pass** (853 original + 4 new).
