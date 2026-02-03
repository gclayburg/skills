Example pipeline stage report.  Note the slight indentation in the log line for each completed stage. This is make the output a little more visually distinctive.

[16:44:39] ℹ   Stage: Initialize Submodules (10s)
[16:44:39] ℹ   Stage: Build (100ms)
[16:46:41] ℹ   Stage: Unit Tests (2min 4s)
[16:46:41] ℹ   Stage: Deploy (101ms)


Success stages should be in green.  failed stages should be in red.  unstable stages should be in yellow