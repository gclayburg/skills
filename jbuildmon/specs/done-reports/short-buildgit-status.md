We need to modify what `buidlgit status` returns.  Now it returns different results based on if we are running on a tty or not.  Both outputs need to change.

Here is an example of what `buildgit status` returns today.

```
$ buildgit status
[09:46:49] ℹ Prior 3 Jobs
SUCCESS     #249 id=d502ded Tests=666/0/0 Took 2m 28s on 2026-03-02T16:19:32-0700 (17 hours ago)
FAILURE     #250 id=unknown Tests=?/?/? Took 0s on 2026-03-02T16:57:58-0700 (16 hours ago)
SUCCESS     #251 id=9512c5d Tests=666/0/0 Took 2m 19s on 2026-03-02T17:06:42-0700 (16 hours ago)

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #252
Status:     SUCCESS
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     9512c5d - "release buildgit v1.1.0"
            ✓ In your history (reachable from HEAD)
Started:    2026-03-02 17:06:42

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent6
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/252/console

[09:46:50] ℹ   Stage: [agent6        ] Build (4s)
[09:46:50] ℹ   Stage:   ║1 [agent6        ] Unit Tests A (1m 48s)
[09:46:50] ℹ   Stage:   ║2 [agent6        ] Unit Tests B (1m 13s)
[09:46:50] ℹ   Stage:   ║3 [agent6        ] Unit Tests C (1m 41s)
[09:46:50] ℹ   Stage:   ║4 [agent6        ] Unit Tests D (2m 9s)
[09:46:50] ℹ   Stage: [agent6        ] Unit Tests (2m 9s)
[09:46:50] ℹ   Stage: [agent6        ] Deploy (3s)

=== Test Results ===
  Total: 666 | Passed: 666 | Failed: 0 | Skipped: 0
====================

Finished: SUCCESS
[09:46:50] ℹ Duration: 2m 18s

5044 0 [03-03 09:46:50] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ buildgit status --line
[09:46:55] ℹ Prior 3 Jobs
SUCCESS     #249 id=d502ded Tests=666/0/0 Took 2m 28s on 2026-03-02T16:19:32-0700 (17 hours ago)
FAILURE     #250 id=unknown Tests=?/?/? Took 0s on 2026-03-02T16:57:58-0700 (16 hours ago)
SUCCESS     #251 id=9512c5d Tests=666/0/0 Took 2m 19s on 2026-03-02T17:06:42-0700 (16 hours ago)
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on 2026-03-02T17:09:01-0700 (16 hours ago)

5045 0 [03-03 09:46:55] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ buildgit status | cat
[09:47:03] ℹ Prior 3 Jobs
SUCCESS     #249 id=d502ded Tests=666/0/0 Took 2m 28s on 2026-03-02T16:19:32-0700 (17 hours ago)
FAILURE     #250 id=unknown Tests=?/?/? Took 0s on 2026-03-02T16:57:58-0700 (16 hours ago)
SUCCESS     #251 id=9512c5d Tests=666/0/0 Took 2m 19s on 2026-03-02T17:06:42-0700 (16 hours ago)
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on 2026-03-02T17:09:01-0700 (16 hours ago)
```

We need to change this.  We want the output of `buildgit status` to always just show one line, like this:

```
$ buildgit status
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on 2026-03-02T17:09:01-0700 (16 hours ago)
```

Just as before, this represents the results of the last build job.
We want the same output if we are on a tty

```
$ buildgit status | /usr/bin/cat
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on 2026-03-02T17:09:01-0700 (16 hours ago)
```

The only difference is that the non-tty will now show any color output.  this is unchanged behaviour from before.

