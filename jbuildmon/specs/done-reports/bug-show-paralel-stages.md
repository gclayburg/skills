It appears that not all stages are printed correctly for either the monitored status or snapshot status.  I see this:

```bash
$ buildgit build
[15:34:12] ℹ Waiting for Jenkins build phandlemono-IT to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #29
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Started:    2026-02-13 15:34:21

=== Build Info ===
  Started by:  Ralph AI Read Only
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/29/console

Commit:     3805e2b - "build now"
            ✓ Your commit (HEAD)
[15:34:27] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[15:34:27] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[15:34:28] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[15:34:28] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (<1s)
[15:34:28] ℹ   Stage: [agent8_sixcore] Build SignalBoot (unknown)
[15:34:33] ℹ   Stage:   [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[15:34:38] ℹ   Stage:   [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[15:34:38] ℹ   Stage: [agent8_sixcore] Build Handle (9s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Verify Docker Images (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Setup Handle (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Integration Tests (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] E2E Tests (<1s)    ← FAILED
[15:37:53] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)


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
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: 3b741f39-2681-488c-a38b-3de20dd4a3ca
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint affectionate_kowalevski (019f8aecc82b99e39f14c697c417609e7be3ace265503acdc3fbcfa55985ffba): Bind for :::9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Finished: FAILURE
[15:37:53] ℹ Duration: 3m 30s

1 2512 0 [02-13 15:37:53] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/phandlemono
$ buildgit status

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #29
Status:     FAILURE
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     3805e2b - "build now"
            ✓ Your commit (HEAD)
Started:    2026-02-13 15:34:21

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/29/console

[15:47:23] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[15:47:23] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[15:47:23] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[15:47:23] ℹ   Stage:   [agent8_sixcore] Trigger Component Builds->Declarative: Checkout SCM (<1s)
[15:47:23] ℹ   Stage:   [agent8_sixcore] Trigger Component Builds->Declarative: Post Actions (<1s)
[15:47:23] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (<1s)
[15:47:23] ℹ   Stage:   [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[15:47:23] ℹ   Stage:   [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[15:47:23] ℹ   Stage: [agent8_sixcore] Build Handle (9s)    ← FAILED
[15:47:23] ℹ   Stage:   [agent8_sixcore] Build SignalBoot->Declarative: Checkout SCM (<1s)
[15:47:23] ℹ   Stage:   [agent8_sixcore] Build SignalBoot->Declarative: Post Actions (<1s)
[15:47:23] ℹ   Stage: [agent8_sixcore] Build SignalBoot (3m 24s)
[15:47:23] ℹ   Stage: [agent8_sixcore] Verify Docker Images (<1s)    ← FAILED
[15:47:23] ℹ   Stage: [agent8_sixcore] Setup Handle (<1s)    ← FAILED
[15:47:23] ℹ   Stage: [agent8_sixcore] Integration Tests (<1s)    ← FAILED
[15:47:23] ℹ   Stage: [agent8_sixcore] E2E Tests (<1s)    ← FAILED
[15:47:23] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)

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
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: 3b741f39-2681-488c-a38b-3de20dd4a3ca
java.io.IOException: Failed to run image 'registry:5000/handle-electron-builder:latest'. Error: docker: Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint affectionate_kowalevski (019f8aecc82b99e39f14c697c417609e7be3ace265503acdc3fbcfa55985ffba): Bind for :::9222 failed: port is already allocated
        at jenkins.util.ErrorLoggingExecutorService.lambda$wrap$0(ErrorLoggingExecutorService.java:51)
Finished: FAILURE
==================

Finished: FAILURE
[15:47:23] ℹ Duration: 3m 30s
```

The top level Jenkinsfile associated with the build is this:

