I am not able to run checkbuild.sh on some repos.  Here is an example:

$ ./checkbuild.sh --job lifeminder
[12:15:37] ℹ Using specified job: lifeminder
[12:15:37] ℹ Verifying Jenkins connectivity...
[12:15:37] ✓ Connected to Jenkins
[12:15:37] ℹ Verifying job 'lifeminder' exists...
[12:15:37] ✓ Job 'lifeminder' found
[12:15:37] ℹ Fetching last build information...
[12:15:37] ✓ Build #156 found
[12:15:37] ℹ Analyzing build details...


As you can see it does find the job, but doesn't show any deatils about it.  The script just exits with an exit code of 1.  It should show me that the build is successful.

Here is another example:

$ ./checkbuild.sh --job visualsync
[12:07:58] ℹ Using specified job: visualsync
[12:07:58] ℹ Verifying Jenkins connectivity...
[12:07:58] ✓ Connected to Jenkins
[12:07:58] ℹ Verifying job 'visualsync' exists...
[12:07:58] ✓ Job 'visualsync' found
[12:07:58] ℹ Fetching last build information...
[12:07:58] ✓ Build #1967 found
[12:07:58] ℹ Analyzing build details...


This one is very similar.  it finds the job, but it does not show me that last build was successful.  Note that in both of these examples, the pwd is a git repo, but it does not match the --job .  What the code needs to do is just show me the status of the last build that I asked for.  it should not care where the pwd is.

Note also, that the command does work for some other jobs like this:

$ ./checkbuild.sh --job msolitaire
[12:20:35] ℹ Using specified job: msolitaire
[12:20:35] ℹ Verifying Jenkins connectivity...
[12:20:35] ✓ Connected to Jenkins
[12:20:35] ℹ Verifying job 'msolitaire' exists...
[12:20:35] ✓ Job 'msolitaire' found
[12:20:35] ℹ Fetching last build information...
[12:20:35] ✓ Build #95 found
[12:20:35] ℹ Analyzing build details...

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        msolitaire
Build:      #95
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     299598f - "minor change"
            ✗ Unknown commit
Duration:   2m 32s
Completed:  2025-01-27 16:54:54

Console:    http://palmer.garyclayburg.com:18080/job/msolitaire/95/console


Perhaps  there is somethign about how these jobs are setup in jenkins that prevents the script from showing us the output?

