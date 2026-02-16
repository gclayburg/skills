Let's change the output for the one line status output from this:

```
SUCCESS     Job ralph1 #178 completed in 4m 39s on 2026-02-15 (13 hours ago)
```

to this where we also show the test results:

```
SUCCESS     Job ralph1 #178 Tests=557/0/0(Took 4m 39s on 2026-02-15 (13 hours ago)
```

If the test result is unknown, print 'Tests=?/?/?' for the test section

For coloring, Tests=557/0/0 should be green if all tests are sucessful. It should be yellow if there are failing tests.  Maybe it should be red if all tests fail?  what is a good standard here?


