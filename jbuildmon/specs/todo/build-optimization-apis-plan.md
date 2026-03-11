# Build Optimization API Commands — Implementation Plan

**Spec:** [build-optimization-apis-spec.md](./build-optimization-apis-spec.md)
**Created:** 2026-03-10

---

## Contents

- [x] **Chunk A: `buildgit agents` command**
- [x] **Chunk B: `buildgit queue` command**
- [x] **Chunk C: `buildgit timing` command**
- [x] **Chunk D: `buildgit pipeline` command**
- [ ] **Chunk E: Routing, sourcing, and help integration**
- [ ] **Chunk F: Skill and documentation updates**

---

## Chunk Detail

---

### Chunk A: `buildgit agents` command

#### Description

Implement `buildgit agents` to display Jenkins executor capacity grouped by label. Introduces two new Jenkins API endpoints not currently used by buildgit. Outputs both human-readable and JSON formats.

#### Spec Reference

See spec [Command 1: `buildgit agents`](./build-optimization-apis-spec.md#command-1-buildgit-agents) and [Implementation Notes](./build-optimization-apis-spec.md#implementation-notes).

#### Dependencies

- None (standalone command using `jenkins_api()` from `api_test_results.sh`, which already exists)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_agents.sh`
- `jbuildmon/test/buildgit_agents.bats`

#### Implementation Details

1. **Create `lib/buildgit/cmd_agents.sh`** with:
   - `_parse_agents_options()` — parse `--json`, `--label <name>`, `-v` from `$@`; set local vars `AGENTS_JSON=false`, `AGENTS_LABEL=""`, `AGENTS_VERBOSE=false`
   - `_fetch_computers()` — call `jenkins_api "/computer/api/json?tree=computer[displayName,assignedLabels[name],numExecutors,idle,offline,temporarilyOffline,executors[currentExecutable[url]]]"`. Return raw JSON.
   - `_fetch_label_info()` — takes label name arg; call `jenkins_api "/label/${label}/api/json"`. Return raw JSON.
   - `_build_agents_data()` — combines computer and label API data: for each unique label across all nodes, call `_fetch_label_info()` to get `totalExecutors`/`busyExecutors`/`idleExecutors`, and build per-label node list from computer data. Returns a structured associative-array-friendly format or a temp JSON file using `jq`.
   - `_render_agents_human()` — iterate labels, print human-readable block per the spec's output format. For each label: "Label: X", "  Nodes: N", "  Executors: T total, B busy, I idle", "  Node details: name  N executors  B busy  online/offline". With `-v`: append running job URL per executor.
   - `_render_agents_json()` — emit JSON per spec structure using `jq` or heredoc assembly.
   - `cmd_agents()` — entry point: parse options, validate `$JENKINS_URL`/`$JENKINS_USER_ID`/`$JENKINS_API_TOKEN` (call `verify_jenkins_connection`), fetch data, dispatch to render function.

2. **Label filtering with `--label <name>`:** when set, only process and display that one label. Pass label to `_build_agents_data()` to skip fetching all others.

3. **Agent label detection:** Node entries from `/computer/api/json` have `assignedLabels[{name}]`. For each node, collect all label names from `assignedLabels`. Build a map: label → list of nodes.

4. **Offline nodes:** Show `offline` status in node details; `offline: true` nodes contribute 0 to busy count but are listed.

#### Test Plan

**Test File:** `test/buildgit_agents.bats`

Setup: source `test_helper.bash`. Mock `jenkins_api()` in each test to return fixture JSON files from `test/fixtures/`. Use `run bash -c "... 3>&- 2>&1"` pattern per CLAUDE.md rules.

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `agents_human_readable_basic` | Two labels, multiple nodes — verify label headers, node counts, executor counts | Command 1 output |
| `agents_json_output` | `--json` flag — verify JSON structure has `labels`, `totalExecutors`, `totalBusy`, `totalIdle` keys | Command 1 `--json` |
| `agents_label_filter` | `--label fastnode` — only fastnode label appears in output | Command 1 `--label` |
| `agents_verbose_shows_job_urls` | `-v` flag with running executors — verify job URL in output | Command 1 `-v` |
| `agents_offline_node_shown` | Node with `offline: true` — shows "offline" status in node detail line | Command 1 output |
| `agents_empty_cluster` | No nodes in computer API response — outputs "No nodes found" or similar | Command 1 edge case |
| `agents_single_executor` | Single-executor node — no plural in output | Command 1 output |

**Mocking Requirements:**
- `jenkins_api()` — return fixture files for `/computer/api/json` and `/label/*/api/json`
- `verify_jenkins_connection()` — stub to return 0

**Dependencies:** None

---

### Chunk B: `buildgit queue` command

#### Description

Implement `buildgit queue` to display the current Jenkins build queue with wait reasons. Adds the full-queue listing endpoint (`/queue/api/json`) which is distinct from the per-item polling already used in `monitor_helpers.sh`.

#### Spec Reference

See spec [Command 4: `buildgit queue`](./build-optimization-apis-spec.md#command-4-buildgit-queue) and [Implementation Notes — Jenkins API endpoints to add](./build-optimization-apis-spec.md#jenkins-api-endpoints-to-add).

#### Dependencies

- None (uses existing `jenkins_api()`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_queue.sh`
- `jbuildmon/test/buildgit_queue.bats`

#### Implementation Details

1. **Create `lib/buildgit/cmd_queue.sh`** with:
   - `_parse_queue_options()` — parse `--json`, `-v` from `$@`
   - `_fetch_queue()` — call `jenkins_api "/queue/api/json?tree=items[id,stuck,blocked,buildable,why,inQueueSince,task[name,url]]"`. Return raw JSON.
   - `_format_queue_duration()` — convert epoch ms `inQueueSince` to human-readable "45s ago", "2m 3s ago", etc. Use `$(date +%s)` minus `(inQueueSince/1000)`.
   - `_render_queue_human()` — if no items: print "Queue: empty". Otherwise: "Queue: N items" then for each item: two-line block with job name + queue duration, indented "why" reason. With `-v`: include `stuck`/`blocked` flags.
   - `_render_queue_json()` — emit JSON per spec structure. Include `queuedDuration` as `$(date +%s%3N) - inQueueSince`.
   - `cmd_queue()` — entry point: parse options, validate credentials, fetch, dispatch render.

2. **Queue item job name extraction:** `task[name]` gives the leaf job name; for multibranch it may be a path. Display as-is since it matches how Jenkins identifies the job.

3. **Stuck/blocked flags in `-v` mode:** print "  [STUCK]" or "  [BLOCKED]" prefixes when those booleans are true.

#### Test Plan

**Test File:** `test/buildgit_queue.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `queue_empty` | API returns empty `items` array — prints "Queue: empty" | Command 4 output |
| `queue_one_item_human` | Single queued item — verify job name, duration, why reason | Command 4 output |
| `queue_multiple_items` | Two items — verify count header "Queue: 2 items" | Command 4 output |
| `queue_json_output` | `--json` — verify `items` array with required fields | Command 4 `--json` |
| `queue_verbose_stuck` | Item with `stuck: true`, `-v` — verify `[STUCK]` appears | Command 4 `-v` |
| `queue_verbose_blocked` | Item with `blocked: true`, `-v` — verify `[BLOCKED]` appears | Command 4 `-v` |
| `queue_quiet_period` | `why` contains "quiet period" text — renders correctly | Command 4 output |

**Mocking Requirements:**
- `jenkins_api()` — return fixture files for `/queue/api/json`
- `verify_jenkins_connection()` — stub to return 0

**Dependencies:** None

---

### Chunk C: `buildgit timing` command

#### Description

Implement `buildgit timing [build#]` to display per-stage and per-test-suite timing. Reuses existing `get_all_stages()`, `get_blue_ocean_nodes()`, and `_build_stage_agent_map()`. Adds a new test report timing query that extends the existing `testReport/api/json` call to include `duration` fields on suites and cases.

#### Spec Reference

See spec [Command 2: `buildgit timing`](./build-optimization-apis-spec.md#command-2-buildgit-timing-build) and [Implementation Notes — Jenkins API endpoints to add](./build-optimization-apis-spec.md#jenkins-api-endpoints-to-add).

#### Dependencies

- Existing functions from `api_test_results.sh`: `get_all_stages()`, `get_blue_ocean_nodes()`, `_build_stage_agent_map()`
- Existing function from `failure_analysis.sh`: `_detect_parallel_branches()`

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_timing.sh`
- `jbuildmon/test/buildgit_timing.bats`
- New test fixture files in `jbuildmon/test/fixtures/` for test report with duration

#### Implementation Details

1. **Create `lib/buildgit/cmd_timing.sh`** with:
   - `_parse_timing_options()` — parse positional `build#`, `--json`, `-n <count>`, `--tests`, `-v`
   - `_fetch_test_report_timing()` — call `jenkins_api "${job_path}/${build}/testReport/api/json?tree=duration,suites[name,duration,cases[className,name,duration,status]]"`. This is a new tree parameter not currently used; the existing call in `api_test_results.sh` only fetches pass/fail counts. Add a new function rather than modifying the existing one.
   - `_resolve_timing_build_number()` — resolve `0`/empty to last successful build via `jenkins_api "${job_path}/lastSuccessfulBuild/buildNumber"`. If explicit number given, use it directly.
   - `_get_parallel_group_for_stage()` — given stage name and Blue Ocean nodes, return the parent parallel group name or empty string for sequential stages. Use edge graph from Blue Ocean nodes.
   - `_identify_bottleneck()` — given a parallel group's stages and their durations, return the name of the slowest stage.
   - `_render_timing_human()` — print per spec format:
     - "Build #N — total Xm Ys"
     - "Sequential stages:" block
     - "Parallel group: Name (wall Xm Ys, bottleneck: StageName)" blocks
     - Each stage line: "  Name    duration    agent    (N files, M tests)" (← parenthetical only with `--tests`)
     - "Test suite timing (top 10 slowest):" block (only with `--tests`)
     - Mark bottleneck stage with "  ← slowest"
   - `_render_timing_json()` — emit JSON per spec structure including `stages[]`, `parallelGroups[]`, `testSuites[]`
   - `_render_timing_for_build()` — fetches all data for one build number and renders. Called by `cmd_timing()` for single and multi-build (`-n`) modes.
   - `cmd_timing()` — entry point: parse options, resolve build number(s), for `-n` loop over N builds oldest-first, call `_render_timing_for_build()` for each.

2. **Stage duration source:** Use `durationMillis` from `wfapi/describe` stages (available via `get_all_stages()`).

3. **Agent attribution:** Call `_build_stage_agent_map()` which parses console text to map stage names to node names. If agent not found, show blank.

4. **Test suite to stage mapping:** Test report suites don't inherently know which stage ran them. Infer by matching suite names against console text per stage, or leave `stage` field null if not determinable. The spec notes this field in JSON; if not determinable, omit it gracefully.

5. **`-n <count>` multi-build mode:** Resolve the latest N build numbers (descending from current) and render each. In human mode, separate builds with a blank line.

#### Test Plan

**Test File:** `test/buildgit_timing.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `timing_sequential_stages` | Build with only sequential stages — no "Parallel group" section | Command 2 output |
| `timing_parallel_group_bottleneck` | Parallel group — verify bottleneck stage marked "← slowest" | Command 2 output |
| `timing_total_duration` | Total build duration line "Build #N — total Xm Ys" | Command 2 output |
| `timing_tests_flag` | `--tests` — test suite section appears; without flag it does not | Command 2 `--tests` |
| `timing_tests_sorted` | `--tests` output — suites sorted by duration descending | Command 2 `--tests` |
| `timing_json_structure` | `--json` — verify `stages`, `parallelGroups`, `testSuites` keys present | Command 2 `--json` |
| `timing_json_bottleneck` | `--json` — `parallelGroups[].bottleneck` equals slowest stage name | Command 2 `--json` |
| `timing_last_successful_default` | No build# given — resolves to last successful build | Command 2 default |
| `timing_n_builds` | `-n 3` — output for 3 builds | Command 2 `-n` |
| `timing_no_test_report` | `testReport` API returns 404 — degrades gracefully (no test section) | Command 2 edge case |

**Mocking Requirements:**
- `jenkins_api()` — return fixtures for `wfapi/describe`, Blue Ocean nodes, `lastSuccessfulBuild/buildNumber`, `testReport/api/json` (with duration fields)
- `_build_stage_agent_map()` — mock to return known agent assignments

**Dependencies:** Existing `get_all_stages()`, `get_blue_ocean_nodes()`, `_build_stage_agent_map()`, `_detect_parallel_branches()`

---

### Chunk D: `buildgit pipeline` command

#### Description

Implement `buildgit pipeline [build#]` to show the full pipeline structure — stage hierarchy, parallelism, agent labels, and stage dependency graph. This is primarily an assembly of data already available from existing API calls; no new Jenkins endpoints are required.

#### Spec Reference

See spec [Command 3: `buildgit pipeline`](./build-optimization-apis-spec.md#command-3-buildgit-pipeline-build) and [Implementation Notes — Agent label detection](./build-optimization-apis-spec.md#agent-label-detection).

#### Dependencies

- Existing functions: `get_blue_ocean_nodes()`, `_get_nested_stages()`, `_detect_parallel_branches()`, `_build_stage_agent_map()` (from `json_output.sh` and `failure_analysis.sh`)
- Chunk A: `_fetch_computers()` is needed to cross-reference node name → label assignment

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/cmd_pipeline.sh`
- `jbuildmon/test/buildgit_pipeline.bats`

#### Implementation Details

1. **Create `lib/buildgit/cmd_pipeline.sh`** with:
   - `_parse_pipeline_options()` — parse positional `build#`, `--json`
   - `_resolve_pipeline_build_number()` — default to latest build (`lastBuild/buildNumber`)
   - `_build_node_label_map()` — call `_fetch_computers()` (from Chunk A or inline the API call here) and build a map from node name (e.g. `fastnode-1`) to its labels. Returns associative-array-like output (or a temp JSON file). Used to annotate stages with their agent label.
   - `_classify_stages()` — using Blue Ocean nodes and edges: classify each node as `sequential` or `parallel` (parallel = has sibling nodes with same parent). Return a list of stage objects with `{name, type, agentNode, agentLabel, children[]}`.
   - `_render_pipeline_human()` — print tree structure per spec format using box-drawing chars (`├─`, `└─`, `│`, `──`). Sequential stages shown as "Name [label] ── sequential". Parallel groups shown as "Name ── parallel fork (N branches)" with indented branches. Use agent label from `_build_node_label_map()`.
   - `_render_pipeline_json()` — emit JSON per spec: `{build, stages[], graph: {edges[]}}`. Each stage has `{name, type, agentLabel, agent}` or `{name, type, branches[]}` for parallel.
   - `cmd_pipeline()` — entry point: parse options, validate, resolve build, classify, render.

2. **Agent label vs node name:** `_build_stage_agent_map()` returns the actual node name (e.g., `fastnode-1`). Cross-reference with `_build_node_label_map()` to get the label (e.g., `fastnode`). If label lookup fails (node offline, unknown), fall back to showing the node name only.

3. **Graph edges in JSON:** Extract from Blue Ocean nodes `edges` field. Each edge is `{from: stageName, to: stageName}`. The parallel group itself is a virtual node; emit edges from parent sequential stage → group, then group → child sequential stage.

4. **If Blue Ocean API unavailable:** Fall back to `wfapi/describe` stages in order. Mark all as `sequential` with no parallel detection. Note in output: "(parallel structure unavailable)".

#### Test Plan

**Test File:** `test/buildgit_pipeline.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `pipeline_sequential_only` | All sequential stages — no parallel fork shown | Command 3 output |
| `pipeline_parallel_branch` | Pipeline with parallel group — shows "parallel fork (N branches)" | Command 3 output |
| `pipeline_agent_label` | Agent label in brackets after stage name — from node-label map | Command 3 output |
| `pipeline_json_structure` | `--json` — verify `stages`, `graph.edges` keys present | Command 3 `--json` |
| `pipeline_json_parallel_type` | `--json` — parallel stage has `type: "parallel"` with `branches[]` | Command 3 `--json` |
| `pipeline_json_sequential_type` | `--json` — sequential stage has `type: "sequential"` | Command 3 `--json` |
| `pipeline_unknown_agent_label` | Node not found in computer map — degrades gracefully (node name shown) | Command 3 edge case |
| `pipeline_human_matches_json` | Same build: parallel count in human output matches branches count in JSON | Command 3 spec |

**Mocking Requirements:**
- `jenkins_api()` — return fixtures for Blue Ocean nodes, `wfapi/describe`, `/computer/api/json`, `lastBuild/buildNumber`
- `_build_stage_agent_map()` — mock to return deterministic node→stage assignments

**Dependencies:** Chunk A (`_fetch_computers()` or inline `/computer/api/json` call)

---

### Chunk E: Routing, sourcing, and help integration

#### Description

Wire all four new commands into the main `buildgit` script: source the new command files, add dispatch cases, and update the `--help` output with the new commands and examples section. Add routing tests.

#### Spec Reference

See spec [Buildgit Help Integration](./build-optimization-apis-spec.md#buildgit-help-integration).

#### Dependencies

- Chunk A (`cmd_agents.sh` must exist)
- Chunk B (`cmd_queue.sh` must exist)
- Chunk C (`cmd_timing.sh` must exist)
- Chunk D (`cmd_pipeline.sh` must exist)

> **WARNING for ralph-loop:** Chunk E adds `source` lines to the main `buildgit` script. If any of A, B, C, or D is missing when Chunk E runs, `buildgit` will fail to start entirely. **Do not implement Chunk E until all of A, B, C, and D are complete.**

#### Produces

- Modified `jbuildmon/skill/buildgit/scripts/buildgit` (routing + help)
- `jbuildmon/test/buildgit_routing.bats` (new routing tests) or extend `jbuildmon/test/buildgit_args.bats`

#### Implementation Details

1. **Source new files** in the main `buildgit` script, near the existing `source` lines for buildgit lib files:
   ```bash
   source "$_LIB_DIR/buildgit/cmd_agents.sh"
   source "$_LIB_DIR/buildgit/cmd_queue.sh"
   source "$_LIB_DIR/buildgit/cmd_timing.sh"
   source "$_LIB_DIR/buildgit/cmd_pipeline.sh"
   ```

2. **Add dispatch cases** to the `main()` case statement:
   ```bash
   agents)   cmd_agents   "${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"}" ;;
   queue)    cmd_queue    "${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"}" ;;
   timing)   cmd_timing   "${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"}" ;;
   pipeline) cmd_pipeline "${COMMAND_ARGS[@]+"${COMMAND_ARGS[@]}"}" ;;
   ```

3. **Update `--help` output** — add to the Commands section:
   ```
   agents [--json] [--label <name>]
                       Show Jenkins executor capacity by label
   timing [build#] [--json] [--tests] [-n <count>]
                       Show per-stage and per-test-suite timing
   pipeline [build#] [--json]
                       Show pipeline structure (stages, parallelism, labels)
   queue [--json]      Show Jenkins build queue with wait reasons
   ```
   Add "Build optimization:" examples block per spec.

4. **Update `CLAUDE.md` and `README.md`** at the repository root to reflect the new commands in the `buildgit --help` output section. The CLAUDE.md embeds the full `--help` output; update that embedded block.

5. **Routing tests** — add to `test/buildgit_routing.bats` (create if doesn't exist):
   - Test that `buildgit agents` dispatches to `cmd_agents` (mock `cmd_agents` to echo a sentinel; verify it's called)
   - Same for `queue`, `timing`, `pipeline`

#### Test Plan

**Test File:** `test/buildgit_routing.bats` (create) or extend `test/buildgit_args.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `routing_agents_dispatched` | `buildgit agents` invokes `cmd_agents` | Help integration |
| `routing_queue_dispatched` | `buildgit queue` invokes `cmd_queue` | Help integration |
| `routing_timing_dispatched` | `buildgit timing` invokes `cmd_timing` | Help integration |
| `routing_pipeline_dispatched` | `buildgit pipeline` invokes `cmd_pipeline` | Help integration |
| `help_contains_agents` | `buildgit --help` output contains "agents" | Help integration |
| `help_contains_timing` | `buildgit --help` output contains "timing" | Help integration |
| `help_contains_pipeline` | `buildgit --help` output contains "pipeline" | Help integration |
| `help_contains_queue` | `buildgit --help` output contains "queue" | Help integration |
| `help_contains_optimization_section` | `buildgit --help` contains "Build optimization" examples | Help integration |

**Mocking Requirements:**
- Mock `cmd_agents`, `cmd_queue`, `cmd_timing`, `cmd_pipeline` as sentinel functions

**Dependencies:** Chunks A, B, C, D

---

### Chunk F: Skill and documentation updates

#### Description

Update the buildgit AI skill manifest and documentation to expose the four new commands to agents. Create the `build-optimization.md` reference file. Update CHANGELOG.md with the new feature.

#### Spec Reference

See spec [Skill Documentation Updates](./build-optimization-apis-spec.md#skill-documentation-updates).

#### Dependencies

- Chunk E (routing and help complete; full interface known)

#### Produces

- Modified `jbuildmon/skill/buildgit/SKILL.md`
- New `jbuildmon/skill/buildgit/references/build-optimization.md`
- Modified `CHANGELOG.md` (repository root)

#### Implementation Details

1. **Update `SKILL.md` frontmatter `description`** — append optimization triggers to the `description:` field per spec.

2. **Remove "When to Use This Skill" body section** from SKILL.md body (trigger info moves to frontmatter per skill-creator guidance). Add bullet to "What this skill does" section: "- analyzes build timing, executor capacity, pipeline structure, and queue contention to enable build optimization".

3. **Add new commands to Commands table** in SKILL.md — add 11 rows per spec covering `agents`, `agents --json`, `agents --label`, `timing`, `timing --tests`, `timing --tests --json`, `timing -n --json`, `pipeline`, `pipeline --json`, `queue`, `queue --json`.

4. **Add "Build Optimization" section** to SKILL.md body with quick-start 4-step list and link to `references/build-optimization.md`.

5. **Create `references/build-optimization.md`** with full 6-step optimization workflow per spec verbatim content (Steps 1–6 and Key constraints).

6. **Update CHANGELOG.md** using the `changelog-maintenance` skill. Document new feature: four new build optimization commands (`agents`, `timing`, `pipeline`, `queue`).

#### Test Plan

No bats tests for documentation. Verification steps:
- Read `SKILL.md` and confirm all 4 commands appear in Commands table
- Read `references/build-optimization.md` and confirm all 6 steps present
- Read `CHANGELOG.md` and confirm new entry exists
- Run `buildgit --help` and confirm "Build optimization:" examples section present

**Dependencies:** Chunk E
