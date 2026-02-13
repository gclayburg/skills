I notice that test results are really only shown when there is a test failure of some sort.  We need to change that so that test results are always shown - both for a monitored build and a snapshot status.  This can only be done after the build has completed. For this we need one line of output:

=== Test Results ===
  Total: 407 | Passed: 376 | Failed: 1 | Skipped: 30
====================


This output needs to green if there were no failures, yellow if there were failures

This line does show up when there is a failure, so maybe we can re-use that part.