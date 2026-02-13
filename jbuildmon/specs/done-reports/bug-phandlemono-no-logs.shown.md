$ buildgit push
To ssh://scranton2:2233/home/git/phandlemono.git
   0df020c..5325e59  main -> main
[17:40:07] ℹ Waiting for Jenkins build phandlemono-IT to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #19
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     5325e59 - "always build all"
            ✓ Your commit (HEAD)
Started:    2026-02-12 17:40:12
Elapsed:    4s

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/19/console

[17:40:17] ℹ   Stage: Declarative: Checkout SCM (<1s)
[17:40:22] ℹ   Stage: Checkout (<1s)
[17:40:22] ℹ   Stage: Analyze Component Changes (<1s)
[17:40:22] ℹ   Stage: Trigger Component Builds (<1s)
[17:40:22] ℹ   Stage: Build SignalBoot (unknown)
[17:40:38] ℹ   Stage: Build Handle (14s)    ← FAILED


Finished: NOT_BUILT

$ buildgit status

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

[18:00:18] ℹ   Stage: Declarative: Checkout SCM (<1s)
[18:00:18] ℹ   Stage: Checkout (<1s)
[18:00:18] ℹ   Stage: Analyze Component Changes (<1s)
[18:00:18] ℹ   Stage: Trigger Component Builds (<1s)
[18:00:18] ℹ   Stage: Build Handle (14s)    ← FAILED
[18:00:18] ℹ   Stage: Build SignalBoot (not executed)
[18:00:18] ℹ   Stage: Verify Docker Images (not executed)
[18:00:18] ℹ   Stage: Setup Handle (not executed)
[18:00:18] ℹ   Stage: Integration Tests (not executed)
[18:00:18] ℹ   Stage: E2E Tests (not executed)

Job:        phandlemono-IT
Build:      #19
Status:     NOT_BUILT
Trigger:    Automated (git push)
Commit:     5325e59 - "always build all"
            ✓ Your commit (HEAD)
Duration:   29s
Completed:  2026-02-12 17:40:12

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

=== Failed Jobs ===
  → phandlemono-IT (stage: Build Handle)
    → phandlemono-signalboot  ✓
    → phandlemono-handle  ← FAILED
====================

=== Error Logs ===
Build failed. Please check the logs for more information.
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: 2f77ae16-4471-4c29-b32e-57092025177b
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint happy_lehmann (4834f7e13deba5ad328e9c882942a1b9cb53834323dc1fab78d51a3874d71575): Bind for 0.0.0.0:9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/19/console
