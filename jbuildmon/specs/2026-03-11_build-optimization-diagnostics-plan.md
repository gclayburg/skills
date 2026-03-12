# Build Optimization Diagnostics Implementation Plan

This plan breaks down `jbuildmon/specs/todo/2026-03-11_build-optimization-diagnostics-spec.md` into
independent, implementable chunks. Features 1 and 4 share test-to-stage correlation logic (Chunk 1),
which is a prerequisite for both. Features 2 and 3 are fully independent.

---

## Contents

- [ ] **Chunk 1: Shared - Stage-Level Test Suite Fetching**
- [ ] **Chunk 2: Feature 2 - `buildgit agents --nodes`**
- [ ] **Chunk 3: Feature 3 - Build Timing Comparison and Trend Table**
- [ ] **Chunk 4: Feature 1 - `buildgit timing --tests --by-stage`**
- [ ] **Chunk 5: Feature 4 - Pipeline Test Suite Enrichment**

---

## Chunk Detail

### Chunk 1: Shared - Stage-Level Test Suite Fetching

#### Description

Implement a reusable function that maps test suites to the pipeline stage that published them,
using the Jenkins per-stage test report API. This shared logic is required by both Feature 1
(timing `--by-stage`) and Feature 4 (pipeline `testSuites` enrichment).

#### Spec Reference

