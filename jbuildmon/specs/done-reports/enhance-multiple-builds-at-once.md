
This display still seems to flash too much `buildgit status -f`

```
IN_PROGRESS Job ralph1 #225 [===========>        ] 64% 3m 44s / ~5m 49s
QUEUED     Job ralph1 #226 [           <===>    ] 3m 1s in queue / ~5m 49s
```


The other monitoring style builds like `buildgit push` only show the build they initially started.  They do not show the QUEUED build behind them like `buildgit status -f` does
All of the monitoring style status commands need to show new builds that are started after our currently monitored build as well.



Also, The output for this `build` command issn't quite right.  It shows the QUEUED information, but there is too much output.

```
$ buildgit --job ralph1 build
[18:12:51] ℹ Waiting for Jenkins build ralph1 to start...
[18:12:52] ℹ Build #226 is QUEUED — In the quiet period. Expires in 4.9 sec
[18:12:54] ℹ Build #226 is QUEUED — In the quiet period. Expires in 2.9 sec
[18:12:56] ℹ Build #226 is QUEUED — In the quiet period. Expires in 0.87 sec
[18:12:58] ℹ Build #226 is QUEUED — Finished waiting
[18:13:00] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 59 sec)
[18:13:02] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 57 sec)
[18:13:04] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 55 sec)
[18:13:06] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 53 sec)
[18:13:08] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 51 sec)
[18:13:10] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 49 sec)
```

There is simply too many lines printed.  We don't need a new line every 2 seconds for something that is going to take 5 minutes.  Instead, if we are on a tty, we should show a progress bar at the bottom that is updated on each interval.  Once the build starts, we can print out the build as normal.  If we are not on a tty, then continue to poll, but only print a new line of output every 30 seconds, or when the internal polling determines that a new build has started.  We need this same behaviour for `build` and `push`.

So in the tty case, it should show:

```
[18:12:52] ℹ Build #226 is QUEUED
Build #226 is QUEUED — In the quiet period. Expires in 0.87 sec
```

The last line is the progress indicator.  when the quiet period is over we should see:

```
[18:12:52] ℹ Build #226 is QUEUED
[18:12:58] ℹ Build #226 is QUEUED — Finished waiting
Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 59 sec)
IN_PROGRESS Job ralph1 #225 [===========>        ] 64% 3m 44s / ~5m 49s
```

In this case, the last 2 lines are progress bar lines that get updated on each poll.

Now, if we are not on a tty, it should print something like this:

```
$ buildgit --job ralph1 build
[18:12:51] ℹ Waiting for Jenkins build ralph1 to start...
[18:12:52] ℹ Build #226 is QUEUED — In the quiet period. Expires in 4.9 sec
[18:12:54] ℹ Build #226 is QUEUED — In the quiet period. Expires in 2.9 sec
[18:12:56] ℹ Build #226 is QUEUED — In the quiet period. Expires in 0.87 sec
[18:12:58] ℹ Build #226 is QUEUED — Finished waiting
[18:13:00] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 59 sec)
[18:12:30] ℹ Build #226 is QUEUED — Build #225 is already in progress (ETA: 4 min 29 sec)
```

New status lines of the build in progress are only printed every 30 seconds unless the build is about to start, or it did actually start.

