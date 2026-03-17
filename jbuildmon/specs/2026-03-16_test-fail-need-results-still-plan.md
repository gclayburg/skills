# Implementation Plan: Hierarchical Test Results with Downstream Aggregation

**Parent spec:** `jbuildmon/specs/2026-03-16_test-fail-need-results-still-spec.md`

## Contents

- [x] **Chunk 1: Downstream test result collection and aggregation library**
- [x] **Chunk 2: Hierarchical test results display for `--all` mode**
- [x] **Chunk 3: One-line mode and JSON mode downstream aggregation**
- [x] **Chunk 4: Monitoring mode integration and manual test plan verification**

## Chunk Detail

### Chunk 1: Downstream test result collection and aggregation library

#### Description

Add new library functions that detect downstream builds from console output, fetch test results from each one, and return a structured data format containing per-job test results alongside aggregated totals. This chunk produces testable library code that later chunks will call from the display and formatting paths.

#### Spec Reference

See spec [Downstream Build Detection](./2026-03-16_test-fail-need-results-still-spec.md#1-downstream-build-detection) sections 1.1-1.3 and [Test Result Collection](./2026-03-16_test-fail-need-results-still-spec.md#2-test-result-collection) sections 2.1-2.2.

#### Dependencies

- None

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh` (modified — add new functions)
- `jbuildmon/test/buildgit_downstream_tests.bats` (new — unit tests for collection and aggregation)
- `jbuildmon/test/fixtures/downstream_test_report_handle.json` (new fixture)
- `jbuildmon/test/fixtures/downstream_test_report_signalboot.json` (new fixture)
- `jbuildmon/test/fixtures/downstream_test_report_signalboot_fail.json` (new fixture)

#### Implementation Details

1. **Add `collect_downstream_test_results()`** in `api_test_results.sh`:
   ```bash
   # Usage: collect_downstream_test_results "job_name" "build_number" "console_output"
   # Returns: JSON array of per-job test result objects on stdout.
   # Each object: {"job":"name","stage":"Stage Name","build_number":N,"test_json":"..."|""}
   # The first element is always the parent job.
   # Exit code: 0 on success, 2 if parent had a communication error.
   collect_downstream_test_results() {
       local job_name="$1"
       local build_number="$2"
       local console_output="$3"

       # 1. Fetch parent test results
       # 2. Detect downstream builds using detect_all_downstream_builds() from failure_analysis.sh
       # 3. If no downstream builds found, return just the parent result (single-element array)
       # 4. For each downstream build, fetch test results
       # 5. Map downstream job names to stage names (see step detail below)
       # 6. Return JSON array with parent + all downstream entries
   }
   ```

2. **Stage name mapping**: Use the existing `_downstream_stage_job_match_score()` from `failure_analysis.sh` pattern, or a simpler approach: extract stage names from `wfapi/describe` parallel branch data. A practical approach is to parse the console output for the `Scheduling project:` lines that appear within named pipeline stages. However, the simplest reliable approach is to find which parallel branch stage triggered each downstream build by matching the downstream job name against the pipeline stage names (e.g., `phandlemono-signalboot` → stage containing "SignalBoot"). The `detect_all_downstream_builds()` function already extracts `job-name build-number` pairs from console. For the stage name, search the stage list from `wfapi` for stages whose name fuzzy-matches the downstream job name using `_downstream_stage_job_match_score()`.

   Fallback: If no stage match is found, use the downstream job name directly as the display label.

3. **Add `aggregate_test_totals()`** in `api_test_results.sh`:
   ```bash
   # Usage: aggregate_test_totals "$collected_results_json"
   # Input: JSON array from collect_downstream_test_results
   # Returns: 4 lines on stdout: total_sum, passed_sum, failed_sum, skipped_sum
   # Treats missing/null test data as 0 for aggregation.
   aggregate_test_totals() {
       local results_json="$1"
       echo "$results_json" | jq -r '
           [.[] | select(.test_json != "") | .test_json | fromjson |
            {p: (.passCount // 0), f: (.failCount // 0), s: (.skipCount // 0)}] |
           {total: (map(.p + .f + .s) | add // 0),
            passed: (map(.p) | add // 0),
            failed: (map(.f) | add // 0),
            skipped: (map(.s) | add // 0)} |
           "\(.total)\n\(.passed)\n\(.failed)\n\(.skipped)"
       '
   }
   ```

4. **Add `has_downstream_builds()`** — quick check helper:
   ```bash
   # Usage: has_downstream_builds "$collected_results_json"
   # Returns: 0 if there are downstream builds (array length > 1), 1 otherwise
   has_downstream_builds() {
       local results_json="$1"
       local count
       count=$(echo "$results_json" | jq 'length')
       [[ "$count" -gt 1 ]]
   }
   ```

5. **Create test fixtures**:
   - `downstream_test_report_handle.json` — based on real data: `{"passCount":83,"failCount":0,"skipCount":0,"suites":[...]}`  (minimal suites array with 1-2 representative entries)
   - `downstream_test_report_signalboot.json` — all passing: `{"passCount":15,"failCount":0,"skipCount":0,"suites":[...]}`
   - `downstream_test_report_signalboot_fail.json` — with failure: `{"passCount":14,"failCount":1,"skipCount":0,"suites":[...]}` including one failed test case with `errorDetails` and `errorStackTrace`

6. **Handle communication errors**: If the parent `fetch_test_results` returns exit code 2, `collect_downstream_test_results` returns exit code 2 immediately (no downstream fetching). If a downstream `fetch_test_results` returns exit code 2, that downstream's `test_json` is set to empty string (treated as `?`) and collection continues.

7. **Recursive downstream**: For each downstream build, check if it has its own console output with downstream patterns. If so, recursively collect those results with an increased indent level. Store `depth` in each result object for display indentation.

#### Test Plan

**Test File:** `test/buildgit_downstream_tests.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `collect_no_downstream_returns_parent_only` | Mock build with no downstream builds in console; verify single-element array with parent test data | 1.1, 2.1 |
| `collect_with_downstream_returns_all` | Mock console with 2 downstream builds + mock their test reports; verify 3-element array (parent + 2 downstream) | 1.1, 2.1 |
| `collect_parent_404_downstream_have_results` | Mock parent testReport 404, 2 downstream builds with results; verify parent has empty test_json, downstreams have data | 2.2 |
| `aggregate_totals_correct_math` | Given collected JSON with parent (83/0/0) + downstream (14/1/0); verify totals = 97/1/0 | 2.1 |
| `aggregate_totals_treats_missing_as_zero` | Given collected JSON with parent (empty) + downstream (15/0/0); verify totals = 15/0/0 | 2.2 |
| `has_downstream_true_for_multi` | Array with 3 elements → returns 0 | 1.1 |
| `has_downstream_false_for_single` | Array with 1 element → returns 1 | 3.2 |
| `collect_downstream_comm_error_on_parent` | Parent returns exit code 2; verify collect returns exit code 2 immediately | 8 |
| `collect_downstream_comm_error_on_child` | One downstream returns exit code 2; verify it gets empty test_json, other downstream still collected | 2.2 |
| `stage_name_mapping` | Downstream job `phandlemono-signalboot` correctly maps to stage label `Build SignalBoot` | 1.2 |

**Mocking Requirements:**
- Mock `fetch_test_results` to return fixture JSON, empty string (404), or exit code 2
- Mock `detect_all_downstream_builds` to return controlled downstream pairs
- Mock `get_console_output` for downstream builds that need recursive detection
- Use the existing mock curl pattern from `test/bin/curl`
- All tests use `3>&-` before `2>&1` per bats fd 3 rules

**Dependencies:** None

#### Implementation Log

- Added downstream collection helpers in `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh`: `collect_downstream_test_results`, `aggregate_test_totals`, `has_downstream_builds`, plus small internal helpers for recursive collection and stage-label mapping.
- Reused the existing downstream console parsing and `_downstream_stage_job_match_score` matching path instead of introducing a second stage-association strategy; exact stage-log matches win, then fuzzy stage-name matching falls back, then the downstream job name is used.
- Parent `fetch_test_results` communication failures now abort collection with exit code `2`; downstream communication failures keep the node in the result tree with empty `test_json` so later display code can render `?` placeholders.
- Added `jbuildmon/test/buildgit_downstream_tests.bats` with coverage for no-downstream, multi-downstream, recursive depth tracking, aggregation, stage-name mapping, and parent/child communication error handling.
- Added fixtures `jbuildmon/test/fixtures/downstream_test_report_handle.json`, `jbuildmon/test/fixtures/downstream_test_report_signalboot.json`, and `jbuildmon/test/fixtures/downstream_test_report_signalboot_fail.json` for downstream aggregation tests.

---

### Chunk 2: Hierarchical test results display for `--all` mode

#### Description

Add the hierarchical `display_hierarchical_test_results()` function that renders the multi-line test results section with per-job lines, right-aligned numbers, per-line coloring, a Totals row, and the `--------------------` separator. Integrate it into the `--all` output paths for both success and failure builds.

#### Spec Reference

See spec [Hierarchical Display Format](./2026-03-16_test-fail-need-results-still-spec.md#3-hierarchical-display-format-all-mode) sections 3.1-3.4.

#### Dependencies

- **Chunk 1** (`collect_downstream_test_results`, `aggregate_test_totals`, `has_downstream_builds` functions available in `api_test_results.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh` (modified — add `display_hierarchical_test_results`)
- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/output_render.sh` (modified — update `display_success_output` and `_display_failure_diagnostics` to use hierarchical display)
- `jbuildmon/test/buildgit_downstream_tests.bats` (extended — display formatting tests)

#### Implementation Details

1. **Add `display_hierarchical_test_results()`** in `api_test_results.sh`:
   ```bash
   # Usage: display_hierarchical_test_results "$collected_results_json"
   # Renders the hierarchical test results section with aligned columns.
   # Falls back to display_test_results (single-line) when no downstream builds.
   display_hierarchical_test_results() {
       local collected_json="$1"

       # If single job (no downstream), delegate to existing display_test_results
       if ! has_downstream_builds "$collected_json"; then
           local parent_test_json
           parent_test_json=$(echo "$collected_json" | jq -r '.[0].test_json // empty')
           display_test_results "$parent_test_json"
           return
       fi

       # Compute totals
       local totals
       totals=$(aggregate_test_totals "$collected_json")
       local total_sum passed_sum failed_sum skipped_sum
       total_sum=$(echo "$totals" | sed -n '1p')
       passed_sum=$(echo "$totals" | sed -n '2p')
       failed_sum=$(echo "$totals" | sed -n '3p')
       skipped_sum=$(echo "$totals" | sed -n '4p')

       # Determine header/footer color from totals
       local section_color="${COLOR_GREEN}"
       if [[ "$failed_sum" -gt 0 ]]; then
           section_color="${COLOR_YELLOW}"
       fi

       echo ""
       echo "${section_color}=== Test Results ===${COLOR_RESET}"

       # Render each job line (parent first, then children)
       # ... (see step 2 below)

       # Separator and Totals
       echo "--------------------"
       # ... render Totals line

       # Failed test details from all jobs
       # ... (see step 4 below)

       echo "${section_color}====================${COLOR_RESET}"
   }
   ```

2. **Per-job line rendering with right-alignment**:
   - First pass: compute the max width needed for each numeric column across all lines (including Totals)
   - Second pass: render each line with right-aligned numbers using `printf "%*d"` formatting
   - For each job in the collected results array:
     - Determine indent: `depth * 2` spaces (parent=depth 0, children=depth 1, grandchildren=depth 2)
     - Get label: stage name for children, job name for parent
     - If test_json is empty: show `?` for all values, use default color
     - If test_json present: parse counts, use green (fail=0) or yellow (fail>0)
   - Format: `<indent><label><padding>Total: <N> | Passed: <N> | Failed: <N> | Skipped: <N>`

3. **Right-alignment strategy**: Since numbers vary in width (1 digit vs 3 digits), compute max width for each column position. Use `printf "%-*s"` for labels and `printf "%*s"` for number values. The label column width = max label length + max indent. Number columns align across all lines.

4. **Failed test details from all jobs**: After the Totals row, iterate through all jobs in the collected results. For each job with `failCount > 0`, extract failed tests via `parse_failed_tests` and display them using the existing formatting logic from `display_test_results` (error details, stack traces, age indicators, truncation).

5. **Update `display_success_output()`** in `output_render.sh` (lines 197-211):
   - Replace the current `fetch_test_results` + `display_test_results` block with:
     ```bash
     local console_output
     console_output=$(get_console_output "$job_name" "$build_number")
     local collected_results
     collected_results=$(collect_downstream_test_results "$job_name" "$build_number" "$console_output")
     display_hierarchical_test_results "$collected_results"
     ```
   - Note: `display_success_output` currently doesn't have console_output. It will need to fetch it. Check if it's already fetched elsewhere in the caller and can be passed through.

6. **Update `_display_failure_diagnostics()`** in `output_render.sh` (lines 521-535):
   - Replace the current `fetch_test_results` + `display_test_results` block with:
     ```bash
     local collected_results collected_rc=0
     if collected_results=$(collect_downstream_test_results "$job_name" "$build_number" "$console_output"); then
         collected_rc=0
     else
         collected_rc=$?
         collected_results=""
     fi
     if [[ "$collected_rc" -eq 2 ]]; then
         _note_test_results_comm_failure "$job_name" "$build_number"
         display_test_results_comm_error
     else
         display_hierarchical_test_results "$collected_results"
     fi
     ```
   - Console output is already available as `$3` in `_display_failure_diagnostics`.

7. **Handle the `display_success_output` console fetch**: `display_success_output` doesn't currently receive console output. Two options:
   - Fetch it inside the function: `console_output=$(get_console_output "$job_name" "$build_number")`
   - This is an extra API call for SUCCESS builds, but it's needed to detect downstream builds. Only called in `--all` mode (not one-line).

#### Test Plan

**Test File:** `test/buildgit_downstream_tests.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `hierarchical_display_all_passing` | Mock parent + 2 downstream all passing; verify header, 3 job lines, separator, Totals, all green | 3.1, 3.3 |
| `hierarchical_display_with_failure` | Mock parent 404 + downstream passing + downstream failing; verify `?` line, green line, yellow line, correct Totals | 3.1, 3.3 |
| `hierarchical_display_right_alignment` | Mock builds with different number widths (1-digit vs 3-digit); verify numbers align across lines | 3.1 |
| `hierarchical_display_no_downstream_fallback` | Single-element collected results; verify falls back to existing single-line display_test_results format | 3.2 |
| `hierarchical_display_failed_test_details` | Mock downstream with failed tests; verify FAILED TESTS section appears after Totals | 3.4 |
| `hierarchical_display_color_per_line` | Verify green ANSI on pass lines, yellow on fail lines, no color on `?` lines | 3.3 |
| `success_output_shows_hierarchical_results` | Mock display_success_output call with downstream builds; verify hierarchical display appears | Integration |
| `failure_diagnostics_shows_hierarchical_results` | Mock _display_failure_diagnostics with downstream builds; verify hierarchical display replaces placeholder | Integration |

**Mocking Requirements:**
- Mock `collect_downstream_test_results` to return controlled JSON arrays
- Mock `get_console_output` for success path console fetch
- Mock `fetch_test_results` for the fallback (single-job) path
- Capture stdout and check for exact formatting including alignment and ANSI codes
- Use `COLOR_GREEN`, `COLOR_YELLOW`, `COLOR_RESET` test values for predictable output checking

**Dependencies:** Chunk 1 (collection functions)

#### Implementation Log

- Added `display_hierarchical_test_results()` plus small internal helpers in `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh` to render multi-job `--all` test output with aligned columns, per-line colors, a Totals row, and aggregated failed-test details.
- Refactored the shared failed-test detail rendering so both single-job and hierarchical paths use the same truncation, age-indicator, and footer behavior without duplicating formatting logic.
- Updated `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/output_render.sh` so `display_success_output()` fetches console text when needed and both success/failure `--all` paths call downstream collection plus hierarchical rendering; failure diagnostics still pass the parent test JSON into `_display_error_log_section` to preserve existing suppression behavior in this chunk.
- Extended `jbuildmon/test/buildgit_downstream_tests.bats` with hierarchical display coverage for passing/failing trees, alignment, fallback-to-single-job behavior, failed-test details, per-line coloring, and the two `--all` integration call sites.

---

### Chunk 3: One-line mode and JSON mode downstream aggregation

#### Description

Update the one-line status format (`buildgit status`, `buildgit status --line`) to use aggregated Totals from downstream builds, and update JSON mode (`buildgit status --json`) to include the `breakdown` array when downstream builds exist.

#### Spec Reference

See spec [One-Line Mode](./2026-03-16_test-fail-need-results-still-spec.md#4-one-line-mode-buildgit-status-buildgit-status---line) sections 4.1-4.2 and [JSON Mode](./2026-03-16_test-fail-need-results-still-spec.md#5-json-mode-buildgit-status---json) sections 5.1-5.2.

#### Dependencies

- **Chunk 1** (`collect_downstream_test_results`, `aggregate_test_totals`, `has_downstream_builds` functions)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/status_parsing_and_format.sh` (modified — `_status_line_for_build_json` uses downstream totals)
- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh` (modified — add `format_hierarchical_test_results_json`)
- `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/output_render.sh` (modified — `output_json` uses breakdown)
- `jbuildmon/test/buildgit_downstream_tests.bats` (extended — one-line and JSON tests)

#### Implementation Details

1. **Update `_status_line_for_build_json()`** in `status_parsing_and_format.sh` (lines 440-461):
   - After the current `fetch_test_results` call, if the result is non-empty (parent has test data) AND there are no downstream builds, keep current behavior.
   - If the parent has test data but there ARE downstream builds, OR if the parent returns empty (404):
     - Fetch console output: `console_output=$(get_console_output "$job_name" "$build_number")`
     - Call `collect_downstream_test_results "$job_name" "$build_number" "$console_output"`
     - If downstream builds exist (array length > 1), compute totals via `aggregate_test_totals` and use those for `tests_display`
     - If no downstream builds, keep current behavior (parent-only or `?/?/?`)
   - Optimization: Only fetch console output when parent test results don't tell the full story. To check for downstream builds without fetching console every time, we can check the parent testReport first — if the parent returns results AND we don't need to aggregate, skip console fetch. But per the spec, we ALWAYS aggregate for multi-component pipelines. So we need a way to know if a job has downstream builds.
   - Practical approach: Fetch console output for all builds. The console text API is already used elsewhere. Cache it if available. Alternatively, check if `detect_all_downstream_builds` returns any results — if not, use parent-only numbers.

2. **Minimize API overhead for `-n` mode**: When `status -n 5` fetches multiple builds, each build would need console text + downstream testReport calls. This could be slow. Mitigation:
   - Only fetch console text when the parent testReport returns data (to check for downstream builds to aggregate) or returns 404 (to find downstream builds)
   - Once we determine a job has downstream builds for one build, assume all builds of that job have the same downstream pattern and reuse the downstream detection

3. **Add `format_hierarchical_test_results_json()`** in `api_test_results.sh`:
   ```bash
   # Usage: format_hierarchical_test_results_json "$collected_results_json"
   # Returns: JSON object with top-level totals + breakdown array
   format_hierarchical_test_results_json() {
       local collected_json="$1"

       # Single job → delegate to existing format_test_results_json
       if ! has_downstream_builds "$collected_json"; then
           local parent_test_json
           parent_test_json=$(echo "$collected_json" | jq -r '.[0].test_json // empty')
           format_test_results_json "$parent_test_json"
           return
       fi

       # Compute totals
       local totals
       totals=$(aggregate_test_totals "$collected_json")
       # ... build JSON with top-level totals + breakdown array
       # Each breakdown entry: {job, stage, build_number, total, passed, failed, skipped, failed_tests}
       # null values for entries with empty test_json
   }
   ```

4. **Update `output_json()`** in `output_render.sh`:
   - Replace the current `fetch_test_results` + `format_test_results_json` block with:
     ```bash
     local console_output
     console_output=$(get_console_output "$job_name" "$build_number")
     local collected_results
     collected_results=$(collect_downstream_test_results "$job_name" "$build_number" "$console_output")
     local test_results_formatted
     test_results_formatted=$(format_hierarchical_test_results_json "$collected_results")
     ```
   - For communication errors, keep existing behavior.

#### Test Plan

**Test File:** `test/buildgit_downstream_tests.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `oneline_uses_downstream_totals` | Mock parent (19/0/0) + 2 downstream builds (64/0/0, 15/0/0); verify one-line shows `Tests=98/0/0` | 4.1 |
| `oneline_parent_404_uses_downstream_totals` | Mock parent 404 + downstream (83/0/0, 14/1/0); verify `Tests=97/1/0` | 4.1 |
| `oneline_no_downstream_unchanged` | Mock single build with no downstream; verify current behavior preserved | 4.1 |
| `json_breakdown_present_for_multi_job` | Mock parent + 2 downstream; verify JSON has `breakdown` array with 3 entries | 5.1 |
| `json_breakdown_null_for_missing_tests` | Mock parent 404 in collected results; verify breakdown entry has `null` for total/passed/failed/skipped | 5.1 |
| `json_no_breakdown_for_single_job` | Mock single build without downstream; verify no `breakdown` field in JSON | 5.2 |
| `json_totals_match_oneline` | Mock same data; verify JSON top-level totals match one-line `Tests=` values | 7 |
| `oneline_comm_error_no_downstream_fallback` | Parent returns exit code 2; verify `!err!` displayed, no downstream attempted | 8 |

**Mocking Requirements:**
- Mock `fetch_test_results` for parent builds
- Mock `get_console_output` to return console text with `Starting building:` patterns
- Mock `collect_downstream_test_results` or mock the underlying functions
- Mock downstream `fetch_test_results` calls with fixture data
- Use `3>&-` before `2>&1` per bats fd 3 rules

**Dependencies:** Chunk 1 (collection and aggregation functions)

#### Implementation Log

- Updated `jbuildmon/skill/buildgit/scripts/lib/buildgit/status_parsing_and_format.sh` so `_status_line_for_build_json()` keeps the existing single-job path but, when console output shows downstream builds, aggregates parent + downstream totals for the `Tests=pass/fail/skip` field; parent test-report communication failures still short-circuit to `!err!` without attempting downstream collection.
- Added `format_hierarchical_test_results_json()` in `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh` to emit the existing single-job JSON unchanged, or a multi-job object with top-level totals, concatenated `failed_tests`, and a per-job `breakdown` array using `null` counts for missing reports.
- Updated `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/json_output.sh` to call downstream collection plus hierarchical JSON formatting for completed builds while preserving the existing `test_results: null` sentinel for completed builds with no report and the existing `testResultsError: "communication_failure"` behavior.
- Extended `jbuildmon/test/buildgit_downstream_tests.bats` with direct coverage for one-line aggregation, parent-404 aggregation, single-job fallback, JSON `breakdown` presence/absence, JSON/oneline total consistency, and parent communication-error short-circuit behavior.

---

### Chunk 4: Monitoring mode integration and manual test plan verification

#### Description

Wire downstream test result collection into the monitoring mode completion path (`_handle_build_completion` in the main `buildgit` script) so that `buildgit push`, `buildgit build`, and `buildgit status -f` show hierarchical test results at build completion. Run the manual test plan against the real Jenkins server to verify end-to-end behavior.

#### Spec Reference

See spec [Monitoring Mode](./2026-03-16_test-fail-need-results-still-spec.md#6-monitoring-mode-buildgit-push-buildgit-build-buildgit-status--f) section 6 and [Consistency Rules](./2026-03-16_test-fail-need-results-still-spec.md#7-consistency-rules) section 7.

#### Dependencies

- **Chunk 1** (collection functions)
- **Chunk 2** (hierarchical display function)
- **Chunk 3** (JSON formatting function — needed if monitoring outputs JSON)

#### Produces

- `jbuildmon/skill/buildgit/scripts/buildgit` (modified — `_handle_build_completion` uses hierarchical display)
- `jbuildmon/test/buildgit_downstream_tests.bats` (extended — monitoring mode tests)

#### Implementation Details

1. **Update `_handle_build_completion()`** in the main `buildgit` script:
   - Find the test results section in `_handle_build_completion` (search for `fetch_test_results` or `display_test_results` call).
   - Replace with:
     ```bash
     local collected_results collected_rc=0
     if collected_results=$(collect_downstream_test_results "$job_name" "$build_number" "$console_output"); then
         collected_rc=0
     else
         collected_rc=$?
         collected_results=""
     fi
     if [[ "$collected_rc" -eq 2 ]]; then
         _note_test_results_comm_failure "$job_name" "$build_number"
         display_test_results_comm_error
     else
         display_hierarchical_test_results "$collected_results"
     fi
     ```
   - Console output should already be available in the monitoring completion path (it's used for failure diagnostics). Verify and pass it through.

2. **Handle monitoring JSON mode**: If `_handle_build_completion` also produces JSON for `status -f --json`, ensure it uses `format_hierarchical_test_results_json` instead of `format_test_results_json`.

3. **Verify consistency**: The same `collect_downstream_test_results` + `display_hierarchical_test_results` pattern is now used in:
   - `display_success_output` (snapshot --all, Chunk 2)
   - `_display_failure_diagnostics` (snapshot --all failure, Chunk 2)
   - `_handle_build_completion` (monitoring mode, this chunk)
   - `output_json` (JSON mode, Chunk 3)
   - `_status_line_for_build_json` (one-line mode, Chunk 3)

4. **Run the manual test plan**: Execute every test command from `2026-03-16_test-fail-need-results-still-test-plan.md` against the real Jenkins server:
   - Test 1: `buildgit --job phandlemono-IT status 73 --all` → verify hierarchical display
   - Test 2: `buildgit --job phandlemono-IT status 75 --all` → verify hierarchical display for success
   - Test 3: `buildgit --job phandlemono-IT status 73` → verify `Tests=97/1/0`
   - Test 4: `buildgit --job phandlemono-IT status 75` → verify `Tests=98/0/0`
   - Test 5: `buildgit --job phandlemono-IT status 73 --json` → verify breakdown array
   - Test 6: `buildgit --job phandlemono-IT status 75 --json` → verify breakdown array
   - Test 7: `buildgit status --all` → verify single-job format unchanged
   - Test 8: `buildgit status --json` → verify no breakdown field
   - Test 9: Consistency check across modes
   - Test 10: `buildgit --job phandlemono-IT status -n 5` → verify all builds
   - Test 11: Color verification
   - If any test fails, fix the code and re-run.

5. **Performance check**: Time the one-line mode for builds with downstream jobs vs without. Verify that the extra API calls don't add excessive latency. If `-n 5` is noticeably slow, consider adding a note about the expected overhead.

#### Test Plan

**Test File:** `test/buildgit_downstream_tests.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `monitoring_completion_shows_hierarchical_results` | Mock build completion with downstream builds; verify hierarchical test results display | 6 |
| `monitoring_completion_single_job_unchanged` | Mock build completion without downstream; verify existing single-line display | 6 |
| `monitoring_json_uses_breakdown` | Mock monitoring JSON output with downstream builds; verify breakdown array in JSON | 6 |
| `monitoring_comm_error_no_downstream` | Mock parent comm error in monitoring; verify comm error display, no downstream attempted | 8 |

**Mocking Requirements:**
- Mock the full monitoring completion flow: `get_build_info`, `get_console_output`, `fetch_test_results`, `detect_all_downstream_builds`
- Use existing test patterns from `test/buildgit_monitoring.bats` or similar
- Use `3>&-` before `2>&1` and `trap '' PIPE` per bats fd 3 rules

**Dependencies:** Chunks 1, 2, and 3

#### Implementation Log

- Updated `jbuildmon/skill/buildgit/scripts/buildgit` so `_handle_build_completion()` now fetches console output for successful monitored builds, collects downstream test results, and renders them through `display_hierarchical_test_results`; parent test-report communication failures still surface the existing comm-error path.
- Fixed a large-report regression in `jbuildmon/skill/buildgit/scripts/lib/jenkins-common/api_test_results.sh`: the collector now streams `test_json` into `jq` over stdin instead of passing it via `--arg`, which avoids `Argument list too long` on large Jenkins test reports during monitoring completion.
- Extended `jbuildmon/test/buildgit_downstream_tests.bats` with monitoring-path coverage for multi-job completion output, single-job fallback behavior, parent communication failure handling in `_handle_build_completion()`, and a regression test for oversized parent test reports. The large-report regression now writes collector output to a temp file instead of relying on bats `run` output capture, which avoids CI-only truncation/parsing issues on oversized JSON payloads.
- Re-ran the full unit suite after the change: `jbuildmon/test/bats/bin/bats jbuildmon/test/` passed with `920` tests.
- Ran the manual test plan commands against Jenkins. `phandlemono-IT` build `73` showed hierarchical totals `98/97/1/0`, build `75` showed `98/98/0/0`, one-line and JSON totals matched, and `status -n 5` showed aggregated downstream counts for builds `73` and `75`.
- Notable manual-plan nuance: the exact Test 8 helper command in `2026-03-16_test-fail-need-results-still-test-plan.md` raises a Python `TypeError` when the latest `ralph1/...` build has `"test_results": null`; raw JSON still confirms there is no `breakdown` field, so the no-downstream JSON shape remains unchanged.
- First Jenkins validation push surfaced the large-report regression above on `ralph1/2026-03-16_test-fail-need-resu #6`; the fix and regression test were added before the final push/verification.
- Second Jenkins validation push surfaced a CI-only failure in the new regression test on `ralph1/2026-03-16_test-fail-need-resu #7`; replacing `echo` with `printf` was not sufficient because the bats capture path itself was the problem.
- Third local/test iteration switched the large-report regression test to write the collector output to a temp file and inspect that file with `jq`; this is the version intended for the final verification push after local `920`-test success.
- Third Jenkins validation push surfaced one more portability issue on `ralph1/2026-03-16_test-fail-need-resu #9`: the regression test used `python3`, which was not installed on that CI shard. The final version generates the oversized JSON fixture with `jq` instead, keeping the test compatible with the existing CI toolchain.
- Performance spot-checks on this branch were acceptable: `status` without downstream took about `0.316s`, `status 75` on `phandlemono-IT` took about `0.639s`, and `status -n 5` on `phandlemono-IT` took about `2.600s`.

---

## SPEC Workflow

**Parent spec:** `jbuildmon/specs/2026-03-16_test-fail-need-results-still-spec.md`

Read `specs/CLAUDE.md` for full workflow rules. The workflow below applies to multi-chunk plan implementation.

### Per-Chunk Workflow (every chunk must follow these steps)

1. **Run all unit tests** before starting. Do not proceed if tests are failing.
   - Test runner: `jbuildmon/test/bats/bin/bats jbuildmon/test/` (do NOT use any bats from `$PATH`)
2. **Implement the chunk** as described in its Implementation Details section.
3. **Write or update unit tests** as described in the chunk's Test Plan section.
4. **Run all unit tests** and confirm they pass (both new and existing).
5. **Fill in the `#### Implementation Log`** for the chunk you implemented — summarize files changed, key decisions, and anything notable.
6. **Commit and push** using `buildgit push jenkins` with a commit message that includes the chunk number (e.g., `"chunk 1/4: downstream test result collection and aggregation library"`).
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
