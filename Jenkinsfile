pipeline {
    agent none
    options {
        timeout(time: 15, unit: 'MINUTES')
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
                echo 'Building...'
            }
        }

        stage('Unit Tests') {
            parallel {
                stage('Unit Tests A') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'fastnode'
                        }
                    }
                    steps {
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                PARALLEL_OPTS="--jobs 2"
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . $PARALLEL_OPTS \
                                    test/buildgit_status.bats \
                                    test/buildgit_build.bats \
                                    test/smoke.bats || true
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
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                PARALLEL_OPTS="--jobs 6"
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . $PARALLEL_OPTS \
                                    test/nested_stages.bats \
                                    test/parallel_stages.bats \
                                    test/console_option.bats \
                                    test/unified_header.bats \
                                    test/stage_duration.bats \
                                    test/stage_print.bats \
                                    test/extract_stage_logs.bats \
                                    test/buildgit_errors.bats \
                                    test/jenkins_common.bats \
                                    test/build_info.bats || true
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
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                PARALLEL_OPTS="--jobs 6"
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . $PARALLEL_OPTS \
                                    test/display_stages.bats \
                                    test/buildgit_routing.bats \
                                    test/buildgit_realtime_progress.bats \
                                    test/bug_show_all_stages.bats \
                                    test/stage_tracking.bats \
                                    test/buildgit_verbosity.bats \
                                    test/build_completion.bats \
                                    test/job_discovery.bats \
                                    test/monitor_consolidation.bats \
                                    test/shared_failure_diagnostics.bats \
                                    test/monitoring_stages.bats \
                                    test/finished_line.bats \
                                    test/early_build_failure.bats \
                                    test/bug_status_json.bats \
                                    test/stage_retrieval.bats \
                                    test/buildgit_follow_banner.bats \
                                    test/bug_not_built.bats \
                                    test/header_integration.bats \
                                    test/correlate_commit.bats \
                                    test/trigger_detection.bats \
                                    test/buildgit_verbose_stderr.bats \
                                    test/buildgit_version.bats || true
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
                        sh 'git submodule update --init --recursive --depth 1'
                        dir('jbuildmon') {
                            sh '''
                                PARALLEL_OPTS="--jobs 6"

                                # Files explicitly assigned to Groups A, B, C
                                ASSIGNED_FILES="
                                    buildgit_status.bats
                                    buildgit_build.bats
                                    smoke.bats
                                    nested_stages.bats
                                    parallel_stages.bats
                                    console_option.bats
                                    unified_header.bats
                                    stage_duration.bats
                                    stage_print.bats
                                    extract_stage_logs.bats
                                    buildgit_errors.bats
                                    jenkins_common.bats
                                    build_info.bats
                                    display_stages.bats
                                    buildgit_routing.bats
                                    buildgit_realtime_progress.bats
                                    bug_show_all_stages.bats
                                    stage_tracking.bats
                                    buildgit_verbosity.bats
                                    build_completion.bats
                                    job_discovery.bats
                                    monitor_consolidation.bats
                                    shared_failure_diagnostics.bats
                                    monitoring_stages.bats
                                    finished_line.bats
                                    early_build_failure.bats
                                    bug_status_json.bats
                                    stage_retrieval.bats
                                    buildgit_follow_banner.bats
                                    bug_not_built.bats
                                    header_integration.bats
                                    correlate_commit.bats
                                    trigger_detection.bats
                                    buildgit_verbose_stderr.bats
                                    buildgit_version.bats
                                "

                                # Find all .bats files not assigned to other groups
                                REMAINING=""
                                for f in test/*.bats; do
                                    if ! echo "$ASSIGNED_FILES" | grep -qw "$(basename "$f")"; then
                                        REMAINING="$REMAINING $f"
                                    fi
                                done

                                if [ -n "$REMAINING" ]; then
                                    echo "Catch-all group running: $REMAINING"
                                    ./test/bats/bin/bats --formatter tap --report-formatter junit --output . $PARALLEL_OPTS $REMAINING || true
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
                                test/integration/integration_tests.bats \
                                test/integration/threads_integration_tests.bats
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

        stage('Deploy') {
            agent {
                docker {
                    image 'registry:5000/shell-jenkins-agent:latest'
                    alwaysPull true
                    label 'fastnode'
                }
            }
            steps {
                echo 'Deploying...'
            }
        }
    }
}
