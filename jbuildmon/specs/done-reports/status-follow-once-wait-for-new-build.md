# Feature request: `buildgit status -f --once` should wait for a *new* build (up to 10s)

## Summary

Current behavior for `buildgit status -f --once` can immediately display the most recent completed build (even if it finished hours/days/weeks ago) and then exit.

Requested behavior: when `--once` is used with follow mode, do **not** replay an old completed build if nothing is running now.

## Desired behavior

Command: `buildgit status -f --once`

1. If a build is currently in progress at command start:
   - Follow that in-progress build to completion
   - Exit after completion (existing once behavior)

2. If no build is currently in progress at command start:
   - Wait for a **new build to start** for up to **10 seconds**
   - If a new build starts within 10 seconds:
     - Follow that new build to completion
     - Exit
   - If no new build starts within 10 seconds:
     - Exit immediately (non-blocking beyond timeout)
     - Do not display old completed build output

## Explicit non-goal

- Do not show status/details from a previously completed build when using `status -f --once` and no build is running now.

## Rationale

`--once` is intended for agent/script-safe monitoring of a single upcoming/current build. Replaying stale completed builds is misleading and causes incorrect automation decisions.

## Example flow

- `buildgit status -f --once` invoked at 10:00:00
- Latest known build is #412 (completed yesterday)
- No build currently running
- Tool waits until 10:00:10 for a new build
  - If build #413 starts at 10:00:06: monitor #413 and exit when done
  - If nothing starts by 10:00:10: exit; show timeout/no-new-build message; do not show #412

## Suggested acceptance criteria

- `status -f --once` never prints stale completed-build output when no build is running at start.
- Wait window is capped at 10 seconds.
- If a build starts inside that window, it is monitored and completion status determines exit code.
- If no build starts inside that window, command exits quickly without indefinite wait.
