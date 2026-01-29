# Test Failure Display Enhancement - Implementation Plan

## Contents

- [x] **Chunk A: fetch_test_results Function**
- [x] **Chunk B: parse_test_summary Function**
- [x] **Chunk C: parse_failed_tests Function**
- [x] **Chunk D: display_test_results Function**
- [x] **Chunk E: format_test_results_json Function**
- [x] **Chunk F: Integration into Display Flow**

---

## Chunk Detail

---

- [x] **Chunk A: fetch_test_results Function**

### Description

Add a function to `jenkins-common.sh` that queries the Jenkins test report API for a given job and build number. Returns the raw JSON test report data or empty string if no test results are available.

### Spec Reference

See spec [Test Report Detection](./test-failure-display-spec.md#1-test-report-detection) sections 1.1-1.2.

### Dependencies

- None (uses existing `jenkins_api` and `jenkins_api_with_status` functions)

### Produces

- `lib/jenkins-common.sh` (modified - add `fetch_test_results` function)
- `test/test_results_display.bats` (new file with initial tests)

### Implementation Details

1. Add `fetch_test_results` function to `jenkins-common.sh`:
   - Takes job_name and build_number as parameters
   - Constructs API endpoint: `/job/${JOB_NAME}/${BUILD_NUMBER}/testReport/api/json`
   - Uses `jenkins_api_with_status` to handle HTTP response codes
   - Returns empty string on 404 (no test results available)
   - Returns JSON on 200 success
   - Logs warning and returns empty on other errors

2. Add default configuration variables at top of library:
   - `MAX_FAILED_TESTS_DISPLAY` default 10
   - `MAX_ERROR_LINES` default 5
   - `MAX_ERROR_LENGTH` default 500

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `fetch_test_results_returns_empty_on_404` | Mock API returns 404, function returns empty | 1.2 |
| `fetch_test_results_returns_json_on_200` | Mock API returns 200 with JSON, function returns JSON | 1.1 |
| `fetch_test_results_returns_empty_on_error` | Mock API returns 500, function returns empty | Error Handling |

**Mocking Requirements:**
- Mock `jenkins_api_with_status` function to simulate API responses
- Use test fixtures with sample test report JSON

**Dependencies:** None

---

- [x] **Chunk B: parse_test_summary Function**

### Description

Add a function to parse the test report JSON and extract summary statistics (total, passed, failed, skipped counts).

### Spec Reference

See spec [Summary Statistics](./test-failure-display-spec.md#21-summary-statistics) section 2.1.

### Dependencies

- Chunk A (`fetch_test_results` provides the JSON input)

### Produces

- `lib/jenkins-common.sh` (modified - add `parse_test_summary` function)
- `test/test_results_display.bats` (modified - add summary tests)

### Implementation Details

1. Add `parse_test_summary` function:
   - Takes test report JSON as input
   - Uses `jq` to extract `failCount`, `passCount`, `skipCount`
   - Calculates total count
   - Outputs four lines: total, passed, failed, skipped
   - Handles missing fields with defaults (0)

2. Example output format:
   ```
   33
   32
   1
   0
   ```

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `parse_test_summary_extracts_counts` | Extracts correct counts from valid JSON | 2.1 |
| `parse_test_summary_handles_missing_failcount` | Missing failCount defaults to 0 | Error Handling |
| `parse_test_summary_handles_missing_passcount` | Missing passCount defaults to 0 | Error Handling |
| `parse_test_summary_handles_empty_json` | Empty/invalid JSON returns zeros | Error Handling |

**Mocking Requirements:**
- Test fixtures with various JSON structures

**Dependencies:** None (function is pure JSON parsing)

---

- [x] **Chunk C: parse_failed_tests Function**

### Description

Add a function to extract detailed information about each failed test case from the test report JSON.

### Spec Reference

See spec [Failed Test Details](./test-failure-display-spec.md#22-failed-test-details) and [Test Case Iteration](./test-failure-display-spec.md#23-test-case-iteration) sections 2.2-2.3.

### Dependencies

- Chunk A (`fetch_test_results` provides the JSON input)

### Produces

- `lib/jenkins-common.sh` (modified - add `parse_failed_tests` function)
- `test/test_results_display.bats` (modified - add failed test parsing tests)

### Implementation Details

1. Add `parse_failed_tests` function:
   - Takes test report JSON as input
   - Uses `jq` to iterate through `suites[].cases[]`
   - Filters for cases where `status == "FAILED"`
   - Extracts for each failed test:
     - `className`
     - `name`
     - `errorDetails` (may be null)
     - `errorStackTrace` (may be null)
     - `duration`
     - `age`
   - Outputs JSON array of failed test objects
   - Respects `MAX_FAILED_TESTS_DISPLAY` limit

2. Handle edge cases:
   - Missing className/name: use "unknown"
   - Missing errorDetails AND errorStackTrace: use "No error details available"
   - Truncate errorDetails to `MAX_ERROR_LENGTH` characters

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `parse_failed_tests_extracts_details` | Extracts all fields from failed test | 2.2 |
| `parse_failed_tests_filters_by_status` | Only includes FAILED tests, not PASSED | 2.3 |
| `parse_failed_tests_handles_missing_errordetails` | Missing errorDetails handled gracefully | Error Handling |
| `parse_failed_tests_handles_missing_classname` | Missing className defaults to "unknown" | Error Handling |
| `parse_failed_tests_respects_max_limit` | Limits output to MAX_FAILED_TESTS_DISPLAY | 3.3 |
| `parse_failed_tests_truncates_long_errors` | Long errors truncated to MAX_ERROR_LENGTH | 3.3 |

**Mocking Requirements:**
- Test fixtures with various test report structures
- Fixtures with missing fields
- Fixtures with many failed tests (>10)

**Dependencies:** None (function is pure JSON parsing)

---

- [x] **Chunk D: display_test_results Function**

### Description

Add a function to format and print test results in human-readable format to the terminal.

### Spec Reference

See spec [Human-Readable Output](./test-failure-display-spec.md#3-human-readable-output) sections 3.1-3.3.

### Dependencies

- Chunk B (`parse_test_summary` for summary stats)
- Chunk C (`parse_failed_tests` for failed test details)

### Produces

- `lib/jenkins-common.sh` (modified - add `display_test_results` function)
- `test/test_results_display.bats` (modified - add display tests)

### Implementation Details

1. Add `display_test_results` function:
   - Takes test report JSON as input
   - Calls `parse_test_summary` to get counts
   - Calls `parse_failed_tests` to get failed test array
   - Formats output according to spec:

   ```
   === Test Results ===
     Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0

     FAILED TESTS:
     ✗ test_helper.bats::TEST_TEMP_DIR is unique per test run
       Error: [[: command not found
       (in test file test/test_helper.bats, line 74)
   ====================
   ```

2. Handle special cases:
   - All tests passed: add "(All tests passed - failure may be from other causes)"
   - Recurring failures (age > 1): add "(failing for N builds)"
   - More than 10 failures: show "... and N more failed tests"
   - Truncate stack traces to `MAX_ERROR_LINES` lines

3. Use existing color variables from jenkins-common.sh (`COLOR_YELLOW`, `COLOR_RED`, etc.)

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `display_test_results_shows_summary` | Displays summary line with all counts | 3.1 |
| `display_test_results_shows_failed_details` | Shows className::name format for failed tests | 3.2 |
| `display_test_results_shows_all_passed_message` | Shows special message when all tests pass | 3.1 |
| `display_test_results_shows_recurring_failure` | Shows "failing for N builds" when age > 1 | 3.2 |
| `display_test_results_truncates_many_failures` | Shows "... and N more" when > 10 failures | 3.3 |
| `display_test_results_truncates_stacktrace` | Truncates stack trace to MAX_ERROR_LINES | 3.3 |

**Mocking Requirements:**
- Disable colors for testing (set NO_COLOR=1)
- Various test report fixtures

**Dependencies:** Chunk B, Chunk C functions

---

- [x] **Chunk E: format_test_results_json Function**

### Description

Add a function to format test results as a JSON object for inclusion in checkbuild.sh JSON output.

### Spec Reference

See spec [JSON Output Enhancement](./test-failure-display-spec.md#4-json-output-enhancement) sections 4.1-4.3.

### Dependencies

- Chunk B (`parse_test_summary` for counts)
- Chunk C (`parse_failed_tests` for failed test array)

### Produces

- `lib/jenkins-common.sh` (modified - add `format_test_results_json` function)
- `test/test_results_display.bats` (modified - add JSON format tests)

### Implementation Details

1. Add `format_test_results_json` function:
   - Takes test report JSON as input
   - Returns JSON object in this format:
   ```json
   {
     "total": 33,
     "passed": 32,
     "failed": 1,
     "skipped": 0,
     "failed_tests": [
       {
         "class_name": "test_helper.bats",
         "test_name": "TEST_TEMP_DIR is unique per test run",
         "duration_seconds": 0.045,
         "age": 3,
         "error_details": "[[: command not found",
         "error_stack_trace": "(in test file test/test_helper.bats, line 74)..."
       }
     ]
   }
   ```

2. If no test results available, return empty string (caller should omit field)

3. Use `jq` to build properly escaped JSON output

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `format_test_results_json_valid_structure` | Output is valid JSON with required fields | 4.1 |
| `format_test_results_json_correct_counts` | Counts match input data | 4.1 |
| `format_test_results_json_failed_tests_array` | failed_tests array populated correctly | 4.1 |
| `format_test_results_json_empty_on_no_results` | Returns empty when no test data | 4.3 |

**Mocking Requirements:**
- Test fixtures with various test results

**Dependencies:** Chunk B, Chunk C functions

---

- [x] **Chunk F: Integration into Display Flow**

### Description

Integrate the test results functions into the existing `display_failure_output` and `output_json` functions in `jenkins-common.sh`, and update checkbuild.sh to use the new functionality.

### Spec Reference

See spec [Integration Points](./test-failure-display-spec.md#5-integration-points) and [Output Ordering](./test-failure-display-spec.md#6-output-ordering) sections 5-6.

### Dependencies

- Chunk A (`fetch_test_results`)
- Chunk D (`display_test_results`)
- Chunk E (`format_test_results_json`)

### Produces

- `lib/jenkins-common.sh` (modified - update `display_failure_output`, `output_json`)
- `test/test_results_display.bats` (modified - add integration tests)

### Implementation Details

1. Modify `display_failure_output` function:
   - After "Failed Jobs" section and before "Error Logs" section
   - Call `fetch_test_results` to get test report data
   - If test results exist, call `display_test_results`
   - Maintain existing error log display behavior

2. Modify `output_json` function:
   - After calling `_build_failure_json`
   - Call `fetch_test_results` to get test report data
   - If test results exist, call `format_test_results_json`
   - Add `test_results` field to JSON output (after `failure`, before `build_info`)
   - If no test results, omit the field entirely

3. Verify output ordering per spec section 6:
   1. Build banner
   2. Build summary
   3. Build Info section
   4. Failed Jobs section
   5. **Test Results section (NEW)**
   6. Error Logs section
   7. Console URL

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `integration_display_shows_test_results` | Test results appear in failure output | 5.1 |
| `integration_display_correct_ordering` | Test results between Failed Jobs and Error Logs | 6 |
| `integration_display_skips_when_no_tests` | No test section when API returns 404 | 1.2 |
| `integration_json_includes_test_results` | JSON output includes test_results field | 5.1 |
| `integration_json_omits_when_no_tests` | JSON omits test_results when not available | 4.3 |

**Mocking Requirements:**
- Mock `jenkins_api_with_status` for test report API
- Mock `get_console_output` for existing failure analysis
- Test fixtures for complete failure scenarios

**Dependencies:** Chunks A, D, E

---

## Test Fixture Data

Create `test/fixtures/test_report_1_failure.json`:
```json
{
  "failCount": 1,
  "passCount": 32,
  "skipCount": 0,
  "suites": [
    {
      "name": "test_helper.bats",
      "cases": [
        {
          "className": "test_helper.bats",
          "name": "TEST_TEMP_DIR is unique per test run",
          "status": "FAILED",
          "duration": 0.045,
          "age": 1,
          "errorDetails": "[[: command not found",
          "errorStackTrace": "(in test file test/test_helper.bats, line 74)\n`assert [[ \"${TEST_TEMP_DIR}\" == /tmp/* ]]' failed"
        },
        {
          "className": "test_helper.bats",
          "name": "passing test",
          "status": "PASSED",
          "duration": 0.012,
          "age": 0,
          "errorDetails": null,
          "errorStackTrace": null
        }
      ]
    }
  ]
}
```

Create `test/fixtures/test_report_all_passed.json`:
```json
{
  "failCount": 0,
  "passCount": 33,
  "skipCount": 0,
  "suites": [
    {
      "name": "test_helper.bats",
      "cases": [
        {
          "className": "test_helper.bats",
          "name": "test 1",
          "status": "PASSED",
          "duration": 0.01,
          "age": 0
        }
      ]
    }
  ]
}
```

Create `test/fixtures/test_report_many_failures.json` (>10 failures for truncation testing)

---

## Definition of Done

For each chunk:
- [ ] All unit tests written for the chunk have been executed and pass
- [ ] All existing project tests continue to pass
- [ ] Code follows existing patterns in `jenkins-common.sh`
- [ ] Functions are portable (sh-compatible, no bash-specific features unless necessary)
- [ ] Test cases document the spec section they verify
