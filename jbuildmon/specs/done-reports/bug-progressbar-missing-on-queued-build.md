
```
$ buildgit --job ralph1 build
[19:40:41] ℹ Waiting for Jenkins build ralph1 to start...
[19:40:41] ℹ Build #232 is QUEUED — In the quiet period. Expires in 4.9 sec
[19:40:47] ℹ Build #232 is QUEUED — Finished waiting
[19:40:52] ℹ Build #232 is QUEUED — Build #231 is already in progress (ETA: 2 min 28 sec)
```

This output is not right.  we are on a tty, so we should see a progress bar like the spec says, right?  I see the similar output for the 'push' command.  There just isn't a progress bar shown.

