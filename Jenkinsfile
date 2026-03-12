pipeline {
    agent none
    options {
        timeout(time: 15, unit: 'MINUTES')
        skipDefaultCheckout true
    }

    stages {
        stage('Build') {
            agent {
                docker {
                    image 'registry:5000/shell-jenkins-agent:latest'
                    alwaysPull true
                    label 'fastnode'
                }
            }
            steps {
                sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                checkout scm
                echo 'Building...'
            }
        }

        stage('All Tests') {
            parallel {
                stage('Unit Tests A') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'sixcore'
                        }
                    }
                    steps {
                        sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                        checkout scm
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . --jobs 8 \
                                    test/buildgit_status_follow.bats \
                                    test/buildgit_push.bats \
                                    test/buildgit_args.bats \
                                    test/console_option.bats \
                                    test/buildgit_queue.bats \
                                    test/buildgit_pipeline.bats \
                                    test/test_helper.bats || true
                            '''
                        }
                    }
                    post {
                        always {
                            junit skipPublishingChecks: true, testResults: 'jbuildmon/report.xml'
                        }
                    }
                }

                stage('Unit Tests B') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'fastnode'
                        }
                    }
                    steps {
                        sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                        checkout scm
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . --jobs 6 \
                                    test/nested_stages.bats \
                                    test/parallel_stages.bats \
                                    test/unified_header.bats \
                                    test/stage_duration.bats \
                                    test/stage_print.bats \
                                    test/extract_stage_logs.bats || true
                            '''
                        }
                    }
                    post {
                        always {
                            junit skipPublishingChecks: true, testResults: 'jbuildmon/report.xml'
                        }
                    }
                }

                stage('Unit Tests C') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'fastnode'
                        }
                    }
                    steps {
                        sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                        checkout scm
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . --jobs 6 \
                                    test/buildgit_build.bats \
                                    test/buildgit_status.bats \
                                    test/test_results_display.bats \
                                    test/build_info.bats \
                                    test/build_completion.bats \
                                    test/buildgit_errors.bats \
                                    test/jenkins_common.bats \
                                    test/early_build_failure.bats \
                                    test/finished_line.bats \
                                    test/stage_retrieval.bats || true
                            '''
                        }
                    }
                    post {
                        always {
                            junit skipPublishingChecks: true, testResults: 'jbuildmon/report.xml'
                        }
                    }
                }

                stage('Unit Tests D') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'fastnode'
                        }
                    }
                    steps {
                        sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                        checkout scm
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . --jobs 6 \
                                    test/monitor_consolidation.bats \
                                    test/bug_show_all_stages.bats \
                                    test/monitoring_stages.bats \
                                    test/display_stages.bats \
                                    test/buildgit_routing.bats \
                                    test/buildgit_realtime_progress.bats \
                                    test/stage_tracking.bats \
                                    test/buildgit_verbosity.bats \
                                    test/job_discovery.bats \
                                    test/shared_failure_diagnostics.bats \
                                    test/buildgit_follow_banner.bats \
                                    test/bug_not_built.bats \
                                    test/header_integration.bats \
                                    test/correlate_commit.bats \
                                    test/bug_status_json.bats || true
                            '''
                        }
                    }
                    post {
                        always {
                            junit skipPublishingChecks: true, testResults: 'jbuildmon/report.xml'
                        }
                    }
                }

                stage('Unit Tests E') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'slownode'
                        }
                    }
                    steps {
                        sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                        checkout scm
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                # Catch-all: files not assigned to Groups A-D
                                ASSIGNED_FILES="
                                    buildgit_status_follow.bats
                                    buildgit_push.bats
                                    buildgit_args.bats
                                    console_option.bats
                                    buildgit_queue.bats
                                    buildgit_pipeline.bats
                                    test_helper.bats
                                    nested_stages.bats
                                    parallel_stages.bats
                                    unified_header.bats
                                    stage_duration.bats
                                    stage_print.bats
                                    extract_stage_logs.bats
                                    buildgit_build.bats
                                    buildgit_status.bats
                                    test_results_display.bats
                                    build_info.bats
                                    build_completion.bats
                                    buildgit_errors.bats
                                    jenkins_common.bats
                                    early_build_failure.bats
                                    finished_line.bats
                                    stage_retrieval.bats
                                    monitor_consolidation.bats
                                    bug_show_all_stages.bats
                                    monitoring_stages.bats
                                    display_stages.bats
                                    buildgit_routing.bats
                                    buildgit_realtime_progress.bats
                                    stage_tracking.bats
                                    buildgit_verbosity.bats
                                    job_discovery.bats
                                    shared_failure_diagnostics.bats
                                    buildgit_follow_banner.bats
                                    bug_not_built.bats
                                    header_integration.bats
                                    correlate_commit.bats
                                    bug_status_json.bats
                                "

                                REMAINING=""
                                for f in test/*.bats; do
                                    if ! echo "$ASSIGNED_FILES" | grep -qw "$(basename "$f")"; then
                                        REMAINING="$REMAINING $f"
                                    fi
                                done

                                if [ -n "$REMAINING" ]; then
                                    echo "Catch-all group running: $REMAINING"
                                    ./test/bats/bin/bats --formatter tap --report-formatter junit --output . --jobs 4 $REMAINING || true
                                else
                                    echo "No additional test files found"
                                fi
                            '''
                        }
                    }
                    post {
                        always {
                            junit skipPublishingChecks: true, testResults: 'jbuildmon/report.xml'
                        }
                    }
                }

                stage('Integration Tests') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'fastnode'
                        }
                    }
                    steps {
                        sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                        checkout scm
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            withCredentials([usernamePassword(
                                credentialsId: 'jenkins-buildgit-readonly',
                                usernameVariable: 'JENKINS_USER_ID',
                                passwordVariable: 'JENKINS_API_TOKEN'
                            )]) {
                                sh '''
                                    : "${JENKINS_URL:?JENKINS_URL is not set}"
                                    : "${JENKINS_USER_ID:?JENKINS_USER_ID is not set}"
                                    : "${JENKINS_API_TOKEN:?JENKINS_API_TOKEN is not set}"
                                    export JENKINS_URL JENKINS_USER_ID JENKINS_API_TOKEN
                                    ./test/bats/bin/bats --formatter tap --report-formatter junit --output . \
                                        test/integration/integration_tests.bats
                                '''
                            }
                        }
                    }
                    post {
                        always {
                            junit skipPublishingChecks: true, testResults: 'jbuildmon/report.xml'
                        }
                    }
                }
            }
        }

        stage('Deploy') {
            agent {
                docker {
                    image 'registry:5000/shell-jenkins-agent:latest'
                    alwaysPull true
                    label 'fastnode'
                }
            }
            steps {
                sh 'mkdir -p /home/jenkins/.ssh && ssh-keyscan -p 2233 scranton2 > /home/jenkins/.ssh/known_hosts 2>/dev/null || true'
                checkout scm
                echo 'Deploying...'
            }
        }
    }
}
