pipeline {
    agent any

    stages {
        stage('Build') {
            steps {
                echo 'Building...'
                // sh './scripts/build.sh'
            }
        }

        stage('Test') {
            steps {
                echo 'Testing...'
                // sh './scripts/test.sh'
            }
        }

        stage('Deploy') {
            steps {
                echo 'Deploying...'
                sh './scripts/deploy.sh'
            }
        }
    }
}