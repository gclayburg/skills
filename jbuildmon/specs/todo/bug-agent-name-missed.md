There is a problem sometimes trying to figure out the name of the agent running the stage.  In this build, the stage 'Build SignalBoot' has an empty agent name.  why ?  can we fix it?

```
[09:05:23] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->System Diagnostics (2s)
[09:05:23] ℹ   Stage:   ║2 [agent7 guthrie] Build SignalBoot->Docker Diagnostics (3s)
  [agent8_sixcore] Build Handle->Build [================>   ] 86% 11s / ~13s
  [agent8_sixcore] Build Handle [=>                  ] 12% 28s / ~3m 54s
  [agent7 guthrie] Build SignalBoot->... [==>                 ] 19% 11s / ~1m 1s
  [              ] Build SignalBoot [=>                  ] 14% 29s / ~3m 26s
IN_PROGRESS Job phandlemono-IT #67 [>                   ] 9% 33s / ~6m 3s
```

Here is the Jenkinsfile used for the build:

```

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
            args '-v /tmp:/tmp --init -v /var/run/docker.sock:/var/run/docker.sock -u 1000:118 --group-add 199 --group-add 1001 --group-add 1000'
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
                    steps {
                        echo "🚀 Triggering phandlemono-handle build..."
                        script {
                            def handleBuild = build job: 'phandlemono-handle', wait: true, propagate: true, parameters: [booleanParam(name: 'FORCE_BUILD', value: true)]
                            echo "✅ phandlemono-handle build #${handleBuild.number} completed successfully"
                        }
                    }
                }
                stage('Build SignalBoot') {
                    steps {
                        echo "🚀 Triggering phandlemono-signalboot build..."
                        script {
                            def signalbootBuild = build job: 'phandlemono-signalboot', wait: true, propagate: true, parameters: [booleanParam(name: 'FORCE_BUILD', value: true)]
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
