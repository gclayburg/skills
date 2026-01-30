# Implementation Plan: Bug Fix - Test Case Failure Details Not Shown

**Spec:** [bug2026-01-28-test-case-failure-not-shown-spec.md](./bug2026-01-28-test-case-failure-not-shown-spec.md)

## Contents

- [x] **Chunk A: Capture Real Jenkins testReport JSON and Create childReports Fixture**
- [x] **Chunk B: Fix parse_failed_tests() to Handle Multiple JSON Structures**

---

## Chunk Detail

---

- [x] **Chunk A: Capture Real Jenkins testReport JSON and Create childReports Fixture**

### Description

Query the Jenkins API to capture the actual testReport JSON structure from a failed build, then create a test fixture file that represents the `childReports` JSON structure. This provides the test data needed to verify the fix.

### Spec Reference

See spec [Investigation Required](./bug2026-01-28-test-case-failure-not-shown-spec.md#investigation-required) and [Test Fixture](./bug2026-01-28-test-case-failure-not-shown-spec.md#test-fixture).

### Dependencies

- None

### Produces

- `test/fixtures/test_report_childreports.json` - Test fixture with childReports structure
- `test/fixtures/test_report_direct_suites.json` - (optional) Captured real API response for documentation

### Implementation Details

1. **Query Jenkins API to capture actual structure**:
   - Execute the following command to fetch the testReport JSON (requires `JENKINS_USER_ID`, `JENKINS_API_TOKEN`, and `JENKINS_URL` environment variables):
     ```bash
     curl -s -u "$JENKINS_USER_ID:$JENKINS_API_TOKEN" \
       "$JENKINS_URL/job/ralph1/26/testReport/api/json" > /tmp/actual_test_report.json
     ```
   - Examine the JSON structure to identify whether it uses `.suites[].cases[]` or `.childReports[].result.suites[].cases[]`
   - Document findings in commit message

2. **Create test fixture for childReports structure**:
   - Create `test/fixtures/test_report_childreports.json` with the following structure:
     ```json
     {
       "failCount": 1,
       "passCount": 32,
       "skipCount": 0,
       "childReports": [
         {
           "result": {
             "failCount": 1,
             "passCount": 32,
             "skipCount": 0,
             "suites": [
               {
                 "name": "smoke.bats",
                 "cases": [
                   {
                     "className": "smoke.bats",
                     "name": "test_name",
                     "status": "FAILED",
                     "duration": 0.045,
                     "age": 1,
                     "errorDetails": "ru n true' failed with status 127",
                     "errorStackTrace": "(in test file test/smoke.bats, line 10)\n`ru n true' failed with status 127\n/home/jenkins/workspace/ralph1/jbuildmon/test/smoke.bats: line 10: ru: command not found"
                   },
                   {
                     "className": "smoke.bats",
                     "name": "passing test",
                     "status": "PASSED",
                     "duration": 0.012,
                     "age": 0
                   }
                 ]
               }
             ]
           }
         }
       ]
     }
     ```
   - Ensure the fixture has at least one FAILED test case with errorDetails and errorStackTrace
   - Include at least one PASSED test case to verify filtering works

3. **Verify fixture is valid JSON**:
   - Run `jq . test/fixtures/test_report_childreports.json` to validate

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `childreports_fixture_is_valid_json` | Verify fixture file is valid JSON | Test Fixture |
| `childreports_fixture_has_required_fields` | Verify fixture has failCount, childReports structure | Test Fixture |

**Mocking Requirements:**
- None (fixture creation only)

**Dependencies:** None

---

- [x] **Chunk B: Fix parse_failed_tests() to Handle Multiple JSON Structures**

### Description

Update the `parse_failed_tests()` function in `lib/jenkins-common.sh` to handle both the direct `.suites[].cases[]` structure and the pipeline `.childReports[].result.suites[].cases[]` structure. Add comprehensive unit tests for both structures.

### Spec Reference

See spec [Update jq Query](./bug2026-01-28-test-case-failure-not-shown-spec.md#2-update-jq-query) and [Unit Tests](./bug2026-01-28-test-case-failure-not-shown-spec.md#unit-tests).

### Dependencies

- Chunk A (test fixture file `test/fixtures/test_report_childreports.json`)

### Produces

- `lib/jenkins-common.sh` (modified `parse_failed_tests()` function)
- `test/test_results_display.bats` (new test cases)

### Implementation Details

1. **Update parse_failed_tests() jq query** in `lib/jenkins-common.sh:600-624`:
   - Modify the jq query to collect failed tests from BOTH paths:
     ```bash
     echo "$test_json" | jq -r --argjson max_display "$max_display" --argjson max_error_len "$max_error_len" '
         # Collect failed tests from direct suites path AND childReports path
         (
             [.suites[]?.cases[]? | select(.status == "FAILED")] +
             [.childReports[]?.result?.suites[]?.cases[]? | select(.status == "FAILED")]
         ) |
         # Remove duplicates (in case both paths exist)
         unique_by(.className + .name) |
         # Limit to max_display
         .[:$max_display] |
         # Transform each failed test (existing transformation logic)
         map({
             className: (.className // "unknown"),
             name: (.name // "unknown"),
             errorDetails: (
                 if (.errorDetails // "") == "" and (.errorStackTrace // "") == "" then
                     "No error details available"
                 elif (.errorDetails // "") != "" then
                     (.errorDetails | tostring | .[:$max_error_len])
                 else
                     null
                 end
             ),
             errorStackTrace: (.errorStackTrace // null),
             duration: (.duration // 0),
             age: (.age // 0)
         })
     '
     ```

2. **Add unit tests for childReports structure** in `test/test_results_display.bats`:
   - Test that `parse_failed_tests()` extracts failures from childReports structure
   - Test that it correctly extracts errorDetails and errorStackTrace
   - Test that it handles mixed structures (both paths present)

3. **Verify existing tests still pass**:
   - Run `bats test/test_results_display.bats` to ensure no regressions
   - Ensure direct `.suites[].cases[]` structure still works

4. **Add integration test for display output**:
   - Add a test that mocks `fetch_test_results()` to return childReports fixture
   - Verify `display_test_results()` shows the failed test name and stacktrace

### Test Plan

**Test File:** `test/test_results_display.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `parse_failed_tests_handles_direct_structure` | Existing tests continue to pass with `.suites[].cases[]` | Unit Tests |
| `parse_failed_tests_handles_childreports_structure` | Extracts failures from `.childReports[].result.suites[].cases[]` | Unit Tests |
| `parse_failed_tests_extracts_stacktrace_from_childreports` | Correctly extracts errorStackTrace field from childReports | Unit Tests |
| `parse_failed_tests_handles_mixed_structures` | Works when both suites and childReports are present | Unit Tests |
| `display_test_results_shows_childreports_failures` | Integration: displays failed test name and error from childReports | Integration Test |

**Mocking Requirements:**
- Mock `fetch_test_results()` to return childReports fixture for integration tests

**Dependencies:** Chunk A (childReports fixture file)

---

## Definition of Done

Per the spec [Definition of Done](./bug2026-01-28-test-case-failure-not-shown-spec.md#definition-of-done):

- [ ] Actual Jenkins testReport JSON structure documented
- [ ] `parse_failed_tests()` jq query updated to match actual structure
- [ ] Failed test names display correctly in terminal output
- [ ] Failed test stacktraces display correctly
- [ ] Unit tests pass for both JSON structure variations
- [ ] All existing tests in `test/test_results_display.bats` still pass
- [ ] Manual verification with real Jenkins build (run `checkbuild.sh` on a failed build)
