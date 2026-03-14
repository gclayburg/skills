
Now, when I run 'status -f' to follow a build without any --job option, buildgit will assume I want $JOB/main.  This works, but it is too limiting.

```
$ ./buildgit  status -f
[11:24:09] ℹ Waiting for Jenkins build ralph1/main to start...
```

What we need instead is for the 'status -f' to wait for a build on ANY remote branch.  This also includes new remote branches that have not even been seen yet on the remote server.  The first one that starts to build will be shown on the screen. Any others that may exist in any state are ignored for this scenario.

What happens now, is that we implement a spec with a command like:

```
./jbuildmon/implement-spec.sh jbuildmon/specs/2026-03-14_standardize-stdout-stderr-spec.md 
```

This script will create a new local branch, and eventually will push it to the remote jenkins server.  This will take a while.  I want to be able to run 'buildgit status -f' in another terminal to show the build status when it starts.  

