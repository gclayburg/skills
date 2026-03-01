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
                        sh 'git submodule update --init --recursive'
                        dir('jbuildmon') {
                            sh '''
                                PARALLEL_OPTS=""
                                command -v parallel >/dev/null 2>&1 && PARALLEL_OPTS="--jobs 2"
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . $PARALLEL_OPTS \
                                    test/buildgit_status.bats \
                                    test/test_results_display.bats \
                                    test/buildgit_status_follow.bats \
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
                        sh 'git submodule update --init --recursive'
                        dir('jbuildmon') {
                            sh '''
                                PARALLEL_OPTS=""
                                command -v parallel >/dev/null 2>&1 && PARALLEL_OPTS="--jobs 2"
                                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . $PARALLEL_OPTS \
                                    test/nested_stages.bats \
                                    test/parallel_stages.bats \
                                    test/console_option.bats \
                                    test/unified_header.bats \
                                    test/buildgit_push.bats \
                                    test/stage_duration.bats \
                                    test/stage_print.bats \
                                    test/buildgit_args.bats \
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
                        sh 'git submodule update --init --recursive'
                        dir('jbuildmon') {
                            sh '''
                                PARALLEL_OPTS=""
                                command -v parallel >/dev/null 2>&1 && PARALLEL_OPTS="--jobs 2"
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
