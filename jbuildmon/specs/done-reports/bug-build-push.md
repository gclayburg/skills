check out the results of these commands:

```bash
$ buildgit push
To ssh://scranton2:2233/home/git/ralph1.git
   732740a..552b265  main -> main
[09:04:29] ℹ Waiting for Jenkins build ralph1 to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #157
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     552b265 - "nested job support, status for build by job jumber, better failure detection"
            ✓ Your commit (HEAD)
Started:    2026-02-13 09:04:35
Elapsed:    3s

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/157/console

[09:04:39] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[09:04:39] ℹ   Stage: [agent8_sixcore] Declarative: Agent Setup (<1s)
[09:04:55] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[09:04:55] ℹ   Stage: [agent8_sixcore] Build (<1s)
[09:07:52] ℹ   Stage: [agent8_sixcore] Unit Tests (2m 57s)
[09:07:52] ℹ   Stage: [agent8_sixcore] Deploy (<1s)


Finished: SUCCESS

2223 0 [02-13 09:07:52] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ buildgit build
[09:11:17] ℹ Waiting for Jenkins build ralph1 to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #158
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     unknown
            ✗ Unknown commit
Started:    2026-02-13 09:11:25
Elapsed:    unknown

=== Build Info ===
  Started by:  Ralph AI Read Only
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/158/console

[09:11:31] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[09:11:31] ℹ   Stage: [agent8_sixcore] Declarative: Agent Setup (<1s)
[09:11:41] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[09:11:41] ℹ   Stage: [agent8_sixcore] Build (<1s)
[09:14:39] ℹ   Stage: [agent8_sixcore] Unit Tests (2m 58s)
[09:14:39] ℹ   Stage: [agent8_sixcore] Deploy (<1s)


Finished: SUCCESS
```

These are both monitoring style status reports.  They were run consecutively, but they report different infomration.  It is not clear why.
- build info section is different.  why not display the agent and pipleine data in both cases?
- The commit says 'unknown' for 'buildgit build'  why?  We did not push a new change, but the build itself knows what the last commit was.  It also would match our local commit.
- The Elapsed line doesn't make much sense in this context.  The build was obviously just started by us.  The only time this Elapsed line makes sense is if we ran 'buildgit status -f' variant.  It could be the case that we ran buildgit status -f for a build that was started some time ago.  In that case, we should show the Elapsed line at the beginning.  something like 'Job ralph1 #160 has been unning for 14s (so far)'.  This should be displayed just under the build in progress banner shown today.  The Elapsed line should be removed.
- When a monitoring style build is finished, there is no display about how long the build actually took.  We need to add a final log line after the 'Finished' line that says 'Duration: 3m 14s', for example.  This should be printed using the log system that shows the date stamp at the beginning
- of course, all of this applies to 'build status -f' as well since it is also a monitoring style.

