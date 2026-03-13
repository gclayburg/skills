# Implementation Plan: Build Optimization Diagnostics

**Parent spec:** `jbuildmon/specs/2026-03-11_build-optimization-diagnostics-spec.md`

## Contents

- [x] **Chunk 1: Stage-Level Test Correlation Library**
- [x] **Chunk 2: Feature 2 — `buildgit agents --nodes`**
- [x] **Chunk 3: Feature 1 — `buildgit timing --tests --by-stage`**
- [x] **Chunk 4: Feature 3 — `buildgit timing --compare` and multi-build table**
- [x] **Chunk 5: Feature 4 — `buildgit pipeline` enriched with test suites**


## Chunk Detail

### Chunk 1: Stage-Level Test Correlation Library

#### Description

Create a shared library that maps JUnit test suites to their parent pipeline stages by querying the Jenkins wfapi per-stage test result endpoint. This shared logic is consumed by both Chunk 3 (timing `--by-stage`) and Chunk 5 (pipeline `testSuites`). Keeping it in one place avoids duplication and ensures both features stay consistent.

#### Spec Reference

See spec [Feature 1](./2026-03-11_build-optimization-diagnostics-spec.md#feature-1-test-to-stage-mapping-in-timing-output) §Data source and [Feature 4](./2026-03-11_build-optimization-diagnostics-spec.md#feature-4-test-to-stage-assignment-in-pipeline-output) §Requirements — "Features 1 and 4 overlap in data source... implementation should share the underlying test-report-to-stage correlation logic."

#### Dependencies

- None (standalone library sourced by callers)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/stage_test_correlation.sh`
- `jbuildmon/test/stage_test_correlation.bats`
- `jbuildmon/test/fixtures/stage_test_corr_wfapi_42.json`
- `jbuildmon/test/fixtures/stage_test_corr_node_101_tests.json`
- `jbuildmon/test/fixtures/stage_test_corr_node_102_tests.json`
- `jbuildmon/test/fixtures/stage_test_corr_node_103_tests.json`

#### Implementation Details

1. **Discover the per-stage test result endpoint** by inspecting `wfapi/describe` for a build. Each stage node has an `id` field. The endpoint `/job/<job>/<build>/execution/node/<nodeId>/wfapi/testResults` returns a JSON object (or 404 if no tests ran on that node):
   ```
   {
     "id": "101",
     "urlName": "...",
     "testResult": {
       "totalCount": 94,
       "skipCount": 0,
       "failCount": 0,
       "suites": [
         {"name": "buildgit_status_follow", "duration": 122.3, "cases": [...]}
       ]
     }
   }
   ```
   Use `jenkins_api_with_status` and handle 404 silently (no tests for that stage).

2. **Create `stage_test_correlation.sh`** with two public functions:

   **`fetch_stage_test_suites(job_name, build_number)`**
   - Calls `get_all_stages` to obtain the stage list (names + ids).
   - For each stage, calls `_fetch_node_test_results job_path build_number node_id`.
   - Returns a JSON object keyed by stage name:
     ```json
     {
       "Unit Tests A": [
         {"name": "buildgit_status_follow", "tests": 74, "durationMs": 122300, "failures": 0}
       ],
       "Unit Tests B": [...]
     }
     ```
   - Stages with no test results are omitted from the map.

   **`_fetch_node_test_results(job_path, build_number, node_id)`** (internal)
   - Queries `jenkins_api_with_status "${job_path}/${build_number}/execution/node/${node_id}/wfapi/testResults"`.
   - On 200: extracts `.testResult.suites[]` → `{name, tests: (.cases|length), durationMs: (.duration*1000|floor), failures: ([.cases[]?|select(.status=="FAILED")]|length)}`.
   - On 404 or empty: returns `[]`.
   - On other errors: returns `[]` (non-fatal; callers degrade gracefully).

3. **Handle `get_all_stages` id field**: The existing `get_all_stages` function extracts `id` but the current `jq` map in `api_test_results.sh` already includes `id: (.id // "")`. Verify that the `id` field is preserved through to callers. No change to `get_all_stages` should be needed.

4. **Add fixture files** representing a real wfapi/describe output and per-node test result responses for builds used in tests:
   - `stage_test_corr_wfapi_42.json` — wfapi/describe with 3 stages (ids 101, 102, 103)
   - `stage_test_corr_node_101_tests.json` — test results for node 101 (2 suites)
   - `stage_test_corr_node_102_tests.json` — test results for node 102 (3 suites)
   - `stage_test_corr_node_103_tests.json` — 404 response scenario (no tests)

#### Test Plan

**Test File:** `test/stage_test_correlation.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `fetch_stage_test_suites_returns_map_keyed_by_stage_name` | Returns JSON object with stage names as keys | Feature 1 §Data source |
| `fetch_stage_test_suites_correct_suite_fields` | Each suite entry has name, tests, durationMs, failures | Feature 1 §Requirements |
| `fetch_stage_test_suites_stage_with_no_tests_omitted` | Stage with 404 node response absent from map | Feature 1 §Requirements |
| `fetch_stage_test_suites_empty_build_returns_empty_map` | Empty stages list → `{}` | Feature 1 §Data source |
| `fetch_node_test_results_404_returns_empty_array` | 404 from Jenkins returns `[]`, no error | Feature 1 §Data source |
| `fetch_node_test_results_parses_suites_correctly` | Suite count, duration, failure count correct | Feature 1 §Requirements |
| `fetch_node_test_results_failure_count_correct` | Counts only FAILED cases, not REGRESSION | Feature 4 §Requirements |

**Mocking Requirements:**
- Mock `jenkins_api_with_status` to return fixture file contents based on endpoint pattern.
- Mock `jenkins_api` (used by `get_all_stages`) to return `stage_test_corr_wfapi_42.json`.

**Dependencies:** None

#### Implementation Log

- Added [`jbuildmon/skill/buildgit/scripts/lib/jenkins-common/stage_test_correlation.sh`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/lib/jenkins-common/stage_test_correlation.sh) with `fetch_stage_test_suites` and `_fetch_node_test_results`; both degrade to empty JSON on missing node data, invalid responses, or non-200/non-404 statuses.
- Updated [`jbuildmon/skill/buildgit/scripts/lib/jenkins-common.sh`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/lib/jenkins-common.sh) to source the new shared library so later timing/pipeline chunks can consume it without additional loader changes.
- Added [`jbuildmon/test/stage_test_correlation.bats`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/stage_test_correlation.bats) plus four new fixtures under [`jbuildmon/test/fixtures`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures) to cover stage-keyed aggregation, suite field extraction, silent 404 handling, empty-build behavior, and FAILED-vs-REGRESSION counting.
- Key decision: failure counts intentionally include only `FAILED` cases, matching the chunk spec and preserving room for later callers to represent regressions separately if needed.

---

### Chunk 2: Feature 2 — `buildgit agents --nodes`

#### Description

Add a `--nodes` flag to `buildgit agents` that pivots the output from a label-centric view to a node-centric view. Each physical node appears once with all its labels, executor counts, and busy/idle status. This is independent of all other chunks.

#### Spec Reference

See spec [Feature 2](./2026-03-11_build-optimization-diagnostics-spec.md#feature-2-agent-node-label-overlap-view) §Specification and §Requirements.

#### Dependencies

- None

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh` (modified)
- `jbuildmon/test/buildgit_agents.bats` (new tests appended)
- `jbuildmon/test/fixtures/agents_computers_overlap.json` (new fixture)

#### Implementation Details

1. **Add `AGENTS_NODES` flag to `_parse_agents_options`**:
   ```bash
   --nodes)
       AGENTS_NODES=true
       shift
       ;;
   ```
   Initialize `AGENTS_NODES=false` at the top of `_parse_agents_options`.

2. **Add `_build_agents_nodes_data(computers_json)`** function:
   - Takes the raw computers JSON already fetched via `_fetch_computers`.
   - Uses `jq` to pivot: for each `computer[]`, emit one node entry with `name`, `executors`, `busy` (via executor scan), `labels[]` (sorted alphabetically).
   - Returns a JSON object:
     ```json
     {
       "nodes": [
         {
           "name": "agent6 guthrie",
           "executors": 3,
           "busy": 0,
           "idle": 3,
           "online": true,
           "labels": ["agent6", "dockernode", "fastnode", "guthrie"]
         }
       ]
     }
     ```
   - Nodes sorted alphabetically by `name`.

3. **Add `_render_agents_nodes_human(nodes_json)`** function:
   - Iterates `.nodes[]`, prints:
     ```
     Node: agent6 guthrie  (3 executors, 0 busy)
       Labels: agent6, dockernode, fastnode, guthrie
     ```
   - Blank line between nodes.

4. **Add `_render_agents_nodes_json(nodes_json)`** function:
   - Passes `nodes_json` through `jq '.'`.

5. **Update `cmd_agents`**:
   - After `_build_agents_data` (used for label view) add a branch:
     ```bash
     if [[ "$AGENTS_NODES" == "true" ]]; then
         local computers_json
         computers_json=$(_fetch_computers)
         local nodes_json
         nodes_json=$(_build_agents_nodes_data "$computers_json")
         if [[ "$AGENTS_JSON" == "true" ]]; then
             _render_agents_nodes_json "$nodes_json"
         else
             _render_agents_nodes_human "$nodes_json"
         fi
         return 0
     fi
     ```
   - Place this branch early in `cmd_agents` before calling `_build_agents_data`.

6. **Update `buildgit` help text** in the main script to add `--nodes` to the `agents` command description.

7. **Add fixture** `agents_computers_overlap.json`: a computers JSON where some nodes share labels (e.g., `agent6` has labels `fastnode` and `dockernode`), matching the example output in the spec.

#### Test Plan

**Test File:** `test/buildgit_agents.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `agents_nodes_human_readable_basic` | `--nodes` output contains "Node:" lines with labels | Feature 2 §Specification |
| `agents_nodes_human_executor_count` | Executor count and busy status shown per node | Feature 2 §Requirements |
| `agents_nodes_sorted_alphabetically` | Nodes appear in alpha order by name | Feature 2 §Requirements |
| `agents_nodes_each_label_listed` | All labels of a multi-label node appear in output | Feature 2 §Requirements |
| `agents_nodes_json_has_nodes_array` | `--nodes --json` output has top-level `nodes` array | Feature 2 §Requirements |
| `agents_nodes_json_node_fields` | Each node in JSON has name, executors, busy, labels[] | Feature 2 §Requirements |
| `agents_nodes_does_not_affect_default_view` | Without `--nodes`, default label view unchanged | Feature 2 §Requirements |

**Mocking Requirements:**
- Mock `jenkins_api` to return `agents_computers_overlap.json` for `/computer/api/json?...` endpoint.
- No label info endpoint needed for `--nodes` view (only `/computer` is queried).

**Dependencies:** None

#### Implementation Log

- Updated [`jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh) to add `--nodes`, a node-centric JSON builder, and separate human/JSON renderers that reuse the existing `/computer/api/json` payload and leave the label view untouched.
- Updated [`jbuildmon/skill/buildgit/scripts/buildgit`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/buildgit) help text to advertise `agents --nodes`; finalize should propagate the help change to the remaining documentation files listed in the plan workflow.
- Added [`jbuildmon/test/fixtures/agents_computers_overlap.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/agents_computers_overlap.json) plus seven `--nodes` tests in [`jbuildmon/test/buildgit_agents.bats`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/buildgit_agents.bats) covering human output, executor/busy counts, alpha sorting, label lists, JSON shape, and default-view regression protection.
- Key decision: the node view intentionally derives busy executors from active executor URLs and sorts node labels alphabetically, matching the chunk spec while avoiding any dependency on per-label API lookups.

---

### Chunk 3: Feature 1 — `buildgit timing --tests --by-stage`

#### Description

Add a `--by-stage` flag to `buildgit timing` that groups test suite output under their parent pipeline stage. When `--tests --by-stage` are combined, the human-readable output shows per-stage sections listing test suites with wall time and test count. JSON output adds a `testsByStage` field. This chunk depends on the shared correlation library from Chunk 1.

#### Spec Reference

See spec [Feature 1](./2026-03-11_build-optimization-diagnostics-spec.md#feature-1-test-to-stage-mapping-in-timing-output) §Specification and §Requirements.

#### Dependencies

- **Chunk 1** (`fetch_stage_test_suites` from `stage_test_correlation.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh` (modified)
- `jbuildmon/test/buildgit_timing.bats` (new tests appended)
- `jbuildmon/test/fixtures/timing_stage_tests_wfapi_42.json` (new fixture — wfapi/describe with stage ids)
- `jbuildmon/test/fixtures/timing_stage_tests_node_10_tests.json` (new fixture)
- `jbuildmon/test/fixtures/timing_stage_tests_node_11_tests.json` (new fixture)

#### Implementation Details

1. **Add `TIMING_BY_STAGE` flag to `_parse_timing_options`**:
   ```bash
   --by-stage)
       TIMING_BY_STAGE=true
       shift
       ;;
   ```
   Initialize `TIMING_BY_STAGE=false`. When `--by-stage` is present without `--tests`, it is ignored silently.

2. **Source `stage_test_correlation.sh`** at the top of `cmd_timing.sh` (or ensure the main buildgit script sources it). Add:
   ```bash
   # shellcheck source=lib/jenkins-common/stage_test_correlation.sh
   source "${_SCRIPT_DIR}/lib/jenkins-common/stage_test_correlation.sh"
   ```
   Check how other libraries are sourced in `buildgit` to match the existing pattern.

3. **Add `_render_timing_by_stage_human(timing_json, stage_tests_map_json)`** function:
   - Prints the standard timing header (`Build #N - total Xs`).
   - Prints stage timing lines (as in existing `_render_timing_human`).
   - Then prints a `Test suite timing by stage:` section:
     ```
     Test suite timing by stage:
       Unit Tests A (wall 51s, agent6 guthrie):
         buildgit_status_follow.bats  2m 2s  (74 tests)
         buildgit_push.bats           1m 1s  (20 tests)
       Unit Tests B (wall 1m 50s, agent8_sixcore):
         nested_stages.bats           3m 29s  (50 tests)
     ```
   - Only stages present in `stage_tests_map_json` appear.
   - The wall time for the stage group header comes from `.parallelGroups[]` or the stage's own `durationMillis`.
   - The agent comes from `timing_json.stages[].agent` for the matching stage.

4. **Update `_render_timing_for_build`**:
   - When `TIMING_BY_STAGE == "true" && TIMING_TESTS == "true"`:
     - Call `fetch_stage_test_suites` (from Chunk 1) to get `stage_tests_map_json`.
     - Pass `stage_tests_map_json` to `_render_timing_by_stage_human` instead of `_render_timing_human`.
   - When `TIMING_BY_STAGE == "true" && TIMING_TESTS != "true"`: proceed as normal (ignore `--by-stage`).

5. **Update JSON output**: when `TIMING_JSON == "true"` and `TIMING_BY_STAGE == "true"`:
   - Add `"testsByStage": <stage_tests_map_json>` to the output object.

6. **Update `buildgit` help text** to add `--by-stage` to the `timing` command documentation.

#### Test Plan

**Test File:** `test/buildgit_timing.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `timing_by_stage_groups_suites_under_stage` | Output contains stage header before its suite list | Feature 1 §Specification |
| `timing_by_stage_shows_stage_wall_time_and_agent` | Stage header includes wall time and agent name | Feature 1 §Specification |
| `timing_by_stage_suite_line_has_duration_and_count` | Suite line has duration and test count | Feature 1 §Specification |
| `timing_by_stage_without_tests_flag_ignored` | `--by-stage` alone does not error; shows normal timing | Feature 1 §Requirements |
| `timing_by_stage_json_has_testsByStage_field` | JSON output has `testsByStage` keyed by stage name | Feature 1 §Requirements |
| `timing_by_stage_stage_with_no_tests_omitted` | Stages without JUnit results not shown in by-stage section | Feature 1 §Requirements |
| `timing_by_stage_framework_agnostic` | Suite names come from className/suite, no .bats assumption | Feature 1 §Requirements |

**Mocking Requirements:**
- Extend the existing `jenkins_api` / `jenkins_api_with_status` mock in `buildgit_timing.bats` to handle:
  - `wfapi/describe` returning `timing_stage_tests_wfapi_42.json` (with node ids)
  - `/execution/node/<id>/wfapi/testResults` returning fixture node test results

**Dependencies:** Chunk 1 (`stage_test_correlation.sh` must be present and sourced)

#### Implementation Log

- Updated [`jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh) to parse `--by-stage`, fetch stage-correlated suites only when combined with `--tests`, render a new `Test suite timing by stage:` human section, and include `testsByStage` in JSON output for by-stage runs.
- Updated [`jbuildmon/skill/buildgit/scripts/buildgit`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/buildgit) help text and [`jbuildmon/test/buildgit_routing.bats`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/buildgit_routing.bats) so the documented timing synopsis now includes `--by-stage`.
- Extended [`jbuildmon/test/buildgit_timing.bats`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/buildgit_timing.bats) with the seven chunk-specific cases and added stage-correlation fixtures [`jbuildmon/test/fixtures/timing_stage_tests_wfapi_42.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/timing_stage_tests_wfapi_42.json), [`jbuildmon/test/fixtures/timing_stage_tests_node_10_tests.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/timing_stage_tests_node_10_tests.json), and [`jbuildmon/test/fixtures/timing_stage_tests_node_11_tests.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/timing_stage_tests_node_11_tests.json).
- Key decision: the by-stage section preserves the existing top-level stage timing output, then appends correlated suites in pipeline stage order, omitting stages whose node-level test endpoint returns no suites while leaving `--by-stage` inert when `--tests` is absent.

---

### Chunk 4: Feature 3 — `buildgit timing --compare` and multi-build table

#### Description

Add a `--compare A B` flag to `buildgit timing` for side-by-side comparison of two builds with deltas. Also enhance `-n N` (without `--tests`) to render a compact multi-build timing table instead of repeating the single-build block. This chunk works entirely within the existing timing infrastructure and has no dependency on Chunk 1.

#### Spec Reference

See spec [Feature 3](./2026-03-11_build-optimization-diagnostics-spec.md#feature-3-build-timing-comparison) §Specification and §Requirements.

#### Dependencies

- None (uses existing `_render_timing_for_build` and `get_all_stages`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh` (modified)
- `jbuildmon/test/buildgit_timing.bats` (new tests appended)
- `jbuildmon/test/fixtures/timing_wfapi_parallel_40.json` (new fixture, or reuse sequential_40)

#### Implementation Details

1. **Add `--compare` option to `_parse_timing_options`**:
   ```bash
   --compare)
       TIMING_COMPARE=true
       if [[ -z "${2:-}" || -z "${3:-}" ]]; then
           _usage_error "--compare requires two build numbers"
       fi
       TIMING_COMPARE_A="$2"
       TIMING_COMPARE_B="$3"
       shift 3
       ;;
   ```
   Initialize `TIMING_COMPARE=false`, `TIMING_COMPARE_A=""`, `TIMING_COMPARE_B=""`.
   Validate that both values are integers (absolute) or relative (0, -N).

2. **Add `_render_timing_compare_human(timing_a_json, timing_b_json)`** function:
   - Collects all stage names across both builds (union).
   - Renders a fixed-width table:
     ```
     Timing comparison: Build #11 vs #14
                             #11        #14       Delta
     Total                 4m 33s     4m 21s     -12s
       Unit Tests A          48s        51s       +3s
       ...
     ```
   - Delta: positive → `+Xs`, negative → `-Xs`, zero → `0s`.
   - Uses `format_duration` or `format_stage_duration` helpers for each cell.
   - Parallel groups shown with their wall time; sequential stages shown individually.

3. **Add `_render_timing_compare_json(timing_a_json, timing_b_json)`** function:
   - Returns:
     ```json
     {
       "builds": [<timing_a>, <timing_b>],
       "deltas": {
         "total": -12000,
         "stages": {"Unit Tests A": 3000, "Unit Tests B": -14000}
       }
     }
     ```

4. **Add `_render_timing_multi_table_human(builds_array_json)`** function:
   - Prints a compact table with one row per build, columns per top-level stage/group.
   - Column headers are stage names, truncated to fit.
   - Each row: `#N  total  stageA  stageB  ...`
   - When `TIMING_TESTS == "true"`: print the multi-build table first, then fall through to detailed output for the latest build only (per spec §Requirements).

5. **Update `cmd_timing`**:
   - If `TIMING_COMPARE == "true"`:
     - Resolve both build numbers using `_resolve_timing_build_number`.
     - Fetch timing data for each with `_render_timing_for_build` (capture JSON).
     - Call compare render functions.
     - Skip the normal loop.
   - If `TIMING_COUNT > 1 && TIMING_TESTS == "false"`:
     - Fetch all N builds, accumulate JSON array, then call `_render_timing_multi_table_human`.
     - Keep existing behavior (N individual blocks) when `TIMING_TESTS == "true"` for backward compatibility, but prepend the multi-build table.

6. **Update `buildgit` help text** to document `--compare A B` and the updated `-n N` behavior.

#### Test Plan

**Test File:** `test/buildgit_timing.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `timing_compare_shows_both_build_numbers` | Output contains `Build #A vs #B` header | Feature 3 §Specification |
| `timing_compare_shows_delta_column` | Delta column present with +/- prefix | Feature 3 §Specification |
| `timing_compare_zero_delta_shown_as_0s` | When stages equal, delta shown as `0s` | Feature 3 §Requirements |
| `timing_compare_negative_delta_has_minus` | Improvement shown with `-` prefix | Feature 3 §Requirements |
| `timing_compare_positive_delta_has_plus` | Regression shown with `+` prefix | Feature 3 §Requirements |
| `timing_compare_json_has_builds_and_deltas` | JSON output has `builds[]` and `deltas` | Feature 3 §Requirements |
| `timing_n_without_tests_renders_table` | `-n 3` without `--tests` shows compact table | Feature 3 §Specification |
| `timing_n_with_tests_prepends_table` | `-n 3 --tests` shows table then detail for latest | Feature 3 §Requirements |
| `timing_compare_missing_stage_in_one_build` | Stage absent from one build shown as empty/0s | Feature 3 §Specification |

**Mocking Requirements:**
- Extend existing `jenkins_api` mock to serve build info and wfapi data for build numbers 40, 41, 42 (already available as `timing_build_info_40.json`, etc.).
- The `--compare` tests use builds 40 and 42 (or 41 and 42).

**Dependencies:** None (uses existing infrastructure)

#### Implementation Log

- Updated [`jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh) to add `--compare`, resolve relative compare build refs, split timing JSON assembly from rendering, render human/JSON compare output with signed deltas, and render the new multi-build timing table for `-n N`.
- Updated [`jbuildmon/skill/buildgit/scripts/buildgit`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/buildgit) and [`jbuildmon/test/buildgit_routing.bats`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/buildgit_routing.bats) so the help synopsis now documents `timing --compare <a> <b>` and the new compact table behavior examples.
- Extended [`jbuildmon/test/buildgit_timing.bats`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/buildgit_timing.bats) with compare-mode coverage, signed delta assertions, JSON delta validation, compact `-n` table assertions, and the `-n --tests` behavior that prepends the table but keeps detailed output for only the latest build.
- Key decisions: missing top-level stages render as `0s` in compare/table mode instead of `<1s`, delta cells always carry an explicit `+` or `-` sign, and `-n N --tests` now follows the parent spec requirement by showing the summary table first and detailed suite timing only for the newest build in the requested window.

---

### Chunk 5: Feature 4 — `buildgit pipeline` enriched with test suites

#### Description

Enrich `buildgit pipeline` output so each stage that ran tests includes a `testSuites` field (JSON) and a summary line (human output) showing suite count, test count, and cumulative duration. This chunk uses the shared correlation library from Chunk 1.

#### Spec Reference

See spec [Feature 4](./2026-03-11_build-optimization-diagnostics-spec.md#feature-4-test-to-stage-assignment-in-pipeline-output) §Specification and §Requirements.

#### Dependencies

- **Chunk 1** (`fetch_stage_test_suites` from `stage_test_correlation.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh` (modified)
- `jbuildmon/test/buildgit_pipeline.bats` (new tests appended)
- `jbuildmon/test/fixtures/pipeline_wfapi_42.json` (new fixture)
- `jbuildmon/test/fixtures/pipeline_blue_nodes_42.json` (new fixture)
- `jbuildmon/test/fixtures/pipeline_node_20_tests.json` (new fixture)
- `jbuildmon/test/fixtures/pipeline_node_21_tests.json` (new fixture)
- `jbuildmon/test/fixtures/pipeline_console_42.txt` (new fixture or reuse timing_console_42.txt)

#### Implementation Details

1. **Source `stage_test_correlation.sh`** in `cmd_pipeline.sh` (same pattern as Chunk 3 sources it in `cmd_timing.sh`).

2. **Update `_render_pipeline_for_build`**:
   - After classifying stages, call `fetch_stage_test_suites "$job_name" "$build_number"` to get `stage_tests_map_json`.
   - Pass `stage_tests_map_json` into `_enrich_pipeline_stages_with_tests`.

3. **Add `_enrich_pipeline_stages_with_tests(classified_json, stage_tests_map_json)`**:
   - Uses `jq` to walk the `stages` tree and add `testSuites` to nodes whose name appears in `stage_tests_map_json`.
   - For parallel `type=="parallel"` nodes, distribute test suites to matching branch nodes.
   - `testSuites` format per spec:
     ```json
     [{"name": "nested_stages", "tests": 50, "durationMs": 209000, "failures": 0}]
     ```
   - Stages without test data: `testSuites` field omitted (not set to `[]`).
   - Returns the enriched `classified_json`.

4. **Update `_render_pipeline_node_human`**:
   - For sequential stages (type `sequential`) that have `testSuites`:
     ```
     └─ Unit Tests B [fastnode] -- sequential
          6 suites, 156 tests, 5m 24s cumulative
     ```
   - Print the summary line indented one level deeper than the node connector.
   - `cumulative` duration = sum of `testSuites[].durationMs`.

5. **Ensure the enriched `testSuites` passes through `_render_pipeline_json`** without modification (already works via `jq '.'`).

6. **No new CLI flags are needed** — enrichment is automatic when test data is available.

#### Test Plan

**Test File:** `test/buildgit_pipeline.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `pipeline_human_shows_test_summary_for_stages_with_tests` | Output line showing `N suites, M tests` under stage | Feature 4 §Specification |
| `pipeline_human_omits_test_summary_for_stages_without_tests` | Build/Deploy stages have no test summary line | Feature 4 §Requirements |
| `pipeline_json_includes_testSuites_field` | `--json` output has `testSuites` array on stage | Feature 4 §Specification |
| `pipeline_json_testSuites_fields_correct` | Each suite has name, tests, durationMs | Feature 4 §Requirements |
| `pipeline_json_testSuites_omitted_when_no_tests` | Stages without tests have no `testSuites` key | Feature 4 §Requirements |
| `pipeline_json_testSuites_has_failures_count` | `failures` field present in testSuites entries | Feature 4 §Requirements |
| `pipeline_human_cumulative_duration_correct` | Cumulative duration = sum of suite durations | Feature 4 §Specification |
| `pipeline_enrich_no_test_data_returns_unchanged` | When correlation returns `{}`, pipeline output unchanged | Feature 4 §Requirements |

**Mocking Requirements:**
- Mock `jenkins_api` and `jenkins_api_with_status` in wrapper to handle:
  - `wfapi/describe` (stage list with ids) → `pipeline_wfapi_42.json`
  - Blue Ocean nodes → `pipeline_blue_nodes_42.json`
  - Console text → `pipeline_console_42.txt`
  - `/execution/node/<id>/wfapi/testResults` → `pipeline_node_20_tests.json` or `pipeline_node_21_tests.json`
  - Non-test stage nodes → 404

**Dependencies:** Chunk 1 (`stage_test_correlation.sh` must be present and sourced)

#### Implementation Log

- Updated [`jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh) to enrich classified pipeline stages with per-stage `testSuites` from the shared stage-correlation library and to render per-stage human summaries with suite count, test count, and cumulative duration.
- Added chunk-specific fixtures [`jbuildmon/test/fixtures/pipeline_wfapi_42.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/pipeline_wfapi_42.json), [`jbuildmon/test/fixtures/pipeline_blue_nodes_42.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/pipeline_blue_nodes_42.json), [`jbuildmon/test/fixtures/pipeline_node_20_tests.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/pipeline_node_20_tests.json), [`jbuildmon/test/fixtures/pipeline_node_21_tests.json`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/pipeline_node_21_tests.json), and [`jbuildmon/test/fixtures/pipeline_console_42.txt`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/fixtures/pipeline_console_42.txt) so pipeline tests do not depend on timing fixtures.
- Extended [`jbuildmon/test/buildgit_pipeline.bats`](/Users/gclaybur/dev/ralph1/.claude/worktrees/optimize-diag-v4/jbuildmon/test/buildgit_pipeline.bats) with chunk 5 coverage for human summaries, JSON `testSuites`, omission on non-test stages, failure counts, cumulative durations, and the no-test-data path.
- Key decisions: enrichment is recursive by stage name across both `children` and `branches`, stages without correlated test data omit `testSuites` entirely, and the human summary uses cumulative suite duration rather than stage wall time to match the spec.

---

## SPEC Workflow

**Parent spec:** `jbuildmon/specs/2026-03-11_build-optimization-diagnostics-spec.md`

Read `specs/CLAUDE.md` for full workflow rules. The workflow below applies to multi-chunk plan implementation.

### Per-Chunk Workflow (every chunk must follow these steps)

1. **Run all unit tests** before starting. Do not proceed if tests are failing.
   - Test runner: `jbuildmon/test/bats/bin/bats jbuildmon/test/` (do NOT use any bats from `$PATH`)
2. **Implement the chunk** as described in its Implementation Details section.
3. **Write or update unit tests** as described in the chunk's Test Plan section.
4. **Run all unit tests** and confirm they pass (both new and existing).
5. **Fill in the `#### Implementation Log`** for the chunk you implemented — summarize files changed, key decisions, and anything notable.
6. **Commit and push** using `buildgit push jenkins` with a commit message that includes the chunk number (e.g., `"chunk 3/5: implement stage-level test fetching"`).
7. **Verify** the Jenkins CI build succeeds with no test failures. If it fails, fix and push again.

### Finalize Workflow (after ALL chunks are complete)

After all chunks have been implemented, a finalize step runs automatically to complete the remaining SPEC workflow tasks. The finalize agent reads the entire plan file (including all Implementation Log entries) and performs:

1. **Update `CHANGELOG.md`** (at the repository root).
2. **Update `README.md`** (at the repository root) if CLI options or usage changed.
3. **Update `jbuildmon/skill/buildgit/SKILL.md`** if the changes affect the buildgit skill.
4. **Update `jbuildmon/skill/buildgit/references/reference.md`** if output format or available options changed.
5. **Update the spec file:** Change its `State:` field to `IMPLEMENTED` and add it to the spec index in `specs/README.md`.
6. **Handle referenced files:** If the spec lists files in its `References:` header, move those files to `specs/done-reports/` and update the reference paths in the spec.
7. **Update `CLAUDE.md` AND `README.md`** (at the repository root) if the output of `buildgit --help` changes in any way.
8. **Commit and push** using `buildgit push jenkins` and verify CI passes.
