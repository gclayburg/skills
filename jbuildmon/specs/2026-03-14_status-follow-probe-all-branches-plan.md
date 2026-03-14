# Implementation Plan: Add `--probe-all` flag to follow builds on any multibranch pipeline branch

**Parent spec:** `jbuildmon/specs/2026-03-14_status-follow-probe-all-branches-spec.md`

## Contents

- [ ] **Chunk 1: Option parsing, validation, and multibranch branch listing API**
- [ ] **Chunk 2: Probe-all polling loop and build detection**
- [ ] **Chunk 3: Integration with follow mode and end-to-end tests**


## Chunk Detail

### Chunk 1: Option parsing, validation, and multibranch branch listing API

#### Description

Add the `--probe-all` flag to the status option parser, implement all validation rules (requires `-f`, rejects explicit branch in `--job`, warns on non-multibranch), and add a new function to query the multibranch top-level API for all branch sub-jobs with their latest build numbers.

#### Spec Reference

See spec [New flag: `--probe-all`](./2026-03-14_status-follow-probe-all-branches-spec.md#new-flag---probe-all), [Flag validation](./2026-03-14_status-follow-probe-all-branches-spec.md#flag-validation), and [Jenkins API for multibranch branch listing](./2026-03-14_status-follow-probe-all-branches-spec.md#jenkins-api-for-multibranch-branch-listing).

#### Dependencies

- None

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/status_parsing_and_format.sh` (modified — add `--probe-all` to `_parse_status_options`)
- `jbuildmon/skill/buildgit/scripts/lib/buildgit/job_helpers.sh` (modified — add validation in status dispatch path, add `_fetch_multibranch_baselines` function)
- `jbuildmon/skill/buildgit/scripts/buildgit` (modified — help text update)
- `jbuildmon/test/buildgit_probe_all.bats` (new — validation and API tests)
- `jbuildmon/test/fixtures/multibranch_jobs_baseline.json` (new fixture)

#### Implementation Details

1. **Add `STATUS_PROBE_ALL` flag to `_parse_status_options`** in `status_parsing_and_format.sh`:
   ```bash
   --probe-all)
       STATUS_PROBE_ALL=true
       shift
       ;;
   ```
   Initialize `STATUS_PROBE_ALL=false` at the top of the function alongside the other status flags.

2. **Add validation** after option parsing completes (in the status command dispatch path in `buildgit` or `job_helpers.sh`):
   - If `STATUS_PROBE_ALL == "true"` and `STATUS_FOLLOW_MODE != "true"`: emit error to stderr, exit 1.
   - If `STATUS_PROBE_ALL == "true"` and `JOB_NAME` contains `/` (explicit branch): emit error to stderr, exit 1.
   - Pass `STATUS_PROBE_ALL` through to `_cmd_status_follow` as a new parameter.

3. **Add `_fetch_multibranch_baselines`** function in `job_helpers.sh`:
   ```bash
   _fetch_multibranch_baselines() {
       local top_job_name="$1"
       local job_path
       job_path=$(jenkins_job_path "$top_job_name")
       local response
       response=$(jenkins_api "${job_path}/api/json?tree=jobs[name,lastBuild[number]]")
       # Transform .jobs[] into {"branch_name": last_build_number, ...}
       # Branches with null lastBuild get 0
       echo "$response" | jq '[.jobs[] | {key: .name, value: (.lastBuild.number // 0)}] | from_entries'
   }
   ```
   - Uses `jenkins_api` with `jenkins_job_path "$top_job_name"` to build the URL.
   - Uses `jq` to transform `.jobs[]` into a `{name: lastBuild.number}` map.

4. **Add non-multibranch fallback**: When `STATUS_PROBE_ALL == "true"`, check job type via `get_jenkins_job_type`. If not multibranch, emit warning to stderr and clear `STATUS_PROBE_ALL` to fall back to normal follow behavior.

5. **Update help text** in `buildgit` main script:
   - Add `--probe-all` to the status command options section:
     ```
       --probe-all           With -f: follow builds on any multibranch branch
     ```
   - Add examples:
     ```
       buildgit status -f --probe-all          # Follow next build on any branch
       buildgit status -f --probe-all --once   # Follow one build on any branch, then exit
     ```

6. **Add fixture** `multibranch_jobs_baseline.json` representing a top-level multibranch API response with `jobs[]` containing 2-3 branches with varying `lastBuild` states (one with builds, one with `null` lastBuild):
   ```json
   {
     "jobs": [
       {"name": "main", "lastBuild": {"number": 85}},
       {"name": "feature-x", "lastBuild": {"number": 12}},
       {"name": "new-empty-branch", "lastBuild": null}
     ]
   }
   ```

#### Test Plan

**Test File:** `test/buildgit_probe_all.bats`

Each test case must include a comment documenting the spec section it validates (e.g., `# Spec: status-follow-probe-all-branches-spec.md, Flag validation`). Target 80% coverage of the code introduced in this chunk.

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `probe_all_requires_follow_flag` | `status --probe-all` without `-f` exits with error on stderr | Flag validation |
| `probe_all_rejects_explicit_branch_job` | `status -f --probe-all --job ralph1/main` exits with error | Flag validation |
| `probe_all_allows_top_level_job` | `status -f --probe-all --job ralph1` is accepted (no parse error) | Flag validation |
| `probe_all_non_multibranch_warns_and_falls_back` | Mock a plain Pipeline job. Verify warning on stderr | Flag validation |
| `fetch_multibranch_baselines_returns_branch_map` | Mock multibranch API, verify JSON map with branch names and build numbers | Jenkins API for multibranch branch listing |
| `fetch_multibranch_baselines_handles_no_builds` | Branch with null lastBuild returns 0 in the map | Jenkins API for multibranch branch listing |

