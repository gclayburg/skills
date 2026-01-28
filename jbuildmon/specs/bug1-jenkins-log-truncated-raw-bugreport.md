We get this build failure when we try to use pushmon.sh.  The problem is that we see part of the log but not enough of it to determine the failure.  Here is the output in the terminal:

$ pushmon.sh ralph1 'install-bats-core-plan chunk 4'

Jenkins Build Monitor
─────────────────────────────────────────
  Jenkins:    http://palmer.garyclayburg.com:18080
  Job:        ralph1
  Branch:     main
  Repository: ssh://git@scranton2:2233/home/git/ralph1.git
─────────────────────────────────────────

[22:44:54] ℹ Verifying Jenkins connectivity...
[22:44:54] ✓ Connected to Jenkins
[22:44:54] ℹ Verifying job 'ralph1' exists...
[22:44:54] ✓ Job 'ralph1' found
[22:44:54] ℹ Found staged changes to commit
[22:44:54] ℹ Creating commit...
[main b998a3d] install-bats-core-plan chunk 4
 2 files changed, 264 insertions(+), 3 deletions(-)
 create mode 100644 jbuildmon/specs/install-bats-core-plan.md
[22:44:54] ✓ Created commit: b998a3d
[22:44:54] ℹ Fetching from origin/main...
[22:44:54] ℹ Pushing to origin/main...
Enumerating objects: 10, done.
Counting objects: 100% (10/10), done.
Delta compression using up to 10 threads
Compressing objects: 100% (6/6), done.
Writing objects: 100% (6/6), 3.32 KiB | 3.32 MiB/s, done.
Total 6 (delta 4), reused 0 (delta 0), pack-reused 0 (from 0)
To ssh://scranton2:2233/home/git/ralph1.git
   061cfe3..b998a3d  main -> main
[22:44:55] ✓ Pushed to origin/main
[22:44:55] ℹ Current build baseline: #18
[22:44:55] ℹ Waiting for Jenkins build to start...
[22:44:55] ℹ Job is queued, waiting for executor...
[22:45:05] ✓ Build #19 started
[22:45:05] ℹ Monitoring build #19...
[22:45:05] ℹ Stage: Unit Tests

╔════════════════════════════════════════╗
║             BUILD FAILED               ║
╚════════════════════════════════════════╝

[22:45:15] ✗ Build #19 result: UNSTABLE
[22:45:15] ℹ Analyzing failure...

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent2paton
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================
[22:45:15] ℹ Failed stage: Unit Tests

=== Stage 'Unit Tests' Logs ===
[Pipeline] dir
Running in /home/jenkins/workspace/ralph1/jbuildmon
[Pipeline] {
[Pipeline] sh
+ ./test/bats/bin/bats --formatter junit test/smoke.bats test/test_helper.bats
+ true
=================================

[22:45:15] ℹ Full console output: http://palmer.garyclayburg.com:18080/job/ralph1/19/console

---
Meanwhile, the output of the jenkins-cli shows the complete log with the failure reason.  we need a strategy to show more of the console log when a build failure like this happens.  It seems like our log pruning technique is too aggressive.  can you suggest a fix for this?  Here is the complete log as seen in the Jenkins UI:



Started by user buildtriggerdude
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
[Pipeline] Start of Pipeline
[Pipeline] node
Running on agent2paton in /home/jenkins/workspace/ralph1
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Declarative: Checkout SCM)
[Pipeline] checkout
Selected Git installation does not exist. Using Default
The recommended git tool is: NONE
using credential 67c03aed-4b95-4cd0-91d4-02e9976c9da5
Fetching changes from the remote Git repository
Checking out Revision b998a3def72cbae143f3dd67a3cc8121f7bd0f67 (refs/remotes/origin/main)
Commit message: "install-bats-core-plan chunk 4"
 > git rev-parse --resolve-git-dir /home/jenkins/workspace/ralph1/.git # timeout=10
 > git config remote.origin.url ssh://git@scranton2:2233/home/git/ralph1.git # timeout=10
Fetching upstream changes from ssh://git@scranton2:2233/home/git/ralph1.git
 > git --version # timeout=10
 > git --version # 'git version 2.20.1'
using GIT_SSH to set credentials use this to pull from scranton2 ssh repos
Verifying host key using known hosts file, will automatically accept unseen keys
 > git fetch --tags --force --progress -- ssh://git@scranton2:2233/home/git/ralph1.git +refs/heads/*:refs/remotes/origin/* # timeout=10
 > git rev-parse refs/remotes/origin/main^{commit} # timeout=10
 > git config core.sparsecheckout # timeout=10
 > git checkout -f b998a3def72cbae143f3dd67a3cc8121f7bd0f67 # timeout=10
 > git rev-list --no-walk 061cfe395e6535051e8a1023f02467b1f0719b19 # timeout=10
[Checks API] No suitable checks publisher found.
[Pipeline] }
[Pipeline] // stage
[Pipeline] withEnv
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Initialize Submodules)
[Pipeline] sh
+ git submodule update --init --recursive
Submodule 'jbuildmon/test/bats' (https://github.com/bats-core/bats-core.git) registered for path 'jbuildmon/test/bats'
Submodule 'jbuildmon/test/test_helper/bats-assert' (https://github.com/bats-core/bats-assert.git) registered for path 'jbuildmon/test/test_helper/bats-assert'
Submodule 'jbuildmon/test/test_helper/bats-file' (https://github.com/bats-core/bats-file.git) registered for path 'jbuildmon/test/test_helper/bats-file'
Submodule 'jbuildmon/test/test_helper/bats-support' (https://github.com/bats-core/bats-support.git) registered for path 'jbuildmon/test/test_helper/bats-support'
Cloning into '/home/jenkins/workspace/ralph1/jbuildmon/test/bats'...
Cloning into '/home/jenkins/workspace/ralph1/jbuildmon/test/test_helper/bats-support'...
Cloning into '/home/jenkins/workspace/ralph1/jbuildmon/test/test_helper/bats-file'...
Cloning into '/home/jenkins/workspace/ralph1/jbuildmon/test/test_helper/bats-assert'...
Submodule path 'jbuildmon/test/bats': checked out '5f12b3172105a0f26bce629ff8ae0ac76c4bd61e'
Submodule path 'jbuildmon/test/test_helper/bats-assert': checked out '697471b7a89d3ab38571f38c6c7c4b460d1f5e35'
Submodule path 'jbuildmon/test/test_helper/bats-file': checked out '6bee58bec7c2f4aed1a7425ccd4bdc42b4a84599'
Submodule path 'jbuildmon/test/test_helper/bats-support': checked out '0954abb9925cad550424cebca2b99255d4eabe96'
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Build)
[Pipeline] echo
Building...
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Unit Tests)
[Pipeline] dir
Running in /home/jenkins/workspace/ralph1/jbuildmon
[Pipeline] {
[Pipeline] sh
+ ./test/bats/bin/bats --formatter junit test/smoke.bats test/test_helper.bats
+ true
[Pipeline] }
[Pipeline] // dir
Post stage
[Pipeline] junit
Recording test results
[Checks API] No suitable checks publisher found.
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Deploy)
[Pipeline] echo
Deploying...
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
[Checks API] No suitable checks publisher found.
Finished: UNSTABLE