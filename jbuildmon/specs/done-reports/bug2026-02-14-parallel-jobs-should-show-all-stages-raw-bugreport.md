I get this when I run status on a job that has parallel stages:

```bash
$ buildgit --job phandlemono-IT status

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #31
Status:     FAILURE
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     3805e2b - "build now"
            ✓ Your commit (HEAD)
Started:    2026-02-13 17:56:17

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/31/console

[18:33:28] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[18:33:28] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[18:33:28] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[18:33:28] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (3m 25s)
[18:33:28] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[18:33:28] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[18:33:28] ℹ   Stage:   ║ [agent8_sixcore] Build Handle (13s)    ← FAILED
[18:33:28] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot->Declarative: Checkout SCM (<1s)
[18:33:28] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot->Declarative: Post Actions (<1s)
[18:33:28] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot (3m 25s)
[18:33:28] ℹ   Stage: [agent8_sixcore] Verify Docker Images (<1s)    ← FAILED
[18:33:28] ℹ   Stage: [agent8_sixcore] Setup Handle (<1s)    ← FAILED
[18:33:28] ℹ   Stage: [agent8_sixcore] Integration Tests (<1s)    ← FAILED
[18:33:28] ℹ   Stage: [agent8_sixcore] E2E Tests (<1s)    ← FAILED
[18:33:28] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)

=== Failed Jobs ===
  → phandlemono-IT (stage: Build Handle)
    → phandlemono-handle  ← FAILED
    → phandlemono-signalboot  ✓
====================

=== Test Results ===
  (no test results available)
====================

=== Error Logs ===
Build failed. Please check the logs for more information.
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: d9ea2864-5bca-45d1-a0a9-c8e809e89ad0
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint objective_euclid (80a697cb016ab47142355aa65d17d6d933d7b4e9a9bf544512804897a1fd6eef): Bind for 0.0.0.0:9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Finished: FAILURE
[18:33:28] ℹ Duration: 3m 32s
```

as you can see, the status does show that the 'SignalBoot' job did run, but it did not show any of the stages of that build job when it ran.  If I inspect the jenkins console dirctly, I can see that the signalboot job did run.  And it took 3m 25s, but it also had many stages within it.  I need the status command to show me those stages in a way that aligns with the specs in the spec folder.
