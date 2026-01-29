# Test Failure Display Enhancement

## Overview

Enhance `checkbuild.sh` and `pushmon.sh` to display test failure information from Jenkins junit reports. When a build is marked UNSTABLE or FAILURE due to test failures, the scripts should display which tests failed, how many failed, and the error details - all in the terminal without requiring additional tool invocations or web UI access.

## Problem Statement

### Current Behavior

When a Jenkins build fails due to test failures:
1. The build is marked UNSTABLE or FAILURE
2. The scripts show "BUILD FAILED" with the failed stage name
3. Console log snippets are shown from the stage
4. **No information about which tests failed or why**

Users (including AI agents) must manually:
- Query the Jenkins test report API
- Parse the response to find failed tests
- Extract error details

### Observed Issue (2026-01-28)

During a debugging session, a build was marked UNSTABLE. The `checkbuild.sh` output showed:
```
=== Failed Jobs ===
  → ralph1 (stage: Unit Tests)  ← FAILED
====================

=== Error Logs ===
[Pipeline] sh
+ ./test/bats/bin/bats --formatter junit test/*.bats
+ true
...
```

This output was insufficient to diagnose the problem. Additional manual API queries were required to discover:
- 1 test failed out of 33
- Test name: "TEST_TEMP_DIR is unique per test run"
- Error: `[[: command not found` (bash compatibility issue)

### Desired Behavior

