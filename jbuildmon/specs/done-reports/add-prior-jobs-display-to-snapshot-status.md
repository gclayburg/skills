 we need to add the option for prior jobs to the normal snapshot status command so someone types in Bill get status – – prior – jobs space five, then which we should show the normal status normal snapshot status output along with the prior jobs for the past five jobs so basically matching what we do for the monitoring commands like status – F or build or pus you make that match there's no reason why we can't have this snapshot status just show us perhaps the ability to show us the prior jobs in a one format as well. Everything else should be the same.

 e.g.  This should all be valid:
 ./buildgit status --prior-jobs 5 201
./buildgit status --prior-jobs 4
./buildgit status -n 5 --prior-jobs 3

In the last case, this would mean we would show the full status for the past 5 jobs just like we do now.  It also means that for the last job, we will show the prior jobs display of the last 3 builds.  These 3 lines would only be displayed as a part of the last build job printed.

This also means that we also need to show the prior 3 builds by default for any snapshot build status.  The user can override this setting with a --prior-jobs N  option
