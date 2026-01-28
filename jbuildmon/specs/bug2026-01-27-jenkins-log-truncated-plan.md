# Implementation Plan: Bug Fix - Jenkins Stage Log Truncation

This plan breaks down the bug fix for Jenkins stage log truncation into LLM-sized implementation chunks.

**Related Spec:** [bug1-jenkins-log-truncated-spec.md](./bug1-jenkins-log-truncated-spec.md)

---

- [x] **Chunk 1: Fix extract_stage_logs to Handle Nested Pipeline Blocks** ✓ COMPLETED

### Description

Update the `extract_stage_logs()` function in `lib/jenkins-common.sh` to correctly track nesting depth when extracting stage-specific logs. The current AWK script stops at the first `[Pipeline] }` marker, which may be a nested block end rather than the actual stage end.

### Spec Reference

See spec [bug1-jenkins-log-truncated-spec.md](./bug1-jenkins-log-truncated-spec.md#root-cause-analysis) sections "Root Cause Analysis" and "Technical Requirements".

### Dependencies

- None (this is the core fix)

### Produces

- `lib/jenkins-common.sh` (modified `extract_stage_logs` function at lines 573-584)

### Implementation Details

1. Replace the existing AWK script with nesting-depth tracking logic:
   - Initialize `nesting_depth = 0` before entering stage
   - When stage start marker `[Pipeline] { (StageName)` is found, set `nesting_depth = 1`
   - For each `[Pipeline] {` line, increment `nesting_depth`
   - For each `[Pipeline] }` line, decrement `nesting_depth`
   - Only stop when `nesting_depth` returns to 0

2. Handle edge cases:
   - Stage with no nested blocks (single `{` and `}`)
   - Deeply nested blocks (multiple levels)
   - Stage end not found (fall back to remaining output)

3. Algorithm pseudocode:
   ```
   1. Find stage start: "[Pipeline] { (StageName)"
   2. Set nesting_depth = 1
   3. For each subsequent line:
      a. If line contains "[Pipeline] {", increment nesting_depth
      b. If line contains "[Pipeline] }", decrement nesting_depth
      c. If nesting_depth == 0, stop (stage complete)
      d. Else include line in output
   4. Return collected lines
   ```

4. Preserve backward compatibility:
   - Function signature remains unchanged
   - Return format remains unchanged (newline-separated log lines)

### Test Plan

**Test File:** `test/extract_stage_logs.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `extract_stage_logs_simple_stage` | Single stage with no nesting extracts correctly | Technical Requirements |
| `extract_stage_logs_nested_dir_block` | Stage with `dir` block includes all nested content | Technical Requirements |
| `extract_stage_logs_deeply_nested` | Multiple nesting levels handled correctly | Edge Cases |
| `extract_stage_logs_with_post_stage` | Post-stage actions (junit, etc.) are included | Technical Requirements |
| `extract_stage_logs_nonexistent_stage` | Returns empty for non-existent stage | Edge Cases |
| `extract_stage_logs_no_end_marker` | Falls back gracefully when end marker missing | Edge Cases |

**Mocking Requirements:**
- None (function operates on string input, no external dependencies)

**Dependencies:** None

---

- [x] **Chunk 2: Create Comprehensive Unit Tests for Stage Log Extraction** ✓ COMPLETED

### Description

Create a new bats test file with comprehensive tests for the `extract_stage_logs` function, covering simple cases, nested blocks, deeply nested scenarios, and edge cases. Tests will validate the fix from Chunk 1.

### Spec Reference

See spec [bug1-jenkins-log-truncated-spec.md](./bug1-jenkins-log-truncated-spec.md#test-plan) section "Unit Test Cases".

### Dependencies

- Chunk 1 (Fix extract_stage_logs to Handle Nested Pipeline Blocks)

### Produces

- `test/extract_stage_logs.bats` (new test file)

### Implementation Details

1. Create test file structure:
   - Load test_helper for bats-assert and bats-support
   - Load jenkins-common.sh library
   - Define setup() to prepare test fixtures

2. Test case: Simple stage (no nesting):
   ```
   [Pipeline] { (Build)
   Building...
   [Pipeline] }
   ```
   - Verify output contains "Building..."

3. Test case: Nested dir block (from bug report):
   ```
   [Pipeline] { (Unit Tests)
   [Pipeline] dir
   Running in /path/to/workspace
   [Pipeline] {
   [Pipeline] sh
   + ./test/bats/bin/bats ...
   + true
   [Pipeline] }
   [Pipeline] // dir
   Post stage
   [Pipeline] junit
   Recording test results
   [Pipeline] }
   ```
   - Verify output includes "Post stage" and "Recording test results"
   - Verify output includes all lines between stage start and end

4. Test case: Deeply nested blocks:
   ```
   [Pipeline] { (Deploy)
   [Pipeline] withEnv
   [Pipeline] {
   [Pipeline] dir
   [Pipeline] {
   [Pipeline] sh
   + deploy command
   [Pipeline] }
   [Pipeline] }
   [Pipeline] }
   ```
   - Verify all nested content is captured

5. Test case: Post-stage actions included:
   - Verify lines after nested block close but before stage close are captured

6. Test case: Non-existent stage returns empty:
   - Pass console output without target stage
   - Verify empty result

7. Test case: Missing end marker fallback:
   - Console output with stage start but no proper close
   - Verify graceful handling

8. Document spec references in each test using comments:
   ```bash
   # Spec: bug1-jenkins-log-truncated-spec.md, Section: Technical Requirements
   @test "extract_stage_logs_nested_dir_block" {
   ```

### Test Plan

**Test File:** `test/extract_stage_logs.bats`

This chunk IS the test implementation. Verification:

| Verification | Method |
|--------------|--------|
| Tests execute | `./test/bats/bin/bats test/extract_stage_logs.bats` |
| All tests pass | Exit code 0, no failures |
| Coverage of spec requirements | Each test case maps to spec section |

**Mocking Requirements:**
- None (tests use inline console output strings)

**Dependencies:** Chunk 1 must be implemented first for tests to pass

---

- [x] **Chunk 3: Add Fallback Behavior for Insufficient Extraction** ✓ COMPLETED

### Description

Implement fallback behavior when stage extraction fails or produces insufficient output. When extracted logs are too short (< 5 lines), show the last N lines of console output with a message indicating extraction may be incomplete.

### Spec Reference

See spec [bug1-jenkins-log-truncated-spec.md](./bug1-jenkins-log-truncated-spec.md#fallback-behavior) section "Fallback Behavior".

### Dependencies

- Chunk 1 (Fix extract_stage_logs to Handle Nested Pipeline Blocks)

### Produces

- `lib/jenkins-common.sh` (modified `_display_error_logs` function around lines 1152-1197)

### Implementation Details

1. Modify `_display_error_logs` function to check extracted log length:
   - After extracting stage logs, count lines
   - If line count < 5, trigger fallback

2. Implement fallback logic:
   - Display message: "Stage log extraction may be incomplete. Showing last 50 lines:"
   - Show last 50 lines of full console output
   - Still include the full console URL for reference

3. Make fallback line count configurable:
   - Add optional parameter to function or use constant
   - Default to 50 lines for fallback display

4. Ensure full console URL is always displayed:
   - Verify URL is included in both normal and fallback paths

### Test Plan

**Test File:** `test/extract_stage_logs.bats` (add fallback tests)

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `fallback_when_extraction_empty` | Fallback triggers when stage not found | Fallback Behavior |
| `fallback_when_extraction_short` | Fallback triggers when < 5 lines extracted | Fallback Behavior |
| `fallback_shows_last_n_lines` | Fallback shows correct number of lines | Fallback Behavior |
| `fallback_includes_message` | Fallback includes explanatory message | Fallback Behavior |

**Mocking Requirements:**
- May need to mock or isolate the display function for testing

**Dependencies:** Chunk 1

---

- [x] **Chunk 4: Update Existing Tests and Run Regression Suite** ✓ COMPLETED

### Description

Update existing tests in `tests/test-failure-analysis.sh` to use nested console output examples that would have exposed the bug. Verify all existing tests still pass after the fix.

### Spec Reference

See spec [bug1-jenkins-log-truncated-spec.md](./bug1-jenkins-log-truncated-spec.md#acceptance-criteria) section "Acceptance Criteria" item 5: "Existing tests pass: No regression in other failure analysis scenarios".

### Dependencies

- Chunk 1 (Fix extract_stage_logs to Handle Nested Pipeline Blocks)
- Chunk 2 (Create Comprehensive Unit Tests)
- Chunk 3 (Add Fallback Behavior)

### Produces

- `tests/test-failure-analysis.sh` (modified with improved test cases)

### Implementation Details

1. Update Test 16 (`test_extract_stage_logs`) in `tests/test-failure-analysis.sh`:
   - Replace simple test case with nested console output
   - Verify the test now checks for content after nested blocks

2. Add new test case for nested extraction:
   - Use console output from actual bug report
   - Verify post-stage actions are captured

3. Run full regression test suite:
   - Execute `tests/test-failure-analysis.sh`
   - Execute `./test/bats/bin/bats test/*.bats`
   - Verify all tests pass

4. Document test updates with spec references:
   ```bash
   # Test updated for bug1-jenkins-log-truncated-spec.md compliance
   ```

### Test Plan

**Test File:** `tests/test-failure-analysis.sh`

| Verification | Method |
|--------------|--------|
| Updated tests pass | `./tests/test-failure-analysis.sh` exits with success |
| Bats tests pass | `./test/bats/bin/bats test/*.bats` exits with 0 |
| No regressions | All existing test scenarios still pass |

**Mocking Requirements:**
- None

**Dependencies:** All previous chunks

---

## Verification Checklist

After all chunks are complete, verify:

- [x] Nested blocks handled: Stage logs include content from all nested Pipeline blocks
- [x] Post-stage included: `Post stage` actions (like `junit`) are visible in output
- [x] No truncation: All lines from stage start to stage end are displayed
- [x] Fallback works: If extraction fails, show last 50 lines with explanation
- [x] Existing tests pass: No regression in other failure analysis scenarios (22/22 passed)
- [x] All new bats tests pass: `./test/bats/bin/bats test/extract_stage_logs.bats`
- [x] Full test suite passes: `./test/bats/bin/bats test/*.bats` (33/33 passed)

---

## Manual Verification

After implementation, perform manual verification:

1. Trigger a build with failing unit tests using `pushmon.sh`
2. Verify stage logs show complete output including:
   - All nested `[Pipeline] {` and `}` blocks
   - `Post stage` section
   - `junit` recording step
3. Verify the full console URL is still provided
