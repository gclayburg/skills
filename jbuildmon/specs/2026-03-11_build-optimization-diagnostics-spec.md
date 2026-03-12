## Build Optimization Diagnostics

- **Date:** `2026-03-11T17:09:09-0600`
- **References:** `specs/done-reports/rebalance-build.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

### Background

During a hands-on build optimization session, the `buildgit` tool proved sufficient for all diagnostic needs — no direct Jenkins API calls were required. However, several workflow gaps emerged that forced manual cross-referencing of timing data, Jenkinsfile contents, and agent configurations. These features would make `buildgit` a more effective tool for build optimization work.

The four features below address the gaps identified. They are independent of each other and can be implemented in any order.

### Feature 1: Test-to-Stage Mapping in Timing Output

**Problem:** `buildgit timing --tests` shows per-test-suite cumulative durations but does not indicate which pipeline stage ran each suite. During rebalancing, the operator must read the Jenkinsfile to determine group assignments.

**Specification:**

Add a `--by-stage` flag to `buildgit timing`:

```
buildgit timing --tests --by-stage
```

Output groups test suites under their parent stage:

```
Build #14 - total 4m 21s
...
Test suite timing by stage:
  Unit Tests A (wall 51s, sixcore):
    buildgit_status_follow.bats  2m 2s  (74 tests)
    buildgit_push.bats           1m 1s  (20 tests)
    ...
  Unit Tests B (wall 1m 50s, fastnode):
    nested_stages.bats           3m 29s  (50 tests)
    ...
```

**Data source:** JUnit XML reports are published per-stage. The Jenkins API exposes test results at the build level via `/testReport/api/json`. Each test case includes its `className` which maps to the originating `.bats` file (or test class in other frameworks). Stage association can be derived by correlating test suite names with the stage that published them, or by querying per-stage test report endpoints if available.

**Requirements:**
- Must work with any test framework that produces JUnit XML reports (not just bats-core).
- The `className` or `suite` field in JUnit results is used to group tests — no assumption about `.bats` file extensions.
- When `--by-stage` is used without `--tests`, it is ignored (or shows stage timing only, same as default).
- JSON output (`--json`) includes a `testsByStage` object keyed by stage name.

### Feature 2: Agent Node Label Overlap View

**Problem:** `buildgit agents` shows each label and its member nodes, but does not reveal which agents belong to multiple labels. During optimization, understanding label overlap is critical — e.g., assigning tests to `dockernode` may still contend with `fastnode` stages if both labels include the same physical agents.

**Specification:**

Add a `--nodes` flag to `buildgit agents`:

```
buildgit agents --nodes
```

Output shows each physical node with all its labels:

```
Node: agent6 guthrie  (3 executors, 0 busy)
  Labels: agent6, dockernode, fastnode, guthrie

Node: agent8_sixcore  (3 executors, 0 busy)
  Labels: agent8_sixcore, fastnode, fullspeed, sixcore

Node: agent1paton  (3 executors, 0 busy)
  Labels: agent1, any, dockernode, palmeragent1, patonlabel, slownode
```

**Requirements:**
- Each node appears once with all its labels listed.
- Nodes sorted alphabetically by display name.
- Executor count and busy/idle status shown per node (same data as current `agents` output, just pivoted).
- `--json` output includes a `nodes` array with `name`, `executors`, `busy`, `labels[]` per node.
- The existing label-centric view (`buildgit agents` without `--nodes`) remains unchanged.

### Feature 3: Build Timing Comparison

**Problem:** When iterating on build optimizations, the operator must manually compare `buildgit timing` output across builds to assess whether changes helped. There is no built-in way to see timing trends or deltas.

**Specification:**

Add a `--compare` flag to `buildgit timing`:

```
buildgit timing --compare 11 14
```

Output shows side-by-side stage timing with deltas:

```
Timing comparison: Build #11 vs #14
                        #11        #14       Delta
