
Here is an example of the otuput from `buildgit status -f` today.  We need to change a few cosmetic things

```
[15:04:41] ℹ Waiting for Jenkins build ralph1/2026-03-14_status-follow-probe to start...
[15:04:41] ℹ Prior 3 Jobs
UNSTABLE    #1 id=f09092a Tests=867/1/6 Took 3m 7s on 2026-03-14T14:28:12-0600 (36 minutes ago)
SUCCESS     #2 id=7e1e560 Tests=868/0/6 Took 2m 59s on 2026-03-14T14:32:09-0600 (32 minutes ago)
SUCCESS     #3 id=ec668b6 Tests=873/0/6 Took 3m 0s on 2026-03-14T14:48:55-0600 (15 minutes ago)
[15:04:41] ℹ Estimated build time = 3m 0s
[15:04:41] ℹ Starting

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job ralph1/2026-03-14_status-follow-probe #4 has been running for 1m 50s

Job:        ralph1/2026-03-14_status-follow-probe
Build:      #4
Status:     BUILDING
Trigger:    Unknown
Commit:     d3af04a
            ✓ Your commit (HEAD)
Started:    2026-03-14 15:02:50

=== Build Info ===
  Agent:       agent7 guthrie
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/job/2026-03-14_status-follow-probe/4/console

[15:04:43] ℹ   Stage: [agent7 guthrie] Build (4s)
[15:04:45] ℹ   Stage:   ║1 [agent6 guthrie] Unit Tests A (1m 20s)
[15:04:45] ℹ   Stage:   ║2 [agent7 guthrie] Unit Tests B (1m 34s)
[15:04:45] ℹ   Stage:   ║3 [agent6 guthrie] Unit Tests C (1m 15s)
[15:04:45] ℹ   Stage:   ║5 [agent6 guthrie] Unit Tests E (53s)
[15:04:59] ℹ   Stage:   ║4 [agent8_sixcore] Unit Tests D (1m 51s)
[15:05:40] ℹ   Stage:   ║6 [agent8_sixcore] Integration Tests (2m 33s)
[15:05:40] ℹ   Stage: All Tests (2m 33s)
[15:05:41] ℹ   Stage: [agent8_sixcore] Deploy (4s)

=== Test Results ===
  Total: 885 | Passed: 879 | Failed: 0 | Skipped: 6
====================

Finished: SUCCESS
[15:05:51] ℹ Duration: 2m 45s
```

First I don't see 'Started by' line for this build.  sometimes I do.

One build is able to show 'started by'.  the other one cannot.  is this a parsing error?  we need to show who started the build.

```
$ ./buildgit --job ralph1/2026-03-14_status-follow-probe status 4 --all

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1/2026-03-14_status-follow-probe
Build:      #4
Status:     SUCCESS
Trigger:    Unknown
Commit:     d3af04a
            ✗ Not in your history
Started:    2026-03-14 15:02:50

=== Build Info ===
  Agent:       agent7 guthrie
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/job/2026-03-14_status-follow-probe/4/console

[15:22:27] ℹ   Stage: [agent7 guthrie] Build (4s)
[15:22:28] ℹ   Stage:   ║1 [agent6 guthrie] Unit Tests A (1m 20s)
[15:22:28] ℹ   Stage:   ║2 [agent7 guthrie] Unit Tests B (1m 34s)
[15:22:28] ℹ   Stage:   ║3 [agent6 guthrie] Unit Tests C (1m 15s)
[15:22:28] ℹ   Stage:   ║4 [agent8_sixcore] Unit Tests D (1m 51s)
[15:22:28] ℹ   Stage:   ║5 [agent6 guthrie] Unit Tests E (53s)
[15:22:28] ℹ   Stage:   ║6 [agent8_sixcore] Integration Tests (2m 33s)
[15:22:28] ℹ   Stage: All Tests (2m 33s)
[15:22:28] ℹ   Stage: [agent8_sixcore] Deploy (4s)

=== Test Results ===
  Total: 885 | Passed: 879 | Failed: 0 | Skipped: 6
====================

Finished: SUCCESS
[15:22:28] ℹ Duration: 2m 45s

7859 0 [03-14 15:22:28] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ ./buildgit status 83 --all

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1/main
Build:      #83
Status:     SUCCESS
Trigger:    Manual (started by )
Commit:     2ecd125
            ✓ In your history (reachable from HEAD)
Started:    2026-03-14 15:18:35

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent6 guthrie
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/job/main/83/console

[15:23:12] ℹ   Stage: [agent6 guthrie] Build (4s)
[15:23:12] ℹ   Stage:   ║1 [agent8_sixcore] Unit Tests A (1m 33s)
[15:23:12] ℹ   Stage:   ║2 [agent6 guthrie] Unit Tests B (1m 19s)
[15:23:12] ℹ   Stage:   ║3 [agent8_sixcore] Unit Tests C (1m 22s)
[15:23:12] ℹ   Stage:   ║4 [agent6 guthrie] Unit Tests D (1m 35s)
[15:23:12] ℹ   Stage:   ║5 [agent7 guthrie] Unit Tests E (45s)
[15:23:12] ℹ   Stage:   ║6 [agent8_sixcore] Integration Tests (2m 32s)
[15:23:12] ℹ   Stage: All Tests (2m 32s)
[15:23:12] ℹ   Stage: [agent7 guthrie] Deploy (4s)

=== Test Results ===
  Total: 868 | Passed: 862 | Failed: 0 | Skipped: 6
====================

Finished: SUCCESS
[15:23:12] ℹ Duration: 2m 44s
```

The other thing I want to fix is the layout of the header section.  Lets condense the output of the header: section so there are no blank lines and we show the first line of the commit message, if it is available

```
Job:        ralph1/main
Build:      #83
Status:     SUCCESS
Trigger:    Manual (started by )
Commit:     2ecd125  implement: Standardize stdout/stderr output streams for buildgit (squashed 3 commits)
            ✓ In your history (reachable from HEAD)
Started:    2026-03-14 15:18:35
Started by: Ralph AI Read Only
Agent:      agent6 guthrie
Console:    http://palmer.garyclayburg.com:18080/job/ralph1/job/main/83/console
```

We also need to fix the Trigger: line.  Why does it say (started by )  
Maybe there is a parsing error to find the name?  

Also, if 'Trigger:' and 'Started by:' is essentially the same thing, how about we condense this in to one line.  What do you suggest here?

