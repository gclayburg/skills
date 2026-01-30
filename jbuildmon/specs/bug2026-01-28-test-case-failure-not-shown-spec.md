# Bug: Test Case Failure Details Not Shown in Terminal Output
Date: 2026-01-28

## Summary

When a build fails due to test failures, `pushmon.sh` and `checkbuild.sh` display the test summary counts correctly but do not show the individual failed test names or error details. The "FAILED TESTS:" section appears but is empty.

## Observed Behavior

The output shows:
```
=== Test Results ===
  Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0

  FAILED TESTS:
====================
```

The test count summary is correct (1 failed), but no test case details appear below "FAILED TESTS:".

## Expected Behavior

The output should show failed test details with stacktrace, matching the Jenkins web UI format:
```
=== Test Results ===
  Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0

  FAILED TESTS:
  ✗ smoke.bats::test_name
    Stacktrace
    (in test file test/smoke.bats, line 10)
      `ru n true' failed with status 127
    /home/jenkins/workspace/ralph1/jbuildmon/test/smoke.bats: line 10: ru: command not found
====================
```

## Root Cause Analysis

### Working Component

The `parse_test_summary()` function in `lib/jenkins-common.sh:544-575` correctly extracts summary counts from the top-level fields of the Jenkins testReport API response:
- `failCount`
- `passCount`
- `skipCount`

### Failing Component

The `parse_failed_tests()` function in `lib/jenkins-common.sh:581-625` uses this jq query to find failed tests:

```bash
[.suites[]?.cases[]? | select(.status == "FAILED")]
```

This query assumes the Jenkins testReport API returns test cases at the path `.suites[].cases[]`. However, the actual JSON structure returned by Jenkins may differ.

### Likely Cause

The Jenkins testReport API structure varies depending on:
1. Job type (freestyle vs pipeline)
2. Number of test result publishers
3. Jenkins junit plugin version

Common alternative structures include:
- `.childReports[].result.suites[].cases[]` (pipeline jobs with multiple test publishers)
- `.suites[].cases[]` with different status field values
- Nested result objects

### Investigation Required

To confirm the exact structure, query the Jenkins API directly:
```bash
curl -s -u "$JENKINS_USER_ID:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/ralph1/26/testReport/api/json" | jq .
```

## Affected Files

| File | Function | Issue |
|------|----------|-------|
| `lib/jenkins-common.sh` | `parse_failed_tests()` | jq query path doesn't match actual JSON structure |

## Solution

### 1. Inspect Actual JSON Structure

Add debug logging or manual inspection to determine the actual testReport JSON structure from Jenkins.

### 2. Update jq Query

Modify `parse_failed_tests()` to handle the actual JSON structure. The fix may involve:
- Changing the path from `.suites[]?.cases[]?` to the correct path
- Adding fallback paths to handle multiple JSON structures
- Adjusting the status field comparison if needed

### 3. Example Fix Pattern

If the structure is `.childReports[].result.suites[].cases[]`:
```bash
echo "$test_json" | jq -r '
    # Try direct suites path first, then childReports path
    ([.suites[]?.cases[]? | select(.status == "FAILED")] +
     [.childReports[]?.result?.suites[]?.cases[]? | select(.status == "FAILED")]) |
    unique_by(.className + .name) |
    .[:$max_display] |
    ...
'
```

## Testing Requirements

### Unit Tests

Add to `test/test_results_display.bats`:

| Test Case | Description |
|-----------|-------------|
| `parse_failed_tests_handles_direct_structure` | Works with `.suites[].cases[]` structure |
| `parse_failed_tests_handles_childreports_structure` | Works with `.childReports[].result.suites[].cases[]` structure |
| `parse_failed_tests_extracts_stacktrace` | Correctly extracts `errorStackTrace` field |

### Integration Test

Verify with actual Jenkins build that failed tests display correctly:
1. Create a test that intentionally fails
2. Run `checkbuild.sh` and verify failed test name appears
3. Verify stacktrace/error details appear

### Test Fixture

Create `test/fixtures/test_report_childreports.json` with the childReports structure for testing.

## Relationship to Other Specs

This bug is related to `test-failure-display-spec.md`, which defined the original feature. The feature was implemented per the plan (`test-failure-display-plan.md`, all chunks marked complete), but the implementation doesn't work with the actual Jenkins API response structure.

## Definition of Done

- [ ] Actual Jenkins testReport JSON structure documented
- [ ] `parse_failed_tests()` jq query updated to match actual structure
- [ ] Failed test names display correctly in terminal output
- [ ] Failed test stacktraces display correctly
- [ ] Unit tests pass for both JSON structure variations
- [ ] Manual verification with real Jenkins build