Total                 4m 33s     4m 21s     -12s
  Build                  4s         4s        0s
  All Tests           4m 22s     4m 10s     -12s
    Unit Tests A        48s        51s       +3s
    Unit Tests B      2m 4s      1m 50s     -14s
    Unit Tests C      1m 55s     1m 55s       0s
    Unit Tests D      2m 25s     2m 0s      -25s
    Integration       4m 22s     4m 10s     -12s
  Deploy                 4s         4s        0s
```

Also support trend view:

```
buildgit timing -n 5
```

Shows a compact timing summary across the last N builds (stage wall times only, no test detail):

```
Build  Total   Unit A  Unit B  Unit C  Unit D  Integration  Deploy
#10    4m 36s    51s   3m 28s  1m 39s  4m 5s     4m 25s       4s
#11    4m 33s    48s   2m 4s   1m 55s  2m 25s    4m 22s       4s
#12    4m 52s    51s   1m 49s  1m 55s  1m 58s    4m 40s       4s
#13    4m 51s   1m 0s  1m 49s  1m 55s  1m 57s    4m 40s       4s
#14    4m 21s    51s   1m 50s  1m 55s  2m 0s     4m 10s       4s
```

**Requirements:**
- `--compare A B` accepts two build numbers (absolute or relative). Shows per-stage deltas.
- `-n N` without `--tests` shows a compact multi-build timing table.
- `-n N` with `--tests` shows per-test-suite timing for the latest build only (current behavior), preceded by the multi-build stage table.
- `--json` output for `--compare` includes `builds[]` with full timing for both, plus `deltas` object.
- Delta formatting: positive values prefixed with `+`, negative with `-`, zero shown as `0s`.

### Feature 4: Test-to-Stage Assignment in Pipeline Output

**Problem:** `buildgit pipeline --json` shows the pipeline graph structure (stages, parallelism, agent labels) but does not include which test suites each stage executed. For data-driven rebalancing, the operator needs to see both the pipeline structure and the test workload per stage in a single query.

**Specification:**

Add test result data to `buildgit pipeline` output:

```
buildgit pipeline --json
```

The existing `stages` array gains a `testSuites` field per stage (when JUnit results are available):

```json
{
  "name": "Unit Tests B",
  "type": "parallel",
  "agent": "agent6 guthrie",
  "agentLabel": "fastnode",
  "status": "SUCCESS",
  "durationMillis": 110000,
  "testSuites": [
    {"name": "nested_stages", "tests": 50, "durationMs": 209000},
    {"name": "parallel_stages", "tests": 32, "durationMs": 80000},
    {"name": "unified_header", "tests": 20, "durationMs": 15000}
  ]
}
```

Human-readable output adds a test summary line per stage:

```
buildgit pipeline 14
...
  Unit Tests B  (fastnode)  6 suites, 156 tests, 5m 24s cumulative
  Unit Tests C  (fastnode)  10 suites, 170 tests, 4m 12s cumulative
```

**Requirements:**
- Test suite names are derived from JUnit `testsuite` name or `className` — framework-agnostic.
- `testSuites` field is omitted for stages with no JUnit results (e.g., Build, Deploy).
- Human output shows suite count, test count, and cumulative duration per stage.
- JSON `testSuites` array includes `name`, `tests` (count), `durationMs` (cumulative), and optionally `failures` count.
- This enriches the existing `pipeline` command — no new subcommand needed.

### Implementation Notes

- All features rely on data already available from the Jenkins API (build JSON, test reports, node/label configuration). No new Jenkins plugins or credentials are required.
- JUnit XML is the standard test report format across frameworks (JUnit, pytest, bats-core, Jest, Go test, etc.). Standardizing on JUnit report data makes these features framework-agnostic.
- Features 1 and 4 overlap in data source (JUnit test reports mapped to stages). Implementation should share the underlying test-report-to-stage correlation logic.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
