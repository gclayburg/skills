# buildgit follow in progress

So I ran buildgit status twice here.  The first time it told me a build was in progress and told me the details that it knew about the build.  It then exited quickly.  so this part worked well.  Now, the next time I ran it, I did it with the -f option.  It found the build, and waited.  It did not tell me anything about the build.  We need this to display information about the build that is known at the time the build starts.  Here is the output of the commands

```bash
$ buildgit status
On branch main
Your branch is up to date with 'origin/main'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	modified:   ../Jenkinsfile


[10:13:20] ℹ Verifying Jenkins connectivity...
[10:13:20] ✓ Connected to Jenkins
[10:13:20] ℹ Verifying job 'ralph1' exists...
[10:13:20] ✓ Job 'ralph1' found

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #53
Status:     BUILDING
Stage:      Unit Tests
Trigger:    Automated (git push)
Commit:     6157e1a - "test build without verbose flag5"
            ✓ Your commit (HEAD)
Started:    2026-02-01 10:11:24
Elapsed:    1m 55s

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/53/console

2 331 0 [02-01 10:13:20] :0.0 ralph@guthrie VMware, Inc. [main] /home/ralph/dev/ralph1/jbuildmon 
$ buildgit status -f
On branch main
Your branch is up to date with 'origin/main'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	modified:   ../Jenkinsfile

[10:13:24] ℹ Verifying Jenkins connectivity...
[10:13:24] ✓ Connected to Jenkins
[10:13:24] ℹ Verifying job 'ralph1' exists...
[10:13:24] ✓ Job 'ralph1' found

```

Here is what I would rather 'buildgit status -f' show when it is executed in the state where a bvuild is currently running on the build server:

```bash
On branch main
Your branch is up to date with 'origin/main'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	modified:   ../Jenkinsfile


[10:13:20] ℹ Verifying Jenkins connectivity...
[10:13:20] ✓ Connected to Jenkins
[10:13:20] ℹ Verifying job 'ralph1' exists...
[10:13:20] ✓ Job 'ralph1' found

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #53
Status:     BUILDING
Stage:      Unit Tests
Trigger:    Automated (git push)
Commit:     6157e1a - "test build without verbose flag5"
            ✓ Your commit (HEAD)
Started:    2026-02-01 10:11:24

```
Note that there is no Elapsed field shown here.  This is because at the time the messages are printed we don't know the elapsed time yet.
The script should begin to show the progress of the build as each stage of the pipeline is completed.  We need one line printed each time a stage is completed successfully.  This should reuse the same functionality that pushmon.sh uses now to follow  a build in progress.  The main intent here is that we want the -f option to buildgit status command to show information about the build so the operator can see the status as we know it at the time.

# buildgit --verbose push errors


I ran 'buildgit push' twice. Once with the --verbose flag and once without.  When using the --verbose flag, I see many errors and the script eventually errors out.  This must be fixed.  If I do NOT use the --verbose flag, the script can see the build and is able to monitor it until completion.

```bash

```bash
$ echo "#" >> nonsensebuildtrigger.md && buildgit add . && buildgit commit -m 'test build without verbose flag5' && ./buildgit --verbose push
[main 8ddc2c6] test build without verbose flag5
 1 file changed, 1 insertion(+)
 create mode 100644 jbuildmon/nonsensebuildtrigger.md
[10:21:33] ℹ Pushing to remote...
To ssh://scranton2:2233/home/git/ralph1.git
   4ade791..8ddc2c6  main -> main
[10:21:34] ℹ Discovering Jenkins job name...
[10:21:34] ✓ Job name: ralph1
[10:21:34] ℹ Verifying Jenkins connectivity...
[10:21:34] ℹ Verifying Jenkins connectivity...
[10:21:34] ✓ Connected to Jenkins
[10:21:34] ℹ Verifying job 'ralph1' exists...
[10:21:34] ✓ Job 'ralph1' found
[10:21:34] ℹ Current build baseline: #54
[10:21:39] ℹ Monitoring build #[10:21:34] ℹ Waiting for Jenkins build to start...
[10:21:34] ℹ Job is queued, waiting for executor...
[10:21:39] ✓ Build #55 started
55...
[10:21:39] ⚠ API request failed, retrying... (1/5)
[10:21:44] ⚠ API request failed, retrying... (2/5)
[10:21:49] ⚠ API request failed, retrying... (3/5)
[10:21:54] ⚠ API request failed, retrying... (4/5)
[10:21:59] ✗ Too many consecutive API failures (5)
[10:21:59] ✗ Build monitoring interrupted or timed out
Suggestion: Check Jenkins console at http://palmer.garyclayburg.com:18080/job/ralph1/[10:21:34] ℹ Waiting for Jenkins build to start...
[10:21:34] ℹ Job is queued, waiting for executor...
[10:21:39] ✓ Build #55 started
55/console

1 493 0 [02-01 10:21:59] :0.0 ralph@guthrie VMware, Inc. [main] /home/ralph/dev/ralph1/jbuildmon 
$ echo "#" >> nonsensebuildtrigger.md && buildgit add . && buildgit commit -m 'test build without verbose flag5' && ./buildgit push
[main 998227d] test build without verbose flag5
 1 file changed, 1 insertion(+)
To ssh://scranton2:2233/home/git/ralph1.git
   8ddc2c6..998227d  main -> main
[10:22:58] ℹ Verifying Jenkins connectivity...
[10:22:58] ✓ Connected to Jenkins
[10:22:58] ℹ Verifying job 'ralph1' exists...
[10:22:58] ✓ Job 'ralph1' found


╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #56
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     998227d - "test build without verbose flag5"
            ✓ Your commit (HEAD)
Duration:   35s
Completed:  2026-02-01 10:23:04

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/56/console

```

# buildgit push seems to stall

I run this command and the script is sort of working but, there is no output shown to the screen as the build is working.  The script just waits until the entire build completes, and then it shows me the output.  We need to see the output as the build is progressing.  pushmon.sh does this now (see specs/buildgit-spec.md).  buildgit shoul dbe using that logic.  This is a related issue to the one above where the buildgit status -f is not able to see the realtime build updates as well.

```bash
$ echo "#" >> nonsensebuildtrigger.md && buildgit add . && buildgit commit -m 'test build without verbose flag5' && ./buildgit push
[main 4e3f9e8] test build without verbose flag5
 1 file changed, 1 insertion(+)
To ssh://scranton2:2233/home/git/ralph1.git
   998227d..4e3f9e8  main -> main
[10:31:26] ℹ Verifying Jenkins connectivity...
[10:31:26] ✓ Connected to Jenkins
[10:31:26] ℹ Verifying job 'ralph1' exists...
[10:31:26] ✓ Job 'ralph1' found
```

After some amount of wating, the build will complete and the display is updated. It just takes too long.