**Mocking Requirements:**
- Mock `jenkins_api` to return `multibranch_jobs_baseline.json` for the top-level job API endpoint.
- Mock `get_jenkins_job_type` to return `"multibranch"` or `"pipeline"` as needed.
- Tests for validation only need option parsing — no full build flow needed.
- Follow the existing mock patterns from `test/buildgit_status.bats` and `test/buildgit_errors.bats`.

**Dependencies:** None

#### Implementation Log

<!-- Filled in by the implementing agent after completing this chunk.
     Summarize: files changed, key decisions, anything the finalize step needs to know. -->

---

### Chunk 2: Probe-all polling loop and build detection

#### Description

Implement the core probe-all polling loop that replaces the single-job `_follow_wait_for_new_build` with a multi-branch polling function. This function establishes baselines, polls all branches on each cycle, detects new builds (including on newly appeared branches), and returns the detected branch and build number.

#### Spec Reference

See spec [Polling behavior](./2026-03-14_status-follow-probe-all-branches-spec.md#polling-behavior) and [Output messages](./2026-03-14_status-follow-probe-all-branches-spec.md#output-messages).

#### Dependencies

- **Chunk 1** (`STATUS_PROBE_ALL` flag parsed, `_fetch_multibranch_baselines` function available in `job_helpers.sh`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/lib/buildgit/monitor_helpers.sh` (modified — add `_follow_wait_probe_all` and `_follow_wait_probe_all_timeout`)
- `jbuildmon/test/buildgit_probe_all.bats` (extended — polling and detection tests)
- `jbuildmon/test/fixtures/multibranch_jobs_new_build.json` (new fixture — second poll with incremented build)
- `jbuildmon/test/fixtures/multibranch_jobs_new_branch.json` (new fixture — second poll with new branch appearing)

#### Implementation Details

1. **Add `_follow_wait_probe_all`** in `monitor_helpers.sh`:
   ```bash
   _follow_wait_probe_all() {
       local top_job_name="$1"
       # 1. Fetch baselines via _fetch_multibranch_baselines
       local baselines
       baselines=$(_fetch_multibranch_baselines "$top_job_name")
       # 2. Print waiting message
       log_info "Waiting for Jenkins build ${top_job_name} (any branch) to start..."
       # 3. Poll loop:
       while true; do
           sleep "$POLL_INTERVAL"
           local current
           current=$(_fetch_multibranch_baselines "$top_job_name")
           # Compare current vs baselines using jq:
           # - Any branch where current number > baseline number → detected
           # - Any new branch (not in baselines) with build > 0 → detected
           local detected
           detected=$(jq -n --argjson base "$baselines" --argjson curr "$current" '
               [$curr | to_entries[] |
                select(
                  (.value > 0) and
                  (($base[.key] // 0) < .value)
                )] | first // empty
               | "\(.key) \(.value)"
           ')
           if [[ -n "$detected" ]]; then
               local branch build_number
               branch="${detected%% *}"
               build_number="${detected##* }"
               log_info "Build detected on branch '${branch}' — following ${top_job_name}/${branch} #${build_number}"
               echo "${branch} ${build_number}"
               return 0
           fi
       done
   }
   ```

2. **Add `_follow_wait_probe_all_timeout`** — same logic but with deadline enforcement (for `--once` support):
   ```bash
   _follow_wait_probe_all_timeout() {
       local top_job_name="$1"
       local timeout_secs="$2"
       local deadline=$(( $(date +%s) + timeout_secs ))
       # Same baseline + poll logic as _follow_wait_probe_all
       # Returns 1 on timeout (same contract as _follow_wait_for_new_build_timeout)
   }
   ```

3. **Baseline comparison logic** (jq-based):
   - Baselines stored as a JSON object: `{"main": 85, "feature-x": 12, "new-empty-branch": 0}`
   - On each poll cycle, re-fetch the full map and compare.
   - Detection criteria: branch has `current_number > baseline_number` (covers both existing branches with new builds and new branches with `baseline = 0`).
   - Use `jq` to find the first differing branch (deterministic ordering by jq's `first`).

4. **Output messages** per spec [Output messages](./2026-03-14_status-follow-probe-all-branches-spec.md#output-messages):
   - Waiting: `log_info "Waiting for Jenkins build ${top_job_name} (any branch) to start..."`
   - Detection: `log_info "Build detected on branch '${branch}' — following ${top_job_name}/${branch} #${number}"`

5. **Add fixtures**:
   - `multibranch_jobs_new_build.json` — same branches as baseline but `feature-x` build number incremented from 12 to 13.
   - `multibranch_jobs_new_branch.json` — same branches as baseline plus a new `"feature-y"` branch with `lastBuild: {"number": 1}`.

#### Test Plan

**Test File:** `test/buildgit_probe_all.bats`

Each test case must include a comment documenting the spec section it validates. Target 80% coverage of the polling functions introduced in this chunk.

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `probe_all_detects_new_build_on_existing_branch` | Mock 2 polls: baseline fixture then new-build fixture. Verify detection returns correct branch and build number. | Polling behavior |
| `probe_all_detects_new_branch` | Mock 2 polls: baseline fixture then new-branch fixture. Verify detection returns the new branch. | Polling behavior |
| `probe_all_waiting_message` | Verify the "Waiting for Jenkins build ralph1 (any branch) to start..." message appears on stdout. | Output messages |
| `probe_all_shows_branch_detection_message` | Verify "Build detected on branch 'feature-x'" message appears on stdout. | Output messages |
| `probe_all_timeout_returns_failure` | `_follow_wait_probe_all_timeout` with 0s timeout and no new build returns exit code 1. | Polling behavior |

**Mocking Requirements:**
- Mock `jenkins_api` to return different fixture files on successive calls. Use a counter file (`$BATS_TEST_TMPDIR/poll_count`) to alternate between baseline and detection fixtures.
- Mock `get_build_info` and `get_last_build_number` for the detected branch job (needed when the caller proceeds to monitor after detection).
- Set `POLL_INTERVAL=0` to avoid test delays.
- Use `3>&-` before `2>&1` when launching subprocesses (per bats-core fd 3 rules in `jbuildmon/CLAUDE.md`).

**Dependencies:** Chunk 1 (`_fetch_multibranch_baselines` must be available)

#### Implementation Log

<!-- Filled in by the implementing agent after completing this chunk.
     Summarize: files changed, key decisions, anything the finalize step needs to know. -->

---

### Chunk 3: Integration with follow mode and end-to-end tests

#### Description

Wire the probe-all polling functions into `_cmd_status_follow` so that when `STATUS_PROBE_ALL` is true, the follow loop uses the multi-branch polling instead of single-branch polling. Handle the `--once` interaction, the post-build re-baseline for continuous follow, and ensure all existing flag combinations work correctly with `--probe-all`.

#### Spec Reference

See spec [Polling behavior](./2026-03-14_status-follow-probe-all-branches-spec.md#polling-behavior) items 3-4, [Interaction with existing flags](./2026-03-14_status-follow-probe-all-branches-spec.md#interaction-with-existing-flags), and [Commands affected](./2026-03-14_status-follow-probe-all-branches-spec.md#commands-affected).

#### Dependencies

- **Chunk 1** (option parsing and validation)
- **Chunk 2** (polling functions `_follow_wait_probe_all` and `_follow_wait_probe_all_timeout`)

#### Produces

- `jbuildmon/skill/buildgit/scripts/buildgit` (modified — `_cmd_status_follow` updated with probe-all path)
- `jbuildmon/skill/buildgit/scripts/lib/buildgit/job_helpers.sh` (modified — probe-all job resolution bypass in `_resolve_effective_job_name`)
- `jbuildmon/test/buildgit_probe_all.bats` (extended — end-to-end integration tests)

#### Implementation Details

1. **Update `_cmd_status_follow` signature** to accept `probe_all` parameter:
   ```bash
   _cmd_status_follow() {
       local job_name="$1"
       local json_mode="$2"
       local once_mode="${3:-false}"
       local once_timeout="${4:-10}"
       local line_mode="${5:-false}"
       local no_tests="${6:-false}"
       local prior_jobs_count="${7:-3}"
       local probe_all="${8:-false}"
       ...
   }
   ```

2. **Update callers** to pass `STATUS_PROBE_ALL` as the 8th argument at both call sites:
   - In `buildgit` main script (line ~796): add `"$STATUS_PROBE_ALL"` as 8th arg.
   - In `job_helpers.sh` (line ~246): add `"$STATUS_PROBE_ALL"` as 8th arg.

3. **Probe-all branch in the follow loop**: When `probe_all == "true"`, modify the main `while true` loop:
   - Extract the top-level job name: `top_job_name="${job_name%%/*}"` (or use `job_name` directly if no `/`).
   - At the initial wait-for-build stage (where `build_number == 0` or `first_check == true` with a completed build), replace `_follow_wait_for_new_build` / `_follow_wait_for_new_build_timeout` with `_follow_wait_probe_all` / `_follow_wait_probe_all_timeout`.
   - Parse the returned `"${branch} ${build_number}"` string.
   - Set `job_name` to `"${top_job_name}/${detected_branch}"` for the remainder of this build's monitoring.
   - Continue with the existing monitoring logic for that specific build.

4. **Post-build re-baseline** (when `once_mode != "true"`):
   - At the bottom of the loop where the code currently calls `_follow_wait_for_new_build "$job_name" "$build_number"`, instead call `_follow_wait_probe_all "$top_job_name"` to re-baseline all branches and wait for the next build on any branch.
   - Reset `job_name` to the top-level name before re-entering the probe-all wait.

5. **Job resolution bypass for probe-all**: In `_resolve_effective_job_name` (in `job_helpers.sh`), when `STATUS_PROBE_ALL` is true and the job is multibranch:
   - Skip the branch inference (`_get_current_git_branch`) and existence check (`multibranch_branch_exists`).
   - Return just the top-level job name (e.g., `ralph1`) so that `_cmd_status_follow` receives the top-level name and handles branch detection itself.
   - The branch existence check is deferred until after a build is detected (the branch must exist since Jenkins is building it).
   - To pass `STATUS_PROBE_ALL` into `_resolve_effective_job_name`, either pass it as a 3rd parameter or check the global variable directly.

6. **Prior-jobs with probe-all**: When `--prior-jobs` is used with `--probe-all`, prior jobs come from the current git branch (since we don't know which branch will build next). This is the existing default behavior — no change needed since the preamble runs before probe-all detection.

7. **Ensure push/build commands are NOT affected**: Verify that `STATUS_PROBE_ALL` is only checked in the status follow path. The `push` and `build` commands should never set or read this flag.

#### Test Plan

**Test File:** `test/buildgit_probe_all.bats`

Each test case must include a comment documenting the spec section it validates. Target 80% coverage of the integration code introduced in this chunk.

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `probe_all_with_once_exits_after_build` | Full flow: detect build on a branch, monitor to completion, verify exit code 0 and that monitoring output appears. | Interaction with existing flags |
| `probe_all_with_once_timeout_exits_on_timeout` | No build starts within timeout. Verify exit code 2 and error message. | Interaction with existing flags |
| `probe_all_continuous_rebaselines_after_build` | After first build completes, verify re-baseline and "Waiting for Jenkins build ralph1 (any branch)" message reappears. | Polling behavior item 4 |
| `probe_all_line_mode_works` | `--probe-all --line --once` produces one-line status output after detection. | Interaction with existing flags |
| `probe_all_json_mode_works` | `--probe-all --json --once` produces valid JSON output for the detected build. | Interaction with existing flags |
| `probe_all_push_command_unaffected` | `push` command does not accept `--probe-all` or use probe-all logic. | Commands affected |

**Mocking Requirements:**
- Full mock stack: `jenkins_api`, `get_build_info`, `get_last_build_number`, `get_jenkins_job_type`, `multibranch_branch_exists`.
- Mock build lifecycle: `building=true` on first `get_build_info` call, then `building=false` with `result=SUCCESS` on subsequent calls.
- Use the poll counter pattern from Chunk 2 to alternate API responses.
- Set `POLL_INTERVAL=0` and `MAX_BUILD_TIME=10` for fast tests.
- Use `3>&-` before `2>&1` when launching subprocesses and `trap '' PIPE` after `set -euo pipefail` in wrapper heredocs (per bats-core rules in `jbuildmon/CLAUDE.md`).

**Dependencies:** Chunks 1 and 2

#### Implementation Log

<!-- Filled in by the implementing agent after completing this chunk.
     Summarize: files changed, key decisions, anything the finalize step needs to know. -->

---

## SPEC Workflow

**Parent spec:** `jbuildmon/specs/2026-03-14_status-follow-probe-all-branches-spec.md`

Read `specs/CLAUDE.md` for full workflow rules. The workflow below applies to multi-chunk plan implementation.

### Per-Chunk Workflow (every chunk must follow these steps)

1. **Run all unit tests** before starting. Do not proceed if tests are failing.
   - Test runner: `jbuildmon/test/bats/bin/bats jbuildmon/test/` (do NOT use any bats from `$PATH`)
2. **Implement the chunk** as described in its Implementation Details section.
3. **Write or update unit tests** as described in the chunk's Test Plan section.
4. **Run all unit tests** and confirm they pass (both new and existing).
5. **Fill in the `#### Implementation Log`** for the chunk you implemented — summarize files changed, key decisions, and anything notable.
6. **Commit and push** using `buildgit push jenkins` with a commit message that includes the chunk number (e.g., `"chunk 1/3: add --probe-all option parsing and multibranch API"`).
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
