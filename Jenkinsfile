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
                sh 'sleep 10 ; git submodule update --init --recursive'
            }
        }

        stage('Build') {
            steps {
                echo 'Building...'
                //sh 'sleep 15'
                //echo 'done building'
                //sh './scripts/build.sh'
            }
        }

        stage('Unit Tests') {
            steps {
                dir('jbuildmon') {
                    sh 'sleep 2'
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
