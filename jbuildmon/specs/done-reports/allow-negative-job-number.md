today we have this:

```
 buildgit status 31           # Status of build #31
```

 We need to modify this so that we also allow the user to specify a negative number, or 0. 0 means show the status of the current build.  A negative number means show an older build, i.e.
 0 current build in progress or last completed build
 -1 not the current build, but 1 build before that
 -2 not the current build, but 2 builds before that


 These numbers would essentially be equivalent to -n 1 or -n 2

 This also means these commands should be equivalent:

 ```
 $ buildgit status -n 3 --line
 $ buildgit status -3 --line
```

 Also, when testing this, I see that there is a problem with the -n option now to status. if we run this:

```
 $ buildgit status -n 2
```

 then buildgit only shows us the very last build.  It is supposed to show us the status for the last 2 builds, just like `buildgit status -n  2 --line` does now.