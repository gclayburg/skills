When I run this command witha job that has a test failure, I do not see any aggregate information about the number of tests that succeeded, failed, or skipped.
We need to show this, even if the tests fail.


 ```
 $ buildgit --job phandlemono-IT status 73 --all

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #73
Status:     FAILURE
Trigger:    Manual by buildtriggerdude
Commit:     a916068  test: intentional test failure for buildgit diagnostics testing
            ✗ Unknown commit
Started:    2026-03-16 12:33:37
Agent:      agent8_sixcore
Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/73/console

[14:15:50] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[14:15:50] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[14:15:50] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Checkout (<1s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Check for Relevant Changes (<1s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Clean (<1s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Setup (6s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Build (13s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Test (2s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->TestContainers IT (21s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Playwright e2e IT (1m 13s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Coverage (2s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Package (1m 32s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Archive Artifacts (8s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[14:15:50] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle (4m 0s)
[14:15:50] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Declarative: Checkout SCM (<1s)
[14:15:50] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Checkout (<1s)
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Check for Relevant Changes (<1s)
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Artifactory configuration (<1s)
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->System Diagnostics (1s)
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Docker Diagnostics (3s)
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->main build (47s)    ← FAILED
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Docker Build (<1s)    ← FAILED
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Docker Push (<1s)    ← FAILED
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Deploy registerdemo (<1s)    ← FAILED
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Publish to Artifactory (<1s)    ← FAILED
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Archive Artifacts (<1s)    ← FAILED
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Publish build info (<1s)    ← FAILED
[14:15:51] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Declarative: Post Actions (<1s)
[14:15:51] ℹ   Stage:   ║2 [agent8_sixcore] Build SignalBoot (1m 14s)    ← FAILED
[14:15:51] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (4m 0s)
[14:15:51] ℹ   Stage: [agent8_sixcore] Verify Docker Images (<1s)    ← FAILED
[14:15:51] ℹ   Stage: [agent8_sixcore] Setup Handle (<1s)    ← FAILED
[14:15:51] ℹ   Stage: [agent8_sixcore] Integration Tests (<1s)    ← FAILED
[14:15:51] ℹ   Stage: [agent8_sixcore] E2E Tests (<1s)    ← FAILED
[14:15:51] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)

=== Failed Jobs ===
  → phandlemono-IT (stage: Build SignalBoot)
    → phandlemono-handle  ✓
    → phandlemono-signalboot  ← FAILED
====================

=== Test Results ===
  (no test results available)
====================

=== Error Logs ===
[2026-03-16T18:34:46.206Z] 1 test completed, 1 failed
[2026-03-16T18:34:46.106Z] SimpleSpockSpec > logs a simple message FAILED
[2026-03-16T18:34:46.305Z] > Task :handledomain:test FAILED
[2026-03-16T18:34:46.805Z]      o.s.b.a.w.s.e.BasicErrorController:
[2026-03-16T18:34:49.605Z]      o.s.b.a.w.s.e.BasicErrorController:
[2026-03-16T18:34:51.826Z]     2026-03-16T18:34:50.906Z DEBUG 636 --- [tboundChannel-7] s.w.s.s.t.s.WebSocketServerSockJsSession : Failure while sending SockJS close frame
[2026-03-16T18:34:51.826Z]     java.lang.IllegalStateException: Message will not be sent because the WebSocket session has been closed
[2026-03-16T18:34:52.806Z] FAILURE: Build failed with an exception.
[2026-03-16T18:34:52.807Z] Execution failed for task ':handledomain:test'.
[2026-03-16T18:34:52.807Z] BUILD FAILED in 46s
[2026-03-16T18:34:51.828Z]     org.signal.libsignal.protocol.DuplicateMessageException: message with old counter 1 / 0
[2026-03-16T18:34:51.828Z]      at org.signal.libsignal.internal.FilterExceptions.filterExceptions(FilterExceptions.java:362) ~[libsignal-client-0.86.5.jar:na]
[2026-03-16T18:34:51.830Z]     2026-03-16T18:34:50.916Z ERROR 636 --- [lient-AsyncIO-8] o.s.w.s.s.c.WebSocketClientSockJsSession : Ignoring received message due to state CLOSED in WebSocketClientSockJsSession[id='c54798614e084481984624f6f0a70e2b, url=ws://localhost:45119/ws-sockjs]
[2026-03-16T18:34:51.830Z]     2026-03-16T18:34:50.916Z ERROR 636 --- [lient-AsyncIO-8] o.s.w.s.s.c.WebSocketClientSockJsSession : Ignoring received message due to state CLOSED in WebSocketClientSockJsSession[id='c54798614e084481984624f6f0a70e2b, url=ws://localhost:45119/ws-sockjs]
[2026-03-16T18:34:51.832Z]      o.s.b.a.w.s.e.BasicErrorController:
[2026-03-16T18:34:53.455Z] ERROR: Couldn't execute Gradle task. RuntimeException: Gradle build failed with exit code 1
Stage "Docker Build" skipped due to earlier failure(s)
Stage "Docker Push" skipped due to earlier failure(s)
Stage "Deploy registerdemo" skipped due to earlier failure(s)
Stage "Publish to Artifactory" skipped due to earlier failure(s)
Stage "Archive Artifacts" skipped due to earlier failure(s)
Stage "Publish build info" skipped due to earlier failure(s)
[2026-03-16T18:34:55.927Z] ❌ SignalBoot build FAILED!
[2026-03-16T18:34:55.937Z] 💡 Possible failure causes:
[2026-03-16T18:34:55.947Z]   - Java compilation errors
[2026-03-16T18:34:56.019Z] 🔍 Check the specific failed stage above for detailed error information
java.lang.RuntimeException: Gradle build failed with exit code 1
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: 4d54c97c-4c6a-4845-b221-0b7cbca3bf0f
Caused: java.lang.RuntimeException: Gradle build failed. Couldn't execute Gradle task. RuntimeException: Gradle build failed with exit code 1
Finished: FAILURE
==================

Finished: FAILURE
[14:15:51] ℹ Duration: 4m 9s

1 8157 0 [03-16 14:15:51] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1 
$ buildgit --job phandlemono-IT status 73      
FAILURE     #73 id=a916068 Tests=?/?/? Took 4m 9s on 2026-03-16T12:37:47-0600 (1 hour ago)
```


