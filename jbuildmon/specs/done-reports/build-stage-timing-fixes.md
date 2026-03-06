# Build Stage Timing Fixes

## Summary

These changes fix several timing and ordering races in the shared live-monitor path used by `buildgit build`, `buildgit status -f`, and `buildgit push` so that stage output during a live Jenkins build is consistent with the final `buildgit status --all` snapshot.

The focus of the fix was the realtime monitor path for completed stages, especially around parallel stages, the final completion window, and TTY vs non-TTY output parity.

## Additional Review Outcome

During review of the earlier job, one more shared monitor bug was found:

- in TTY mode, stage lines captured on the exact poll where Jenkins first reported the build as finished could be dropped before they were printed
- in non-TTY mode, the same lines still appeared because stage tracking wrote directly to stderr

This meant commands using the same monitor loop could disagree depending on whether stdout was attached to a terminal:

- `buildgit build`
- `buildgit status -f`
- `buildgit push`

The fix now flushes any pending captured stage/header output before the completion settle loop starts, so terminal and non-terminal runs show the same completion-stage lines.

## What It Does Now

### Parallel stages print as each branch finishes

Parallel branches are no longer held until the entire wrapper stage completes.

Current behavior:

- If `Unit Tests C` finishes first, it prints first.
- If `Unit Tests B` finishes next, it prints next.
- Each branch prints only when Jenkins has reported a stable terminal duration for that branch.
- This prevents premature lines like `<1s` or `unknown` for branches that are not actually finalized yet.

### Final parallel branch and wrapper are not skipped

The monitor now keeps tracking the unfinished parallel block through build completion.

Current behavior:

- The last finishing parallel branch such as `Unit Tests D` must print.
- After all branches in the wrapper have printed and the wrapper duration is stable, the wrapper stage such as `Unit Tests` prints.
- Only after that can later stages such as `Deploy` print.

### Later stages do not overtake earlier deferred stages

A later top-level stage is now blocked if an earlier terminal stage still has not been printed.

This specifically fixes cases where:

- `Deploy` printed before `Unit Tests D`
- `Deploy` printed before the `Unit Tests` wrapper
- the build ended with missing late-stage output

Current behavior:

- Stage output respects execution order across deferred stages.
- Parallel siblings can still print independently from each other.
- But a later unrelated stage cannot jump ahead of an earlier unprinted stage group.

### Completion polling no longer stalls unnecessarily

The monitor used a completion settle loop after Jenkins first reported the build as finished. That loop previously kept waiting because internal poll counters changed every pass, even when no meaningful stage data changed.

Current behavior:

- The settle loop now ignores counter-only bookkeeping changes.
- Once the visible stage graph is stable and all terminal stages are printed, the monitor exits promptly.
- This removes the long pause between the last stage line and the final `Finished:` / `Duration:` lines.

### Running-build banner no longer seeds bad stage state

The initial banner for a running build previously could seed the monitor with incomplete completed-stage data and cause bogus early lines like:

- `Unit Tests A (<1s)`
- `Unit Tests C (unknown)`
- `Unit Tests D (unknown)`

Current behavior:

- The running-build banner now uses the tracked stage logic instead of raw completed-stage rendering.
- A live build starts by printing only stages that are actually safe to show.
- This prevents early phantom parallel completion lines from poisoning later monitoring.

## Expected Live Behavior

For the `ralph1/main` job used during validation, the expected live order is:

1. `Build`
2. `Unit Tests B`
3. `Unit Tests C`
4. `Unit Tests A`
5. `Unit Tests D`
6. `Unit Tests`
7. `Deploy`

Exact seconds can vary by a second on some runs, but the important rules are:

- all completed branches print
- the final branch `Unit Tests D` prints
- the wrapper `Unit Tests` prints
- `Deploy` prints after the wrapper
- no bogus `<1s` or `unknown` parallel completion lines appear at startup

## Validation Performed

### Automated tests