The scripts should automatically fetch and display test results when available:
```
=== Failed Jobs ===
  → ralph1 (stage: Unit Tests)  ← FAILED
====================

=== Test Results ===
  Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0

  FAILED TESTS:
  ✗ test_helper.bats::TEST_TEMP_DIR is unique per test run
    Error: [[: command not found
    (in test file test/test_helper.bats, line 74)
    `assert [[ "${TEST_TEMP_DIR}" == /tmp/* ]]' failed
====================

=== Error Logs ===
...
```

---

## Functional Requirements

### 1. Test Report Detection

#### 1.1 Check for Test Results

After a build completes with FAILURE or UNSTABLE status:
1. Query the Jenkins test report API: `GET /job/${JOB_NAME}/${BUILD_NUMBER}/testReport/api/json`
2. If the API returns 404, no test results are available (skip test display)
3. If the API returns 200, parse and display test results

#### 1.2 Handle Missing Test Reports

Not all builds have junit test results. The feature must gracefully handle:
- Builds without test stages
- Test stages that don't produce junit XML
- junit XML that wasn't published

When no test report exists, continue with existing behavior (console log analysis only).

### 2. Test Result Extraction

#### 2.1 Summary Statistics

Extract from the test report API response:
- `failCount`: Number of failed tests
- `passCount`: Number of passed tests
- `skipCount`: Number of skipped tests
- Total count: `failCount + passCount + skipCount`

#### 2.2 Failed Test Details

For each failed test case, extract:
- `className`: The test file or class (e.g., `test_helper.bats`)
- `name`: The test name (e.g., `TEST_TEMP_DIR is unique per test run`)
- `errorDetails`: Brief error description (may be null)
- `errorStackTrace`: Full error trace with file/line information
- `duration`: How long the test ran
- `age`: How many consecutive builds this test has been failing

#### 2.3 Test Case Iteration

The test report structure is:
```json
{
  "suites": [
    {
      "name": "suite-name",
      "cases": [
        {
          "className": "test_file.bats",
          "name": "test_name",
          "status": "PASSED|FAILED|SKIPPED",
          "errorDetails": "...",
          "errorStackTrace": "..."
        }
      ]
    }
  ]
}
```

Iterate through `suites[].cases[]` to find all cases where `status == "FAILED"`.

### 3. Human-Readable Output

#### 3.1 Test Summary Section

Display after the "Failed Jobs" section and before "Error Logs":

```
=== Test Results ===
  Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0
```

If all tests passed but build still failed, show:
```
=== Test Results ===
  Total: 33 | Passed: 33 | Failed: 0 | Skipped: 0
  (All tests passed - failure may be from other causes)
```

#### 3.2 Failed Test Details

For each failed test (limit to first 10 to avoid overwhelming output):

```
  FAILED TESTS:
  ✗ [className]::[name]
    Error: [first line of errorDetails or errorStackTrace]
    [additional context lines, truncated if > 5 lines]
```

If `age > 1`, indicate this is a recurring failure:
```
  ✗ test_helper.bats::failing_test (failing for 3 builds)
```

#### 3.3 Truncation Rules

- Show at most 10 failed tests in detail
- If more than 10 failures, show: `  ... and 5 more failed tests`
- Truncate individual error messages to 500 characters
- Truncate stack traces to 5 lines with `...` indicator

### 4. JSON Output Enhancement

#### 4.1 New `test_results` Field

Add to the JSON output structure:

```json
{
  "test_results": {
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
}
```

#### 4.2 Field Placement

The `test_results` field should appear:
- After `failure` object (if present)
- Before `build_info` object

#### 4.3 Absent Test Results

If no test report is available, omit the `test_results` field entirely (do not include with null/empty values).

### 5. Integration Points

#### 5.1 checkbuild.sh

Modify `display_failure_output` function to:
1. Call new `fetch_test_results` function
2. Call new `display_test_results` function
3. Maintain existing console log display after test results

Modify `output_json` function to:
1. Call `fetch_test_results` function
2. Include test results in JSON structure

#### 5.2 pushmon.sh

The `handle_build_result` function calls shared library functions.
Changes to `jenkins-common.sh` will automatically apply to both scripts.

#### 5.3 jenkins-common.sh

Add new functions to the shared library:
- `fetch_test_results`: Query test report API, return JSON or empty
- `parse_test_summary`: Extract summary statistics
- `parse_failed_tests`: Extract failed test details
- `display_test_results`: Format and print test results
- `format_test_results_json`: Format test results for JSON output

### 6. Output Ordering

The failure output sections should appear in this order:

1. Build banner (`BUILD FAILED`)
2. Build summary (job, build#, status, trigger, commit, duration)
3. Build Info section (started by, agent, pipeline)
4. Failed Jobs section (job tree with failure indicator)
5. **Test Results section (NEW)** - summary + failed test details
6. Error Logs section (console log snippets)
7. Console URL

---

## Error Handling

### API Failures

- If test report API returns 404: Silently skip test results display
- If test report API returns other error: Log warning, continue without test results
- If JSON parsing fails: Log warning, continue without test results

### Malformed Data

- Missing `failCount`: Default to 0
- Missing `className` or `name`: Use "unknown"
- Missing `errorDetails` AND `errorStackTrace`: Show "No error details available"

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_FAILED_TESTS_DISPLAY` | `10` | Maximum failed tests to show in detail |
| `MAX_ERROR_LINES` | `5` | Maximum lines per error stack trace |
| `MAX_ERROR_LENGTH` | `500` | Maximum characters per error message |

---

## Testing Requirements

### Unit Tests (bats)

Create `test/test_results_display.bats` with tests for:

- [ ] `fetch_test_results` returns empty when API returns 404
- [ ] `fetch_test_results` returns JSON when API returns 200
- [ ] `parse_test_summary` extracts correct counts
- [ ] `parse_failed_tests` extracts failed test details
- [ ] `parse_failed_tests` handles missing errorDetails gracefully
- [ ] `display_test_results` formats output correctly
- [ ] `display_test_results` truncates long error messages
- [ ] `display_test_results` limits to MAX_FAILED_TESTS_DISPLAY
- [ ] `format_test_results_json` produces valid JSON structure

### Integration Tests

- [ ] Full checkbuild.sh run with mock test failure data
- [ ] Full pushmon.sh run showing test failures after build completes
- [ ] JSON output includes test_results when available
- [ ] JSON output omits test_results when not available

### Manual Testing Checklist

- [ ] Build with passing tests shows summary only
- [ ] Build with failing tests shows details
- [ ] Build without junit results shows no test section
- [ ] Very long error messages are truncated appropriately
- [ ] Many failing tests (>10) are summarized correctly

---

## Implementation Notes

### Phase 1: Library Functions

1. Add `fetch_test_results` to `jenkins-common.sh`
2. Add `parse_test_summary` to `jenkins-common.sh`
3. Add `parse_failed_tests` to `jenkins-common.sh`
4. Add `display_test_results` to `jenkins-common.sh`
5. Add `format_test_results_json` to `jenkins-common.sh`

### Phase 2: Integration

1. Modify `analyze_failure` to call test result functions
2. Modify `output_json` to include test results
3. Update both scripts to use new functionality

### Phase 3: Testing

1. Create mock test report data for unit tests
2. Implement bats tests for new functions
3. Manual verification with real Jenkins builds

---

## Compatibility

- Requires Jenkins junit plugin to be installed and configured
- Works with any test framework that produces junit XML (bats, JUnit, pytest, etc.)
- Backward compatible: builds without test results continue to work as before
