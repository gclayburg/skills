If I  do a buildgit status, I see that all 6 stagess are shown in the output.  If I do a 'buildgit status -f' in another window, it does not show all the Stage: lines.  it only shows 

buildgit status

```bash
[17:25:44] ℹ   Stage: Declarative: Checkout SCM (<1s)
[17:25:44] ℹ   Stage: Declarative: Agent Setup (1s)
[17:25:44] ℹ   Stage: Initialize Submodules (10s)
[17:25:44] ℹ   Stage: Build (<1s)
[17:25:44] ℹ   Stage: Unit Tests (2s)
[17:25:44] ℹ   Stage: Deploy (<1s)
```

buildgit status -f

```bash
[17:24:37] ℹ   Stage: Declarative: Checkout SCM (<1s)
[17:24:37] ℹ   Stage: Declarative: Agent Setup (running)
[17:24:53] ℹ   Stage: Initialize Submodules (10s)
```

as you can see, it shows (running) which is wrong.  It should only show the time it took to run.  it should never show 'running'. It also does not show the stages that either failed or did not finish.  It needs to show all the stages.  'buildgit status' does show all the stages in the correct color.