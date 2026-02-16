I get this now when I run a multiline outout:

```bash
$ buildgit --job ralph1 status --line=10
UNSTABLE Job ralph1 #176 completed in 4m 37s on 2026-02-15 (42 minutes ago)
UNSTABLE Job ralph1 #175 completed in 4m 37s on 2026-02-15 (3 hours ago)
SUCCESS Job ralph1 #174 completed in 4m 32s on 2026-02-14 (19 hours ago)
UNSTABLE Job ralph1 #173 completed in 4m 55s on 2026-02-14 (19 hours ago)
UNSTABLE Job ralph1 #172 completed in 3m 46s on 2026-02-14 (22 hours ago)
SUCCESS Job ralph1 #171 completed in 3m 32s on 2026-02-13 (1 day ago)
SUCCESS Job ralph1 #170 completed in 3m 18s on 2026-02-13 (2 days ago)
SUCCESS Job ralph1 #169 completed in 3m 14s on 2026-02-13 (2 days ago)
SUCCESS Job ralph1 #168 completed in 3m 15s on 2026-02-13 (2 days ago)
SUCCESS Job ralph1 #167 completed in 3m 13s on 2026-02-13 (2 days ago)
```

We need to align the status column so they look consistent.  Let's pad the output to 10 characters.  Truncate any status that is longer than 10 characters.
Also, we need to color the status field according to the rules we alrady use.  But, if the stdout is not a tty, we should not use colors.  I believe this is what we alrady do.
