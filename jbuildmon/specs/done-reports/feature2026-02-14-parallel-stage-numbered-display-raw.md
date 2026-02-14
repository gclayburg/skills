There are a few issues here with build jobs that run in parallel.   The first is that it isn't easy to see at a glance which tasks are running at the same time when looking at a log output.  We are using the || symbol  to sort of show that,but it is confusing. 

consider a part of Jenkins file with a parallel stage like this:

```groovy
        stage('Trigger Component Builds') {
            parallel {
                stage('Build Handle') {
                    when {
                        expression { env.SHOULD_BUILD_HANDLE == 'true' }
                    }
                    steps {
                        echo "🚀 Triggering phandlemono-handle build..."
                        script {
                            def handleBuild = build job: 'phandlemono-handle', wait: true, propagate: true
                            echo "✅ phandlemono-handle build #${handleBuild.number} completed successfully"
                        }
                    }
                }
                stage('Build SignalBoot') {
                    when {
                        expression { env.SHOULD_BUILD_SIGNALBOOT == 'true' }
                    }
                    steps {
                        echo "🚀 Triggering phandlemono-signalboot build..."
                        script {
                            def signalbootBuild = build job: 'phandlemono-signalboot', wait: true, propagate: true
                            echo "✅ phandlemono-signalboot build #${signalbootBuild.number} completed successfully"
                        }
                    }
                }
            }
        }
```

Build Handle starts at the same tiem as Build Signalboot.  We want to show the name of the stage in the log after it has been run so that we know the execution time and if it failed or not.

We need to replace the || part of the output with a number that corresponds to the parallel stage.  For example, in the log of 'buildgit build' we see this now:

```
[00:03:31] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[00:03:31] ℹ   Stage:   ║ [agent7] Build SignalBoot->Declarative: Checkout SCM (<1s)
[00:03:37] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[00:03:37] ℹ   Stage:   ║ [agent7] Build SignalBoot->Checkout (<1s)
[00:03:37] ℹ   Stage:   ║ [agent7] Build SignalBoot->Check for Relevant Changes (<1s)
```

What I would like to see instead is a little more visual display of the parallel stages:

```
[00:03:31] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[00:03:31] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Declarative: Checkout SCM (<1s)
[00:03:37] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[00:03:37] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Checkout (<1s)
[00:03:37] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Check for Relevant Changes (<1s)
```

There are 2 parallel stages here.  They are labeled 1 and 2.  In this case, each parallel track is being executed on a different build agent, but they may not always be.  Notice also we want to pad the display of the build agent to 14 characters.  Longer agent names would be truncated to fit.

So when parallel stages are started, we need to number them starting at 1 and continuing for as many parallel stages as necessary.  For example, in the Jenkins snippet shown above, there are 2 parallel stages, Build Handle and Build SignalBoot.  Each of these also starts another build job.  They may also spawn more parallel stages just as shown above.  If this happens, we need to show that with an extra identifier like this.  In this case there are another 2 parallel stages started from a parallel stage started previously that was number 3:

```
[00:03:31] ℹ   Stage:   ║3║1 [agent14        ] <desciption of nested parallel stage 1> (<1s)
[00:03:37] ℹ   Stage:   ║3║2 [agent15        ] <description of nested parallel stage 2> (<1s)
```


## Current state of the output today

Here is the output when the build is run and when we do status on that same build immediately after.  We see different results for the running stages for 'buildgit build' and 'buildgit status'.  I want to understand why this is.  It would be ideal if both the monitoring case and the snapshot case of showting the build status were similar, if not identical.  I'm wondering if there is a timing issue, since in the monitoring case, we always want to show the status of a stage only after it has been completed.


