the buidlgit build and buildgit status are not consistent.  they both should show the Failed Jobs section.  the same goes for the other entrypoints like 'buildgit push', etc.


```bash
$ buildgit build
[18:46:34] ℹ Waiting for Jenkins build phandlemono-IT to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #21
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     unknown
            ✗ Unknown commit
Started:    2026-02-12 18:46:43
Elapsed:    0s

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/21/console

[18:46:49] ℹ   Stage: Declarative: Checkout SCM (<1s)
[18:46:49] ℹ   Stage: Checkout (<1s)
[18:46:49] ℹ   Stage: Analyze Component Changes (<1s)
[18:46:49] ℹ   Stage: Trigger Component Builds (<1s)
[18:46:49] ℹ   Stage: Build SignalBoot (unknown)
[18:47:00] ℹ   Stage: Build Handle (9s)    ← FAILED
[18:50:10] ℹ   Stage: Verify Docker Images (<1s)    ← FAILED
[18:50:10] ℹ   Stage: Setup Handle (<1s)    ← FAILED
[18:50:10] ℹ   Stage: Integration Tests (<1s)    ← FAILED
[18:50:10] ℹ   Stage: E2E Tests (<1s)    ← FAILED
[18:50:10] ℹ   Stage: Declarative: Post Actions (<1s)


=== Error Logs ===
Build failed. Please check the logs for more information.
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: f10e2bba-4dd4-411a-8e2d-1bc8f0f7abe2
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint cranky_napier (41e0d48bb8c79b6230e99fb5d404487b1891fa36e509b72e97507e1ddfa946d0): Bind for 0.0.0.0:9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Finished: FAILURE

1 2752 0 [02-12 18:50:15] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/phandlemono/modules/handle 
$ buildgit status

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

[18:50:28] ℹ   Stage: Declarative: Checkout SCM (<1s)
[18:50:28] ℹ   Stage: Checkout (<1s)
[18:50:28] ℹ   Stage: Analyze Component Changes (<1s)
[18:50:28] ℹ   Stage: Trigger Component Builds (<1s)
[18:50:28] ℹ   Stage: Build Handle (9s)    ← FAILED
[18:50:28] ℹ   Stage: Build SignalBoot (3m 20s)
[18:50:28] ℹ   Stage: Verify Docker Images (<1s)    ← FAILED
[18:50:28] ℹ   Stage: Setup Handle (<1s)    ← FAILED
[18:50:28] ℹ   Stage: Integration Tests (<1s)    ← FAILED
[18:50:28] ℹ   Stage: E2E Tests (<1s)    ← FAILED
[18:50:28] ℹ   Stage: Declarative: Post Actions (<1s)

Job:        phandlemono-IT
Build:      #21
Status:     FAILURE
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     5325e59 - "always build all"
            ✓ Your commit (HEAD)
Duration:   3m 26s
Completed:  2026-02-12 18:46:43

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

=== Failed Jobs ===
  → phandlemono-IT (stage: Build Handle)
    → phandlemono-handle  ← FAILED
    → phandlemono-signalboot  ✓
====================

=== Error Logs ===
Build failed. Please check the logs for more information.
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: f10e2bba-4dd4-411a-8e2d-1bc8f0f7abe2
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint cranky_napier (41e0d48bb8c79b6230e99fb5d404487b1891fa36e509b72e97507e1ddfa946d0): Bind for 0.0.0.0:9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/21/console
```