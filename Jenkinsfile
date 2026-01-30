pipeline {
    agent {
        docker {
            image 'registry:5000/shell-jenkins-agent:latest'
            alwaysPull true
        }
    }

    stages {
        stage('Initialize Submodules') {
            steps {
                sh 'git submodule update --init --recursive'
            }
        }

        stage('Build') {
            steps {
                echo 'Building...'
                // sh './scripts/build.sh'
            }
        }

        stage('Unit Tests') {
            steps {
                dir('jbuildmon') {
                    sh './test/bats/bin/bats --formatter junit test/*.bats > test-results.xml || true'
                }
            }
            post {
                always {
                    junit skipPublishingChecks: true, testResults: 'jbuildmon/test-results.xml'
                }
            }
        }

        stage('Deploy') {
            steps {
                echo 'Deploying...'
                // sh './scripts/deploy.sh'
            }
        }
    }
}