See spec [Implementation Notes](../specs/todo/2026-03-11_build-optimization-diagnostics-spec.md#implementation-notes):
> Features 1 and 4 overlap in data source. Implementation should share the underlying
> test-report-to-stage correlation logic.

Also see Feature 1 Data Source section and Feature 4 Requirements.

#### Dependencies

- None (no other chunks required)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_stage_tests.sh`
- `jbuildmon/test/buildgit_stage_tests.bats`

#### Implementation Details

1. **Discover the per-stage test report endpoint** before writing code. The Jenkins Pipeline
   workflow API exposes stage-level test results. Verify by executing:
   ```bash
   curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
     "${JENKINS_URL}/job/${JOB_NAME}/${BUILD_NUMBER}/execution/node/${NODE_ID}/wfapi/testResults"
   ```
   If that returns 404, also try the Blue Ocean path:
   ```bash
   curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
     "${JENKINS_URL}/blue/rest/organizations/jenkins/pipelines/${JOB_NAME}/runs/${BUILD_NUMBER}/nodes/${NODE_ID}/steps/"
   ```
   Capture a successful response as a fixture file at
   `jbuildmon/test/fixtures/stage_test_results_node.json`.

2. **Implement `_fetch_stage_test_results(job_name, build_number, node_id)`** in the new file:
   - Query `/job/{job}/{build}/execution/node/{nodeId}/wfapi/testResults` via `jenkins_api_with_status`.
   - Return JSON array of test suite objects on HTTP 200.
   - Return `[]` on 404 (stage has no tests — expected for non-test stages).
   - Return error on other status codes.

3. **Implement `_build_stage_test_suite_map(job_name, build_number)`**:
   - Fetch all stages via `get_all_stages()` and Blue Ocean nodes via `get_blue_ocean_nodes()` to obtain node IDs.
   - For each stage node (leaf node in the Blue Ocean tree), call `_fetch_stage_test_results()`.
   - Aggregate suites per stage: `{name, tests, durationMs, failures (optional)}`.
   - Return a JSON object keyed by stage name:
     ```json
     {
       "Unit Tests A": [
         {"name": "buildgit_status_follow", "tests": 74, "durationMs": 122000, "failures": 0},
         ...
       ],
       "Unit Tests B": [...]
     }
     ```
   - Stages with no test results are omitted from the map.

4. **Match stage names between Blue Ocean node names and wfapi stage names** — they should be
   identical, but add a normalization step (trim whitespace) as a safety measure.

#### Test Plan

**Test File:** `test/buildgit_stage_tests.bats`

Create a wrapper script sourcing `jenkins-common.sh` and `api_stage_tests.sh`, with mocked
`jenkins_api_with_status` that returns fixture data.

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `fetch_stage_test_results_success` | Returns suites array for a node that has tests | Feature 1 Data Source |
| `fetch_stage_test_results_no_tests` | Returns empty array on HTTP 404 (non-test stage) | Feature 1 Data Source |
| `fetch_stage_test_results_error` | Returns error on unexpected HTTP status | Feature 1 Data Source |
| `build_stage_test_suite_map_groups_by_stage` | Returns map with suites grouped under each stage name | Feature 1 & 4 |
| `build_stage_test_suite_map_skips_empty_stages` | Stages with no tests are omitted from map | Feature 1 & 4 |
| `build_stage_test_suite_map_empty_build` | Returns `{}` when no stages or nodes available | Feature 1 & 4 |

**Mocking Requirements:**
- `jenkins_api_with_status` returns fixture JSON + HTTP code
- `get_all_stages` returns fixture wfapi/describe stages array
- `get_blue_ocean_nodes` returns fixture Blue Ocean nodes array

**Dependencies:** None

---

### Chunk 2: Feature 2 - `buildgit agents --nodes`

#### Description

Add a `--nodes` flag to `buildgit agents` that pivots the output from label-centric to
node-centric: each physical node appears once with all its labels, executor count, and
busy/idle status.

#### Spec Reference

See spec [Feature 2: Agent Node Label Overlap View](../specs/todo/2026-03-11_build-optimization-diagnostics-spec.md#feature-2-agent-node-label-overlap-view).

#### Dependencies

- None (fully independent)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh` (modified)
- `jbuildmon/test/buildgit_agents.bats` (modified — add new test cases)

#### Implementation Details

1. **Add `AGENTS_NODES` flag** to `_parse_agents_options()`:
   ```bash
   --nodes)
       AGENTS_NODES=true
       shift
       ;;
   ```
   Initialize `AGENTS_NODES=false` at top of `_parse_agents_options()`.

2. **Implement `_build_agents_nodes_data()`**:
   - Call `_fetch_computers()` to get all computer data.
   - Use `jq` to pivot: for each `computer[]` entry, extract `displayName`, `numExecutors`,
     busy executor count (from `executors[].currentExecutable.url`), offline status, and
     all label names from `assignedLabels[].name`.
   - Return JSON with a top-level `nodes` array:
     ```json
     {
       "nodes": [
         {
           "name": "agent1paton",
           "executors": 3,
           "busyExecutors": 0,
           "idleExecutors": 3,
           "online": true,
           "labels": ["agent1", "any", "dockernode", "palmeragent1", "patonlabel", "slownode"]
         },
         ...
       ]
     }
     ```
   - Sort nodes alphabetically by `name`.

3. **Implement `_render_agents_nodes_human()`**:
   - Iterate `nodes[]` sorted by name.
   - Print:
     ```
     Node: <name>  (<executors> executors, <busyExecutors> busy)
       Labels: <label1>, <label2>, ...
     ```
   - Blank line between nodes.
   - If a node is offline, show `(offline)` instead of executor counts.

4. **Update `_render_agents_json()`** to pass through new `nodes` array when `--nodes` is used.
   When `--nodes` is not used, JSON output is unchanged (no `nodes` key added).

5. **Update `cmd_agents()`**: after building data, branch on `AGENTS_NODES`:
   - If true, call `_build_agents_nodes_data()` → `_render_agents_nodes_human()` or
     `_render_agents_json()` with nodes data.

6. **Update usage output** in `buildgit` main script to document `--nodes` flag.

#### Test Plan

**Test File:** `test/buildgit_agents.bats` (add cases)

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `agents_nodes_shows_each_node_once` | Each physical node appears exactly once | Feature 2 Requirements |
| `agents_nodes_lists_all_labels` | All assigned labels shown per node | Feature 2 Requirements |
| `agents_nodes_sorted_alphabetically` | Nodes sorted by display name | Feature 2 Requirements |
| `agents_nodes_shows_executor_counts` | Executor count and busy/idle per node | Feature 2 Requirements |
| `agents_nodes_json_output` | `--nodes --json` includes `nodes` array with expected fields | Feature 2 Requirements |
| `agents_nodes_offline_node` | Offline node shown with offline indicator | Feature 2 Requirements |
| `agents_default_unchanged` | Without `--nodes`, existing label-centric output unchanged | Feature 2 Requirements |

**Mocking Requirements:**
- `jenkins_api` / `_fetch_computers` returns fixture with multi-label nodes
- Fixture should include at least one node with 3+ labels and one node that is offline

**Dependencies:** None

---

### Chunk 3: Feature 3 - Build Timing Comparison and Trend Table

#### Description

Add two related features to `buildgit timing`:
- **`--compare A B`**: side-by-side timing comparison of two builds with per-stage deltas.
- **`-n N` compact table**: when N > 1 and `--tests` is not used, render a compact
  multi-build stage timing table instead of N separate full outputs.

#### Spec Reference

See spec [Feature 3: Build Timing Comparison](../specs/todo/2026-03-11_build-optimization-diagnostics-spec.md#feature-3-build-timing-comparison).

#### Dependencies

- None (fully independent; builds on existing timing infrastructure in `cmd_timing.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh` (modified)
- `jbuildmon/test/buildgit_timing.bats` (modified — add new test cases)

#### Implementation Details

1. **Extend `_parse_timing_options()`** to recognize `--compare`:
   ```bash
   --compare)
       TIMING_COMPARE=true
       TIMING_COMPARE_A="${2:-}"
       TIMING_COMPARE_B="${3:-}"
       shift 3
       ;;
   ```
   Initialize `TIMING_COMPARE=false`, `TIMING_COMPARE_A=""`, `TIMING_COMPARE_B=""`.
   Validate that both A and B are provided and are valid build number arguments (absolute or relative).

2. **Implement `_resolve_build_number_arg(job_name, arg)`** — resolve absolute or relative build
   numbers (same logic as other commands use; refactor/share if a helper already exists).

3. **Implement `_render_timing_compare(job_name, build_a, build_b)`**:
   - Fetch `_render_timing_for_build()` data for both builds (reuse existing function, capture JSON).
   - Extract stage names (union of both builds' stages).
   - Compute delta per stage: `deltaMs = build_b_ms - build_a_ms`.
   - Format delta: `+Xs`, `-Xs`, `0s`.
   - Render header:
     ```
     Timing comparison: Build #A vs #B
                             #A         #B       Delta
     Total               4m 33s     4m 21s      -12s
       Build                 4s         4s        0s
       All Tests          4m 22s     4m 10s      -12s
         Unit Tests A        48s        51s       +3s
     ```
   - Column widths: right-align duration columns (10 chars), right-align delta (8 chars).
   - Stages shown in pipeline order (from build_b's stage order, fall back to build_a if stage missing in build_b).
   - Indentation mirrors parallel group nesting.

4. **Implement `_render_timing_trend_table(job_name, builds_json_array)`** for `-n N` compact output:
   - Accept array of per-build timing JSON objects (one per build, in ascending build-number order).
   - Collect all unique top-level stage names (sequential + parallel group names).
   - Render table:
     ```
     Build  Total   Unit A  Unit B  ...
     #10    4m 36s    51s   3m 28s  ...
     ```
   - Use wall duration for parallel groups (not sum of children).
   - Column width: max of header and widest value.
   - Maximum of 8 stage columns; if more stages exist, truncate with `...` column.

5. **Update `cmd_timing()` dispatch logic**:
   - If `TIMING_COMPARE=true`: call `_render_timing_compare()` (skip `-n` loop).
   - If `TIMING_COUNT > 1` and `TIMING_TESTS=false` and `TIMING_JSON=false`: collect timing
     JSON for all N builds, then call `_render_timing_trend_table()`.
   - If `TIMING_COUNT > 1` and `TIMING_TESTS=true`: render trend table first, then render
     per-suite timing for the latest build only.
   - All other cases: unchanged (single-build or JSON output).

6. **JSON output for `--compare`**: emit object with `builds` array (two full timing objects)
   and top-level `deltas` object: `{"stageName": deltaMs, ...}`.

7. **Update usage output** in `buildgit` main script to document `--compare` flag.

#### Test Plan

**Test File:** `test/buildgit_timing.bats` (add cases)

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `timing_compare_shows_both_builds` | Header shows both build numbers | Feature 3 |
| `timing_compare_positive_delta` | Slower stage shows `+Xs` | Feature 3 Requirements |
| `timing_compare_negative_delta` | Faster stage shows `-Xs` | Feature 3 Requirements |
| `timing_compare_zero_delta` | Unchanged stage shows `0s` | Feature 3 Requirements |
| `timing_compare_json_output` | `--compare --json` includes `builds[]` and `deltas` | Feature 3 Requirements |
| `timing_compare_missing_stage` | Stage present in one build but not other is shown with `--` | Feature 3 |
| `timing_n_trend_table_renders` | `-n 3` without `--tests` shows compact table | Feature 3 Requirements |
| `timing_n_trend_table_columns` | Table columns include Total + stage names | Feature 3 Requirements |
| `timing_n_with_tests_shows_table_then_suites` | `-n 3 --tests` renders table then suite detail for latest | Feature 3 Requirements |
| `timing_single_build_unchanged` | `-n 1` (default) renders same as before | Feature 3 |

**Mocking Requirements:**
- `jenkins_api` returns fixture data for multiple build numbers (use separate fixture files per build)
- `_fetch_test_report_timing` mocked for test-related cases

**Dependencies:** None

---

### Chunk 4: Feature 1 - `buildgit timing --tests --by-stage`

#### Description

Add a `--by-stage` flag to `buildgit timing` that groups test suites under the pipeline stage
that ran them, using the shared stage-test correlation library from Chunk 1.

#### Spec Reference

See spec [Feature 1: Test-to-Stage Mapping in Timing Output](../specs/todo/2026-03-11_build-optimization-diagnostics-spec.md#feature-1-test-to-stage-mapping-in-timing-output).

#### Dependencies

- **Chunk 1** (`_build_stage_test_suite_map` function from `api_stage_tests.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh` (modified)
- `jbuildmon/test/buildgit_timing.bats` (modified — add new test cases)

#### Implementation Details

1. **Source `api_stage_tests.sh`** at the top of `cmd_timing.sh` (or in the main entry point
   alongside other lib sources).

2. **Add `TIMING_BY_STAGE` flag** to `_parse_timing_options()`:
   ```bash
   --by-stage)
       TIMING_BY_STAGE=true
       shift
       ;;
   ```
   Initialize `TIMING_BY_STAGE=false`. When `--by-stage` is used without `--tests`, ignore
   silently (per spec).

3. **Extend `_render_timing_for_build()` to accept by-stage mode**:
   - When `TIMING_BY_STAGE=true` and `TIMING_TESTS=true`, call `_build_stage_test_suite_map()`
     to get the stage→suites map.
   - Pass the map to `_render_timing_human()` or a new `_render_timing_by_stage_human()`.

4. **Implement `_render_timing_by_stage_human(timing_json, stage_suite_map_json)`**:
   - Print the standard stage timing block (same as current output).
   - Then print a `Test suite timing by stage:` section.
   - For each stage that has suites in the map, print:
     ```
       Unit Tests A (wall 51s, agentName):
         buildgit_status_follow.bats  2m 2s  (74 tests)
         buildgit_push.bats           1m 1s  (20 tests)
     ```
   - Stage order follows pipeline order from `timing_json.stages`.
   - Within a stage, suites sorted by duration descending.
   - `agentName` from `timing_json.stages[].agent`.
   - `walltime` from `timing_json.stages[].durationMillis` (for parallel stages) or
     `timing_json.parallelGroups[].wallDurationMillis`.

5. **Extend JSON output**: when `TIMING_BY_STAGE=true`, add a `testsByStage` key to the
   timing JSON object:
   ```json
   "testsByStage": {
     "Unit Tests A": [
       {"name": "buildgit_status_follow", "tests": 74, "durationMs": 122000}
     ]
   }
   ```

6. **Update usage output** in `buildgit` main script to document `--by-stage` flag.

#### Test Plan

**Test File:** `test/buildgit_timing.bats` (add cases)

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `timing_by_stage_groups_suites_under_stage` | Each test suite appears under its stage header | Feature 1 Specification |
| `timing_by_stage_shows_wall_time_and_agent` | Stage header includes wall time and agent name | Feature 1 Specification |
| `timing_by_stage_suites_sorted_by_duration` | Within a stage, slowest suites appear first | Feature 1 Specification |
| `timing_by_stage_without_tests_ignored` | `--by-stage` alone (no `--tests`) shows standard output | Feature 1 Requirements |
| `timing_by_stage_json_includes_testsByStage` | JSON output includes `testsByStage` keyed by stage name | Feature 1 Requirements |
| `timing_by_stage_framework_agnostic` | Works with non-.bats suite names (Java class names) | Feature 1 Requirements |

**Mocking Requirements:**
- `_build_stage_test_suite_map` returns fixture stage→suites map JSON
- `_render_timing_for_build` pieces mocked to inject known stage/agent data

**Dependencies:** Chunk 1 (`_build_stage_test_suite_map`)

---

### Chunk 5: Feature 4 - Pipeline Test Suite Enrichment

#### Description

Enrich `buildgit pipeline` output with test suite data per stage. Each stage that ran JUnit
tests gains a `testSuites` field in JSON output and a test summary line in human output.

#### Spec Reference

See spec [Feature 4: Test-to-Stage Assignment in Pipeline Output](../specs/todo/2026-03-11_build-optimization-diagnostics-spec.md#feature-4-test-to-stage-assignment-in-pipeline-output).

#### Dependencies

- **Chunk 1** (`_build_stage_test_suite_map` function from `api_stage_tests.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh` (modified)
- `jbuildmon/test/buildgit_pipeline.bats` (modified — add new test cases)

#### Implementation Details

1. **Source `api_stage_tests.sh`** in `cmd_pipeline.sh` (or the main entry point).

2. **Call `_build_stage_test_suite_map()`** in `_render_pipeline_for_build()`:
   ```bash
   stage_suite_map_json=$(_build_stage_test_suite_map "$job_name" "$build_number")
   ```
   Pass the map to the `_classify_pipeline_stages()` result enrichment step.

3. **Enrich `_classify_pipeline_stages()` result**: after classifying stages, inject `testSuites`
   into each stage entry that has data in the suite map. The enrichment is a post-processing
   step on the returned `stages` array using `jq`:
   ```bash
   classified_json=$(printf '%s\n' "$classified_json" | jq \
       --argjson suite_map "$stage_suite_map_json" '
       .stages |= map(
           (.name as $name
           | if ($suite_map[$name] // []) | length > 0 then
               . + {testSuites: $suite_map[$name]}
             else
               .
             end)
       )
   ')
   ```
   Apply this recursively for nested `branches` and `children` nodes using a jq `def walk`.

4. **Update `_render_pipeline_node_human()`**: for `type == "sequential"` nodes that have
   `testSuites` field, print an additional summary line:
   ```
   └─ Unit Tests B [fastnode] -- sequential
        Tests: 6 suites, 156 tests, 5m 24s cumulative
   ```
   - `cumulative` = sum of all suite `durationMs` values.
   - Indent summary line under the stage line.

5. **JSON output**: `testSuites` array per-stage includes `name`, `tests`, `durationMs`,
   and `failures` (omit `failures` key when 0 or absent). Stages without JUnit results
   omit the `testSuites` key entirely (per spec).

#### Test Plan

**Test File:** `test/buildgit_pipeline.bats` (add cases)

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `pipeline_test_suites_in_json_output` | Stages with tests include `testSuites` array in JSON | Feature 4 Requirements |
| `pipeline_test_suites_have_required_fields` | Each suite has `name`, `tests`, `durationMs` | Feature 4 Requirements |
| `pipeline_no_test_suites_key_for_non_test_stage` | Build/Deploy stages omit `testSuites` key | Feature 4 Requirements |
| `pipeline_human_shows_test_summary_line` | Human output shows suite/test count and cumulative time | Feature 4 Specification |
| `pipeline_nested_stage_test_suites` | Test suites enriched on nested branch stages | Feature 4 Requirements |
| `pipeline_failures_count_in_testSuites` | `failures` field present when > 0 | Feature 4 Requirements |
| `pipeline_json_without_tests_unchanged` | Builds with no JUnit results produce unchanged pipeline JSON | Feature 4 Requirements |

**Mocking Requirements:**
- `_build_stage_test_suite_map` returns fixture map with data for subset of stages
- Fixture should include at least one stage with failures and one stage with no tests

**Dependencies:** Chunk 1 (`_build_stage_test_suite_map`)

---

## Implementation Notes

- Chunks 2 and 3 are fully independent and can be implemented in any order or in parallel.
- Chunk 1 must be completed before Chunks 4 and 5.
- All tests use bats-core located at `jbuildmon/test/bats/bin/bats`.
- Always run with `--jobs $(nproc)` for parallel test execution.
- New Jenkins API calls must be mocked in unit tests — no real network access in tests.
- When adding flags, also update:
  - `buildgit --help` usage text in the main `buildgit` script
  - `jbuildmon/skill/buildgit/references/reference.md`
  - `CHANGELOG.md` and `README.md`

## References

- Full specification: `jbuildmon/specs/todo/2026-03-11_build-optimization-diagnostics-spec.md`
- Timing command: `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh`
- Agents command: `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh`
- Pipeline command: `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh`
- Existing test API lib: `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh`
- Existing test files: `jbuildmon/test/buildgit_timing.bats`, `jbuildmon/test/buildgit_agents.bats`, `jbuildmon/test/buildgit_pipeline.bats`