```groovy
/*
AGENTS:
- Jenkins job name: phandlemono-IT
- This is the orchestrator pipeline for phandlemono monorepo
- Triggered by git post-receive hook when commits are pushed
- Orchestration flow:
  1. Analyzes changed files to determine which component builds to trigger
  2. Triggers phandlemono-handle and/or phandlemono-signalboot builds in parallel (based on changes)
  3. Waits for component builds to complete successfully
  4. Runs E2E integration tests that verify frontend and backend work together
*/
pipeline {
    agent {
        docker {
            image 'registry:5000/handle-electron-builder:latest'
            label 'sixcore'
            args '-v /tmp:/tmp -p 9222:9222 --init -v /var/run/docker.sock:/var/run/docker.sock -u 1000:118 --group-add 199 --group-add 1001 --group-add 1000'
        }
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        ansiColor('xterm')
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        TZ = 'America/Denver'
        DOCKER_REGISTRY = 'registry:5000'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "=== phandlemono Orchestrator Pipeline ==="
            }
        }

        stage('Analyze Component Changes') {
            steps {
                script {
                    // Get list of changed files in this build
                    def changed_files = []
                    def has_handle_changes = false
                    def has_signalboot_changes = false
                    
                    // Check if this is the first build (no previous build to compare)
                    if (currentBuild.changeSets.size() == 0) {
                        echo "ℹ️ No changeset detected (first build or manual trigger) - will build both components"
                        env.SHOULD_BUILD_HANDLE = 'true'
                        env.SHOULD_BUILD_SIGNALBOOT = 'true'
                        return
                    }
                    
                    // Collect all changed files and detect component changes
                    for (changeSet in currentBuild.changeSets) {
                        for (entry in changeSet.items) {
                            for (file in entry.affectedFiles) {
                                changed_files.add(file.path)
                                if (file.path.startsWith('modules/handle/')) {
                                    has_handle_changes = true
                                }
                                if (file.path.startsWith('modules/signalboot/')) {
                                    has_signalboot_changes = true
                                }
                            }
                        }
                    }
                    
                    echo "📁 Changed files in this commit:"
                    changed_files.each { echo "  - ${it}" }
                    
                    // env.SHOULD_BUILD_HANDLE = has_handle_changes ? 'true' : 'false'
                    // env.SHOULD_BUILD_SIGNALBOOT = has_signalboot_changes ? 'true' : 'false'
                    
                    env.SHOULD_BUILD_SIGNALBOOT = 'true'
                    env.SHOULD_BUILD_HANDLE = 'true'

                    echo "=== Component Build Decision ==="
                    echo "Build Handle: ${env.SHOULD_BUILD_HANDLE}"
                    echo "Build SignalBoot: ${env.SHOULD_BUILD_SIGNALBOOT}"
                }
            }
        }

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

        stage('Verify Docker Images') {
            steps {
                echo "=== Verifying SignalBoot Docker Images ==="
                
                // Pull latest images from registry
                sh "docker pull registry:5000/signalboot-server:latest"
                
                // Verify images are available
                sh "docker images | grep -E 'signalboot-server'"
                
                echo "=== Docker Image Verification Complete ==="
            }
        }

        stage('Setup Handle') {
            steps {
                dir('modules/handle') {
                    sh 'npm install'
                    sh 'npm run build'
                }
            }
        }

        stage('Integration Tests') {
            steps {
                dir('modules/handle') {
                    sh '''
                    echo "=== Starting E2E Integration Tests ==="
                    echo "These tests verify handle client works with signalboot server"
                    
                    # Run integration tests with TestContainers (spins up signalboot)
                    npm run test:integration
                    '''
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'modules/handle/test-results/jest-junit-integration.xml'
                }
            }
        }

        stage('E2E Tests') {
            steps {
                dir('modules/handle') {
                    sh '''
                    echo "=== Starting Playwright E2E Tests ==="
                    
                    # Run Playwright tests with Xvfb for headless display
                    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 xvfb-run -a -e /dev/stderr npm run test:e2e
                    '''
                }
            }
            post {
                always {
                    publishHTML target: [
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'modules/handle/playwright-report',
                        reportFiles: 'index.html',
                        reportName: 'Playwright E2E Report'
                    ]
                    junit allowEmptyResults: true, testResults: 'modules/handle/test-results/playwright-junit.xml'
                }
            }
        }
    }

    post {
        success {
            echo '🎉 phandlemono Integration Tests PASSED!'
            echo '✅ Handle client successfully communicates with SignalBoot server'
            echo '✅ E2E tests verified end-to-end encryption flow'
        }
        failure {
            echo '❌ phandlemono Integration Tests FAILED!'
            echo '💡 Check if:'
            echo '  - SignalBoot Docker images are available in registry'
            echo '  - Handle client builds successfully'
            echo '  - WebSocket/STOMP connection works'
            echo '  - Signal Protocol handshake succeeds'
        }
    }
}
```

Now there was some failures with this build, but I am more interested in the display of the stage lines.  There are 2 stages that run in parallel: Build Handle and Build SignalBoot.  I can see in the Jenkins UI console, that the 'Build SignalBoot' stage did complete after some time. It also had several stages of its own that ran. But we cannot see any of that output in this display.  why is that?  is this something related to having 2 stages that run in parallel? 