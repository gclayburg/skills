It should not be possible to specify  both a job number and an argument with -n.  so this should be an error, but it is not now:

```bash
$ ./buildgit status -2 -n 3 --line
SUCCESS     Job ralph1 #198 Tests=604/0/0 Took 4m 54s on 2026-02-21 (1 hour ago)
SUCCESS     Job ralph1 #199 Tests=606/0/0 Took 4m 57s on 2026-02-21 (39 minutes ago)
SUCCESS     Job ralph1 #200 Tests=606/0/0 Took 4m 53s on 2026-02-21 (15 minutes ago)
```

The user can only specify either a specifc job number, -2 in this case, or a -n option with a number, 3 in this case.
Running the command like this should have been an error.

Also, consider these 3 invocations of buildgit:

```bash
$ ./buildgit status 0

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #200
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     f49e307 - "Add DRAFT spec for relative build numbers and -n full mode fix"
            ✓ Your commit (HEAD)
Started:    2026-02-21 14:49:29

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/200/console

[15:13:41] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[15:13:41] ℹ   Stage: [agent8_sixcore] Declarative: Agent Setup (<1s)
[15:13:41] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[15:13:41] ℹ   Stage: [agent8_sixcore] Build (<1s)
[15:13:41] ℹ   Stage: [agent8_sixcore] Unit Tests (4m 38s)
[15:13:41] ℹ   Stage: [agent8_sixcore] Deploy (<1s)

=== Test Results ===
  Total: 606 | Passed: 606 | Failed: 0 | Skipped: 0
====================

Finished: SUCCESS
[15:13:41] ℹ Duration: 4m 53s

3797 0 [02-21 15:13:41] ED25519 :0.0 gclaybur@Garys-Mac-mini (codextrain) ~/dev/ralph1-main-codextrain/jbuildmon
$ ./buildgit status -1

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #200
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     f49e307 - "Add DRAFT spec for relative build numbers and -n full mode fix"
            ✓ Your commit (HEAD)
Started:    2026-02-21 14:49:29

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/200/console

[15:13:47] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[15:13:48] ℹ   Stage: [agent8_sixcore] Declarative: Agent Setup (<1s)
[15:13:48] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[15:13:48] ℹ   Stage: [agent8_sixcore] Build (<1s)
[15:13:48] ℹ   Stage: [agent8_sixcore] Unit Tests (4m 38s)
[15:13:48] ℹ   Stage: [agent8_sixcore] Deploy (<1s)

=== Test Results ===
  Total: 606 | Passed: 606 | Failed: 0 | Skipped: 0
====================

Finished: SUCCESS
[15:13:48] ℹ Duration: 4m 53s

3798 0 [02-21 15:13:48] ED25519 :0.0 gclaybur@Garys-Mac-mini (codextrain) ~/dev/ralph1-main-codextrain/jbuildmon
$ ./buildgit status -2

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #199
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     dc90e92 - "verbose flag alias"
            ✓ In your history (reachable from HEAD)
Started:    2026-02-21 14:25:19

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/199/console

[15:13:52] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[15:13:52] ℹ   Stage: [agent8_sixcore] Declarative: Agent Setup (<1s)
[15:13:52] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[15:13:52] ℹ   Stage: [agent8_sixcore] Build (<1s)
[15:13:52] ℹ   Stage: [agent8_sixcore] Unit Tests (4m 42s)
[15:13:52] ℹ   Stage: [agent8_sixcore] Deploy (<1s)

=== Test Results ===
  Total: 606 | Passed: 606 | Failed: 0 | Skipped: 0
====================

Finished: SUCCESS
[15:13:52] ℹ Duration: 4m 57s


╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #200
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     f49e307 - "Add DRAFT spec for relative build numbers and -n full mode fix"
            ✓ Your commit (HEAD)
Started:    2026-02-21 14:49:29

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/200/console

[15:13:53] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[15:13:53] ℹ   Stage: [agent8_sixcore] Declarative: Agent Setup (<1s)
[15:13:53] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[15:13:53] ℹ   Stage: [agent8_sixcore] Build (<1s)
[15:13:53] ℹ   Stage: [agent8_sixcore] Unit Tests (4m 38s)
[15:13:53] ℹ   Stage: [agent8_sixcore] Deploy (<1s)

=== Test Results ===
  Total: 606 | Passed: 606 | Failed: 0 | Skipped: 0
====================

Finished: SUCCESS
[15:13:53] ℹ Duration: 4m 53s

3799 0 [02-21 15:13:53] ED25519 :0.0 gclaybur@Garys-Mac-mini (codextrain) ~/dev/ralph1-main-codextrain/jbuildmon
$
```

The first requested build 0, so it showed the status of the last build.  Now, when we ran it with 'status -1', it showed us the status of just the last build, #200.  What it should have done was show us the build of #199, and that one only.  Also, when we ran 'status -2', it showed us 2 builds.  This is also not currect.  What it should have done was show us the status of the build from 2 builds ago, which would have been #198.  So we need to update our spec to clarify that anytime we specify 'status X', then we will only show the status of one build.

This is also true for the output of the --line command.  This is what it is doing now:

```
$ ./buildgit status -2 --line
SUCCESS     Job ralph1 #199 Tests=606/0/0 Took 4m 57s on 2026-02-21 (49 minutes ago)
SUCCESS     Job ralph1 #200 Tests=606/0/0 Took 4m 53s on 2026-02-21 (25 minutes ago)
```

This is not correct.  What it must do instead is show the line output for one build that is 2 builds older than the current.  so in this case the last build is #200.  It should have shown one line for build #198.

