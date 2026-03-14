We need to analyze the entire codebase and fix how we deal with stdout and stderr for the buildgit tool.  We want normal output to go to stdout.  Error output should go to stderr.  Right now, we have sort of a mix.  Some things to to stderr when they should be going to stdout.

For example, I should be able to run commands like this without seeing output on the console:

'buildgit build > /tmp/buildout.log'
'buildgit status --all > /tmp/buildstatus.log'

you can see the difference when i run 'buildgit build' and choose to show it on the console, or redirect to a file.  We need to be consistent here.

A failed build does not mean we should write the build failure messages to stderr.

Things that should generate a stderr message:
- communication failure of any kind
- wrong syntax used for a command or option
- permission problems
- any other problem not related to the build we are monitoring or getting a snapshot status of

For example, this output we see today is wrong.  All of this output should have gone to stdout, i.e. the log file:

```
$ ./buildgit build > /tmp/outb.log
[10:38:56] ℹ Waiting for Jenkins build ralph1/main to start...
[10:38:56] ℹ Build #79 is QUEUED — In the quiet period. Expires in 4.9 sec
[10:39:01] ℹ Build #79 is QUEUED — Finished waiting
[10:39:14] ℹ   Stage: [agent6 guthrie] Build (4s)
[10:39:34] ℹ   Stage:   ║2 [agent6 guthrie] Unit Tests B (9s)    ← FAILED
[10:40:02] ℹ   Stage:   ║5 [agent7 guthrie] Unit Tests E (37s)
[10:40:28] ℹ   Stage:   ║3 [agent8_sixcore] Unit Tests C (1m 8s)
[10:40:55] ℹ   Stage:   ║1 [agent8_sixcore] Unit Tests A (1m 35s)
[10:41:02] ℹ   Stage:   ║4 [agent6 guthrie] Unit Tests D (1m 36s)
[10:42:05] ℹ   Stage:   ║6 [agent8_sixcore] Integration Tests (2m 48s)
[10:42:06] ℹ   Stage: All Tests (2m 48s)
[10:42:06] ℹ   Stage: Deploy (<1s)    ← FAILED
```


The output for push is also wrong. This is what I get now:

```
$ ./buildgit push > /tmp/pushlog.log
[10:44:24] ℹ Waiting for Jenkins build ralph1/main to start...
[10:44:41] ℹ   Stage: [agent6 guthrie] Build (4s)
[10:45:30] ℹ   Stage:   ║5 [agent7 guthrie] Unit Tests E (38s)
[10:46:09] ℹ   Stage:   ║2 [agent6 guthrie] Unit Tests B (1m 19s)
[10:46:16] ℹ   Stage:   ║3 [agent8_sixcore] Unit Tests C (1m 22s)
[10:46:23] ℹ   Stage:   ║1 [agent8_sixcore] Unit Tests A (1m 33s)
[10:46:30] ℹ   Stage:   ║4 [agent6 guthrie] Unit Tests D (1m 35s)
[10:47:24] ℹ   Stage:   ║6 [agent8_sixcore] Integration Tests (2m 32s)
[10:47:24] ℹ   Stage: All Tests (2m 32s)
[10:47:24] ℹ   Stage: [agent7 guthrie] Deploy (4s)
```

 