Regression coverage was added for:

- later stages waiting behind unfinished deferred stages
- completion settle-loop stabilization
- forced completion flush for missing terminal stages
- running-build banner seeding behavior
- TTY vs non-TTY completion-stage parity for `buildgit build`
- TTY vs non-TTY completion-stage parity for `buildgit status -f`
- TTY vs non-TTY completion-stage parity for `buildgit push`

Full test suite result at final state:

- `jbuildmon/test/bats/bin/bats jbuildmon/test/`
- `1..699`
- all passing

### Live Jenkins verification

The real binary was run repeatedly with:

- `./jbuildmon/buildgit --job ralph1/main build`
- `./jbuildmon/buildgit --job ralph1/main status <build> --all`

Three consecutive live validation runs were completed successfully:

#### Build #36

Live `build` output included:

- `Build (3s)`
- `Unit Tests B (1m 18s)`
- `Unit Tests C (1m 42s)`
- `Unit Tests A (1m 56s)`
- `Unit Tests D (2m 16s)`
- `Unit Tests (2m 16s)`
- `Deploy (3s)`

`status 36 --all` matched the final timings.

#### Build #37

Live `build` output included:

- `Build (3s)`
- `Unit Tests B (1m 18s)`
- `Unit Tests C (1m 43s)`
- `Unit Tests A (1m 56s)`
- `Unit Tests D (2m 16s)`
- `Unit Tests (2m 16s)`
- `Deploy (3s)`

`status 37 --all` matched the final timings.

#### Build #38

Live `build` output included:

- `Build (4s)`
- `Unit Tests B (1m 18s)`
- `Unit Tests C (1m 43s)`
- `Unit Tests A (1m 56s)`
- `Unit Tests D (2m 16s)`
- `Unit Tests (2m 16s)`
- `Deploy (3s)`

`status 38 --all` matched the final timings.

### Additional live validation after TTY/non-TTY review

Further live runs on March 5, 2026 confirmed the missing-final-stage regression is gone in both terminal and non-terminal monitor modes:

- `./jbuildmon/buildgit --job ralph1/main build` for build `#41`
- `./jbuildmon/buildgit --job ralph1/main status -f --once --prior-jobs 0` while build `#41` was running
- `./jbuildmon/buildgit --job ralph1/main build` without a TTY for build `#42`
- `./jbuildmon/buildgit --job ralph1/main status -f --once --prior-jobs 0` with a TTY while build `#42` was running
- `./jbuildmon/buildgit --job ralph1/main status 41 --all`
- `./jbuildmon/buildgit --job ralph1/main status 42 --all`

Observed on both builds:

- `Unit Tests D` printed in live monitoring before completion
- `Unit Tests` wrapper printed after the last branch
- `Deploy` printed before the final `Finished:` line
- finished snapshots for builds `#41` and `#42` matched the live stage sets

## What The Validator Should Check

When validating this behavior manually, the assistant should confirm:

1. `buildgit build` prints each parallel branch when it finishes, not all at once at the end.
2. `Unit Tests D` is printed before completion.
3. The wrapper stage `Unit Tests` is printed before `Deploy`.
4. `Deploy` is printed before the final `Finished:` line.
5. The final live output matches `buildgit status --all` for the same build number.
6. There are no startup artifacts showing parallel branches with `<1s` or `unknown` unless those are truly final Jenkins values.
7. The same completion-stage lines appear whether monitoring output is attached to a TTY or not.
8. The same completion-stage behavior holds for `buildgit build`, `buildgit status -f`, and `buildgit push`.

## Residual Risk

This has now passed repeated live runs, but the remaining risk area is Jenkins API inconsistency during very active concurrent builds on the same job.

The monitor is attached to a specific build number, so stage data should remain build-specific after attachment. If a future issue appears, the most likely source is Jenkins publishing incomplete `wfapi` or console-derived structure during a narrow polling window, not cross-build contamination after the target build number is known.