```bash
$ buildgit --job phandlemono-IT build
[00:03:04] ℹ Waiting for Jenkins build phandlemono-IT to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #33
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Started:    2026-02-14 00:03:13

=== Build Info ===
  Started by:  Ralph AI Read Only
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/33/console

Commit:     3805e2b - "build now"
            ✓ Your commit (HEAD)
[00:03:20] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[00:03:20] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[00:03:20] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[00:03:20] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot (unknown)
[00:03:31] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[00:03:31] ℹ   Stage:   ║ [agent7] Build SignalBoot->Declarative: Checkout SCM (<1s)
[00:03:37] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[00:03:37] ℹ   Stage:   ║ [agent7] Build SignalBoot->Checkout (<1s)
[00:03:37] ℹ   Stage:   ║ [agent7] Build SignalBoot->Check for Relevant Changes (<1s)
[00:03:37] ℹ   Stage:   ║ [agent7] Build SignalBoot->Artifactory configuration (<1s)
[00:03:37] ℹ   Stage:   ║ [agent7] Build SignalBoot->System Diagnostics (2s)
[00:03:37] ℹ   Stage:   ║ [agent8_sixcore] Build Handle (13s)    ← FAILED
[00:03:37] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (13s)
[00:03:42] ℹ   Stage:   ║ [agent7] Build SignalBoot->Docker Diagnostics (4s)
[00:04:42] ℹ   Stage:   ║ [agent7] Build SignalBoot->main build (1m 1s)
[00:05:04] ℹ   Stage:   ║ [agent7] Build SignalBoot->Docker Build (20s)
[00:05:15] ℹ   Stage:   ║ [agent7] Build SignalBoot->Docker Push (8s)
[00:05:26] ℹ   Stage:   ║ [agent7] Build SignalBoot->Deploy registerdemo (12s)
[00:06:05] ℹ   Stage:   ║ [agent7] Build SignalBoot->Publish to Artifactory (37s)
[00:06:44] ℹ   Stage:   ║ [agent7] Build SignalBoot->Archive Artifacts (38s)
[00:06:44] ℹ   Stage:   ║ [agent7] Build SignalBoot->Publish build info (<1s)
[00:06:44] ℹ   Stage:   ║ [agent7] Build SignalBoot->Declarative: Post Actions (2s)
[00:06:50] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot (3m 25s)
[00:06:50] ℹ   Stage: [agent8_sixcore] Verify Docker Images (<1s)    ← FAILED
[00:06:50] ℹ   Stage: [agent8_sixcore] Setup Handle (<1s)    ← FAILED
[00:06:50] ℹ   Stage: [agent8_sixcore] Integration Tests (<1s)    ← FAILED
[00:06:50] ℹ   Stage: [agent8_sixcore] E2E Tests (<1s)    ← FAILED
[00:06:50] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)


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
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: 096ba529-4afb-4618-bbb1-14f99fc1d938
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint youthful_yalow (79cd757dc5a1409e0621a6281236ba4b4477b89bfa9f6c2163603df7b931d7e8): Bind for 0.0.0.0:9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Finished: FAILURE
[00:06:50] ℹ Duration: 3m 33s

1 2537 0 [02-14 00:06:50] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/phandlemono
$ buildgit --job phandlemono-IT status

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #33
Status:     FAILURE
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     3805e2b - "build now"
            ✓ Your commit (HEAD)
Started:    2026-02-14 00:03:13

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/33/console

[00:07:34] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[00:07:34] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[00:07:34] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[00:07:34] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (3m 26s)
[00:07:34] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[00:07:34] ℹ   Stage:   ║ [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[00:07:34] ℹ   Stage:   ║ [agent8_sixcore] Build Handle (13s)    ← FAILED
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Declarative: Checkout SCM (<1s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Checkout (<1s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Check for Relevant Changes (<1s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Artifactory configuration (<1s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->System Diagnostics (2s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Docker Diagnostics (4s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->main build (1m 1s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Docker Build (20s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Docker Push (8s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Deploy registerdemo (12s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Publish to Artifactory (37s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Archive Artifacts (38s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Publish build info (<1s)
[00:07:34] ℹ   Stage:   ║ [agent7] Build SignalBoot->Declarative: Post Actions (2s)
[00:07:34] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot (3m 25s)
[00:07:34] ℹ   Stage: [agent8_sixcore] Verify Docker Images (<1s)    ← FAILED
[00:07:34] ℹ   Stage: [agent8_sixcore] Setup Handle (<1s)    ← FAILED
[00:07:34] ℹ   Stage: [agent8_sixcore] Integration Tests (<1s)    ← FAILED
[00:07:34] ℹ   Stage: [agent8_sixcore] E2E Tests (<1s)    ← FAILED
[00:07:34] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)

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
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: 096ba529-4afb-4618-bbb1-14f99fc1d938
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint youthful_yalow (79cd757dc5a1409e0621a6281236ba4b4477b89bfa9f6c2163603df7b931d7e8): Bind for 0.0.0.0:9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Finished: FAILURE
[00:07:34] ℹ Duration: 3m 33s
```

Notice also these 2 lines in the output of the 'buidlgit status'

```
[00:07:34] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (3m 26s)
[00:07:34] ℹ   Stage:   ║ [agent8_sixcore] Build SignalBoot (3m 25s)
```

These lines are quite far apart in the output.  The first one prints BEFORE any of the nested stage results are shown.  The second one is printed AFTER.  Is it possible to show a line like 'Trigger Component Builds' AFTER the 'Build SignalBoot' line. notice the 'Trigger Component Builds' stage is a parent stage to 'Build SignalBoot' stage and has not finished until after 'Build SignalBoot' has completed.`