This is what test results look like now for a successful build of phandlemono-IT:

```
=== Test Results ===
  Total: 19 | Passed: 19 | Failed: 0 | Skipped: 0
====================
```

phandlemono-IT is a job that calls 2 other downstream build jobs.  They both have test reports.  The root test report needs to show this as an example:

```
=== Test Results ===
phandlemono-IT      Total: 19 | Passed: 19 | Failed: 0 | Skipped: 0
  Build SignalBoot  Total: 15 | Passed: 15 | Failed: 0 | Skipped: 0
  Build Handle      Total: 83 | Passed: 83 | Failed: 0 | Skipped: 0
--------------------
Totals                    117 | Passed: 117 | Failed: 0 | Skipped: 0
====================
```

In this case, all tests succeeded. If there were failures, we still need to show the data that we have.  It might be the case that some numbers are unknonwn since the tests did not run.  In that case, the value shown should be ? to match prior expectation.  For the purposes of counting the totals in this report, a ? is considered 0.  Here is an example of a job with a test failure:

```
=== Test Results ===
phandlemono-IT       Total: ? | Passed:  ? | Failed: ? | Skipped: ? 
  Build SignalBoot  Total: 15 | Passed: 14 | Failed: 1 | Skipped: 0
  Build Handle      Total: 83 | Passed: 83 | Failed: 0 | Skipped: 0
--------------------
Totals                     98 | Passed: 98 | Failed: 1 | Skipped: 0
====================
```

Notice the alignement of the lines.  child build jobs are indented 2 spaces from the root job.  If one of the child jobs called another job, then that job would be printed by indenting another 2 spaces.  The lines should be organized using a parent-child relationship for readability.  You can easily see by looking that 'Build Signalboot' and 'Build Handle' are child jobs to 'phandlemono-IT'.  Do your best to align the output so that the numbers are right aligned for all printed lines.  There is no line length limit.  If the build job does not have call any child jobs, then the current output of showing just one line is fine.  We don't need to show a Totals line in that case.

For coloring the output, use this guide:
line with a test failure= yellow
line with all tests passing: green
line with no test data available: white

## summarized line output

All of this also impacts how we show 'status --line' output.  This is the current one line output:

```
SUCCESS     #95 id=66c0211 Tests=15/0/0 Took 3m 12s on 2026-01-22T15:11:56-0700 (7 weeks ago)
```

The format does not change with this fix.  We do, however need to change the numbers to match the 'Totals' row shown above.  We want this number to be the total number of tests for the entire project.

Note, this test aggregation shown here needs to occur whether or not any test fails, skipped, or passed.  We want to do the same thing on each build.  We just report the overall numbers to the user for the data that we can get.
