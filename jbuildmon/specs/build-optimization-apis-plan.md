# Implementation Plan: Build Optimization API Commands

**Parent spec:** `jbuildmon/specs/todo/build-optimization-apis-spec.md`

## Contents

- [x] **Chunk 1: `buildgit agents` command**
- [x] **Chunk 2: `buildgit queue` command**
- [x] **Chunk 3: `buildgit timing` command**
- [x] **Chunk 4: `buildgit pipeline` command**
- [x] **Chunk 5: Routing, help text, and documentation updates**
- [ ] **Chunk 6: Integration test smoke tests**


## Chunk Detail

### Chunk 1: `buildgit agents` command

#### Description

Implement `cmd_agents.sh` — queries `/computer/api/json` and `/label/<name>/api/json`, formats human-readable and JSON output, and supports `--label` filtering and `-v` verbose mode showing running job URLs per executor.

#### Spec Reference

See spec [Command 1: `buildgit agents`](./todo/build-optimization-apis-spec.md#command-1-buildgit-agents).

#### Dependencies

- None (only depends on existing `jenkins_api()` infrastructure in `jenkins-common.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh`
- `jbuildmon/test/buildgit_agents.bats`

#### Implementation Details

1. Parse options (`--json`, `--label <name>`, `-v`/`--verbose`).
2. Fetch `/computer/api/json` with full executor tree.
3. If `--label` provided, also fetch `/label/<name>/api/json` for the per-label summary.
4. Group nodes by their `assignedLabels` and compute totals (totalExecutors, busyExecutors, idleExecutors).
5. Render human-readable label-grouped output or emit JSON matching the spec schema.

#### Test Plan

**Test File:** `test/buildgit_agents.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `agents_human_readable_basic` | Default output shows label, node count, executor counts | Command 1 – Human output |
| `agents_json_output` | `--json` emits valid JSON with labels/totals keys | Command 1 – JSON output |
| `agents_label_filter` | `--label` restricts output to that label | Command 1 – Flags |
| `agents_verbose_shows_job_urls` | `-v` includes currently-running job URLs | Command 1 – Flags |
| `agents_offline_node_shown` | Offline nodes appear with offline indicator | Command 1 – Human output |
| `agents_empty_cluster` | Zero-node response emits sensible empty output | Command 1 – Human output |
| `agents_single_executor` | Single-executor node renders correctly | Command 1 – Human output |

**Mocking Requirements:**
- `jenkins_api()` stubbed to return fixture JSON for `/computer/api/json` and `/label/*/api/json`

**Dependencies:** None (self-contained command)

#### Implementation Log

Command implemented in `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh` (304 lines). Unit tests implemented in `jbuildmon/test/buildgit_agents.bats` (165 lines, 8 test cases). All tests pass.

---

### Chunk 2: `buildgit queue` command

#### Description

Implement `cmd_queue.sh` — queries `/queue/api/json` with the full item tree, formats human-readable wait-reason output and JSON, and supports `--json` and `-v` verbose flags.

#### Spec Reference

See spec [Command 4: `buildgit queue`](./todo/build-optimization-apis-spec.md#command-4-buildgit-queue).

#### Dependencies

- None (only depends on existing `jenkins_api()` infrastructure)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_queue.sh`
- `jbuildmon/test/buildgit_queue.bats`

#### Implementation Details

1. Parse options (`--json`, `-v`/`--verbose`).
2. Fetch `/queue/api/json?tree=items[id,stuck,blocked,buildable,why,inQueueSince,task[name,url]]`.
3. Compute elapsed queue time from `inQueueSince` ms epoch.
4. Render human-readable "Queue: N items" list or emit JSON array of items.
5. Handle empty queue case with "Queue: empty" message.

#### Test Plan

**Test File:** `test/buildgit_queue.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `queue_empty` | Empty queue produces "Queue: empty" output | Command 4 – Human output |
| `queue_one_item_human` | Single queued item shows job name and wait reason | Command 4 – Human output |
| `queue_multiple_items` | Multiple items all displayed | Command 4 – Human output |
| `queue_json_output` | `--json` emits items array with correct fields | Command 4 – JSON output |
| `queue_verbose_stuck` | `-v` shows stuck=true flag | Command 4 – Flags |
| `queue_verbose_blocked` | `-v` shows blocked=true flag | Command 4 – Flags |
| `queue_quiet_period` | Quiet-period reason displayed correctly | Command 4 – Human output |

**Mocking Requirements:**
- `jenkins_api()` stubbed to return fixture JSON for `/queue/api/json`

**Dependencies:** None (self-contained command)

#### Implementation Log

Command implemented in `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_queue.sh` (163 lines). Unit tests implemented in `jbuildmon/test/buildgit_queue.bats` (132 lines, 7 test cases). All tests pass.

---

### Chunk 3: `buildgit timing` command

#### Description

Implement `cmd_timing.sh` — merges wfapi stage data, Blue Ocean parallel-group structure, and testReport `duration` fields to produce per-stage timing with bottleneck identification and optional per-test-suite breakdown.

#### Spec Reference

See spec [Command 2: `buildgit timing`](./todo/build-optimization-apis-spec.md#command-2-buildgit-timing-build).

#### Dependencies

- Reuses `get_all_stages()`, `get_blue_ocean_nodes()`, `_build_stage_agent_map()` from existing library code.
- Extends test-report fetch (`api_test_results.sh`) to include `duration` fields in the tree parameter.

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh`
- `jbuildmon/test/buildgit_timing.bats`

#### Implementation Details

1. Parse options (`build#`, `--json`, `-n <count>`, `--tests`).
2. Resolve build number (default: last successful build via wfapi).
3. Fetch wfapi stage list and Blue Ocean nodes for parallel-group edges.
4. Group stages into parallel groups; identify bottleneck (slowest branch).
5. If `--tests`, fetch `testReport/api/json?tree=duration,suites[name,duration,cases[...]]` and join suite timing to their parent stage.
6. Render tabular human-readable output (sequential stages, parallel groups with `← slowest` markers, top-10 test suites) or emit JSON.

#### Test Plan

**Test File:** `test/buildgit_timing.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `timing_sequential_stages` | Sequential stages listed with duration and agent | Command 2 – Human output |
| `timing_parallel_group_bottleneck` | Bottleneck branch identified with `← slowest` | Command 2 – Human output |
| `timing_total_duration` | Total build duration shown in header | Command 2 – Human output |
| `timing_tests_flag` | `--tests` adds test suite timing section | Command 2 – Flags |
| `timing_tests_sorted` | Test suites sorted slowest-first | Command 2 – Human output |
| `timing_json_structure` | `--json` emits build, stages, parallelGroups, testSuites | Command 2 – JSON output |
| `timing_json_bottleneck` | JSON parallelGroups includes `bottleneck` field | Command 2 – JSON output |
| `timing_last_successful_default` | No build# defaults to last successful | Command 2 – Flags |
| `timing_n_builds` | `-n 3` fetches and outputs 3 builds | Command 2 – Flags |
| `timing_no_test_report` | Missing test report handled gracefully | Command 2 – Human output |

**Mocking Requirements:**
- `jenkins_api()` stubbed for wfapi, Blue Ocean nodes, and testReport endpoints

**Dependencies:** Chunk 1 infrastructure not required; reuses existing library functions.

#### Implementation Log

Command implemented in `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh` (404 lines). Unit tests implemented in `jbuildmon/test/buildgit_timing.bats` (251 lines, 10 test cases). All tests pass.

---

### Chunk 4: `buildgit pipeline` command

#### Description

Implement `cmd_pipeline.sh` — assembles pipeline topology from Blue Ocean node graph and wfapi stage metadata to show stage hierarchy (sequential vs parallel), agent labels, and the dependency edge graph.

#### Spec Reference

See spec [Command 3: `buildgit pipeline`](./todo/build-optimization-apis-spec.md#command-3-buildgit-pipeline-build).

#### Dependencies

- Reuses `get_blue_ocean_nodes()`, `_get_nested_stages()`, `_detect_parallel_branches()`, `_build_stage_agent_map()`.

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh`
- `jbuildmon/test/buildgit_pipeline.bats`

#### Implementation Details

1. Parse options (`build#`, `--json`).
2. Fetch Blue Ocean nodes (edge graph) and wfapi stage metadata.
3. Detect parallel forks from Blue Ocean edges.
4. Cross-reference agent node names with `/computer/api/json` to resolve labels.
5. Render tree-style human-readable output with `──`, `├─`, `└─` connectors, or emit JSON with `stages`, `graph.edges` keys.

#### Test Plan

**Test File:** `test/buildgit_pipeline.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `pipeline_sequential_only` | All-sequential pipeline renders as flat list | Command 3 – Human output |
| `pipeline_parallel_branch` | Parallel fork renders with tree connectors | Command 3 – Human output |
| `pipeline_agent_label` | Agent label shown in brackets per stage | Command 3 – Human output |
| `pipeline_json_structure` | `--json` emits stages and graph.edges | Command 3 – JSON output |
| `pipeline_json_parallel_type` | Parallel stages have `"type": "parallel"` | Command 3 – JSON output |
| `pipeline_json_sequential_type` | Sequential stages have `"type": "sequential"` | Command 3 – JSON output |
| `pipeline_unknown_agent_label` | Unknown agent label shows placeholder | Command 3 – Human output |
| `pipeline_human_matches_json` | Human and JSON outputs describe same stages | Command 3 – Consistency |

**Mocking Requirements:**
- `jenkins_api()` stubbed for Blue Ocean nodes, wfapi describe, and `/computer/api/json`

**Dependencies:** Agent-label cross-reference logic shares fixture with Chunk 1 tests.

#### Implementation Log

Command implemented in `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh` (327 lines). Unit tests implemented in `jbuildmon/test/buildgit_pipeline.bats` (186 lines, 8 test cases). All tests pass.

---

### Chunk 5: Routing, help text, and documentation updates

#### Description

Wire the four new commands into the `buildgit` dispatch table, update `--help` output, add routing unit tests, update `SKILL.md` (frontmatter description, commands table, build optimization section), create `references/build-optimization.md`, and update `CHANGELOG.md` and `README.md`.

#### Spec Reference

See spec [Buildgit Help Integration](./todo/build-optimization-apis-spec.md#buildgit-help-integration) and [Skill Documentation Updates](./todo/build-optimization-apis-spec.md#skill-documentation-updates).

#### Dependencies

- Chunks 1–4 (all four commands must exist before routing and help can be finalized)

#### Produces

- `jbuildmon/skill/buildgit/scripts/buildgit` (routing + help text changes)
- `jbuildmon/skill/buildgit/SKILL.md`
- `jbuildmon/skill/buildgit/references/build-optimization.md`
- `jbuildmon/test/buildgit_routing.bats` (routing and help-text tests)
- `CHANGELOG.md`
- `README.md`

#### Implementation Details

1. Add `source` lines for `cmd_agents.sh`, `cmd_queue.sh`, `cmd_timing.sh`, `cmd_pipeline.sh` in `buildgit`.
2. Add dispatch cases for `agents`, `timing`, `pipeline`, `queue` in the main command switch.
3. Update `--help` output: add the four new commands to the Commands block and add a "Build optimization" examples section.
4. Update `SKILL.md` frontmatter `description`, commands table, and add "Build Optimization" body section.
5. Create `references/build-optimization.md` with the full 6-step optimization workflow.
6. Add routing dispatch tests and help-text assertion tests to `buildgit_routing.bats`.
7. Add entry to `CHANGELOG.md`; update `README.md` to reflect `buildgit --help` changes.

#### Test Plan

**Test File:** `test/buildgit_routing.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `routing_agents_dispatched` | `buildgit agents` calls `cmd_agents` | Routing |
| `routing_queue_dispatched` | `buildgit queue` calls `cmd_queue` | Routing |
| `routing_timing_dispatched` | `buildgit timing` calls `cmd_timing` | Routing |
| `routing_pipeline_dispatched` | `buildgit pipeline` calls `cmd_pipeline` | Routing |
| `help_contains_agents` | `--help` output includes agents command line | Help Integration |
| `help_contains_timing` | `--help` output includes timing command line | Help Integration |

**Mocking Requirements:**
- Routing tests stub `cmd_agents`, `cmd_queue`, `cmd_timing`, `cmd_pipeline` with echo functions.

**Dependencies:** Chunks 1–4

#### Implementation Log

Routing (`source` lines + dispatch cases) added to `jbuildmon/skill/buildgit/scripts/buildgit`. Help text updated with four new commands and "Build optimization" examples block. Routing and help tests added to `jbuildmon/test/buildgit_routing.bats`. `SKILL.md` updated: frontmatter description extended, commands table has 11 new rows, new "Build Optimization" section added with 4-step quick start. `references/build-optimization.md` created with full 6-step workflow. `CHANGELOG.md` updated. `README.md` updated to match new `--help` output. All tests pass.

---

### Chunk 6: Integration test smoke tests

#### Description

Extend `test/integration/integration_tests.bats` with basic smoke tests for all four new commands against the real Jenkins server. Each test calls the command and verifies non-empty, parseable output — ensuring the API endpoints are reachable and the output is structurally valid.

#### Spec Reference

See spec [Integration tests](./todo/build-optimization-apis-spec.md#integration-tests).

#### Dependencies

- Chunks 1–5 (all commands must be routed and working)
- Real Jenkins server accessible via `$JENKINS_URL`, `$JENKINS_USER_ID`, `$JENKINS_API_TOKEN`

#### Produces

- `jbuildmon/test/integration/integration_tests.bats` (new test cases appended)

#### Implementation Details

1. Add `@test "integration_agents_returns_output"`:
   - Run `buildgit agents` (no flags); assert exit 0 and non-empty stdout.
2. Add `@test "integration_agents_json_parseable"`:
   - Run `buildgit agents --json`; pipe to `jq .labels`; assert exit 0.
3. Add `@test "integration_queue_returns_output"`:
   - Run `buildgit queue`; assert exit 0 (output may be "Queue: empty" — that is valid).
4. Add `@test "integration_queue_json_parseable"`:
   - Run `buildgit queue --json`; pipe to `jq .items`; assert exit 0.
5. Add `@test "integration_timing_returns_output"`:
   - Run `buildgit timing`; assert exit 0 and non-empty stdout.
6. Add `@test "integration_timing_json_parseable"`:
   - Run `buildgit timing --json`; pipe to `jq .stages`; assert exit 0.
7. Add `@test "integration_pipeline_returns_output"`:
   - Run `buildgit pipeline`; assert exit 0 and non-empty stdout.
8. Add `@test "integration_pipeline_json_parseable"`:
   - Run `buildgit pipeline --json`; pipe to `jq .stages`; assert exit 0.

All tests must fail (not skip) if Jenkins credentials are unavailable, per project testing conventions.

#### Test Plan

**Test File:** `test/integration/integration_tests.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `integration_agents_returns_output` | `buildgit agents` exits 0 with non-empty stdout | Integration tests |
| `integration_agents_json_parseable` | `buildgit agents --json` produces valid JSON with `.labels` key | Integration tests |
| `integration_queue_returns_output` | `buildgit queue` exits 0 (empty queue is valid) | Integration tests |
| `integration_queue_json_parseable` | `buildgit queue --json` produces valid JSON with `.items` key | Integration tests |
| `integration_timing_returns_output` | `buildgit timing` exits 0 with non-empty stdout | Integration tests |
| `integration_timing_json_parseable` | `buildgit timing --json` produces valid JSON with `.stages` key | Integration tests |
| `integration_pipeline_returns_output` | `buildgit pipeline` exits 0 with non-empty stdout | Integration tests |
| `integration_pipeline_json_parseable` | `buildgit pipeline --json` produces valid JSON with `.stages` key | Integration tests |

**Mocking Requirements:**
- None — integration tests call real Jenkins API endpoints.

**Dependencies:** Chunks 1–5; Jenkins credentials in environment.

#### Implementation Log

<!-- Filled in by the implementing agent after completing this chunk.
     Summarize: files changed, key decisions, anything the finalize step needs to know. -->


## SPEC Workflow

**Parent spec:** `jbuildmon/specs/todo/build-optimization-apis-spec.md`

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
