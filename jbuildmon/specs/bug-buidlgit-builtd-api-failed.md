I get this error when running buildgit build:

$ ./buildgit build
[19:36:07] ℹ Verifying Jenkins connectivity...
[19:36:07] ✓ Connected to Jenkins
[19:36:07] ℹ Verifying job 'ralph1' exists...
[19:36:07] ✓ Job 'ralph1' found
[19:36:15] ⚠ Could not fetch build info for banner display
[19:36:15] ⚠ API request failed, retrying... (1/5)
[19:36:20] ⚠ API request failed, retrying... (2/5)
[19:36:25] ⚠ API request failed, retrying... (3/5)
[19:36:30] ⚠ API request failed, retrying... (4/5)
[19:36:35] ✗ Too many consecutive API failures (5)
[19:36:35] ✗ Build monitoring interrupted or timed out
Suggestion: Check Jenkins console at http://palmer.garyclayburg.com:18080/job/ralph1/[19:36:07] ℹ Waiting in queue: In the quiet period. Expires in 4.9 sec
[19:36:09] ℹ Waiting in queue: In the quiet period. Expires in 2.9 sec
[19:36:11] ℹ Waiting in queue: In the quiet period. Expires in 0.88 sec
[19:36:13] ℹ Waiting in queue: Finished waiting
91/console


When I run ./buildgit status -f, the output is much much better:

