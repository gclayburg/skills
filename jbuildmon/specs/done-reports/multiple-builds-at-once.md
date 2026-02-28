We see this progress indicator at the bottom of the output now when we run a `buildgit status -f` and we are running on a tty.

```
IN_PROGRESS Job ralph1 #218 [=>                  ] 11% 41s / ~6m 15s
```

This is working well.  One thing I will point out though is that there is a noticeable 'flash' when the display updates every few seconds.  the display goes black for a split second before it repaints.  It is a noticeable delay.  can you adjust this so that the delay is minimized?

Also, we need to accomodate for the situation where we have multiple builds going on for a job that is being monitored with `buildgit status -f`.  We only show one build in progress now.  If another build starts up after we have started monitoring, we need to show that as well on the progress bar.  We don't need to show anything on the mornal status lines like individual stage output, or other infomration about the build.

We just need the progress bar to also include these other jobs that are also building like this:

```
IN_PROGRESS Job ralph1 #218 [=>                  ] 11% 41s / ~6m 15s
IN_PROGRESS Job ralph1 #219 [=>                  ] 1% 2s / ~6m 15s
```

We also need to account for the situation where the build job was setup to not allow concurrent builds.  If this is the case now, we will get this kind of output for a build request:

```
$ buildgit --job ralph1 build
[16:49:03] ℹ Waiting for Jenkins build ralph1 to start...
```

basicially, it waits, but it doesn't print out that we are waiting for a prior build.  We need to print out that the build is waiting for a prior build.  Instead, we eventually see this now:

```
$ buildgit --job ralph1 build
[16:49:03] ℹ Waiting for Jenkins build ralph1 to start...
[16:51:06] ✗ Timeout: Build did not start within 120 seconds
[16:53:07] ✗ Timeout: No build started within 120 seconds
[16:53:07] ✗ Build did not start within timeout
Suggestion: Check Jenkins queue at http://palmer.garyclayburg.com:18080/queue/
```

This is not correct.  We need to determine that there is a build in progress and just wait for it to start in this case.  The jenkins console UI shows "Build #219 is alreday in progress  ETA: 1m 34s".  This is much closer to the output we should show as well.  We should also show that our build will be #220, for example, but it is in  a QUEUE state - or actually lets use the state that Jenkins itself uses for this condition.  we jsut want to update the user so they know what to expect.  Once the other build finishes, then we should show the output like normal.


Now back to the `buildgit status -f` display when there are multiple jobs building, but the job is setup to only allow one  build at time.  In this case a the progress bar should be updated to look like this when it determines that another build wants to start, but is waiting for this one to finish:

```
IN_PROGRESS Job ralph1 #218 [=>                  ] 11% 41s / ~6m 15s
IN_QUEUE Job ralph1 #219 [=>                  ] 1% 2s / ~6m 15s
```

Again, use the actual Jenkins terminology for the IN_QUEUE part.  this should match the output of progress indicator of `build` and `push` commands that also run into a QUEUE state.

