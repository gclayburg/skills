---
name: buildgit
description: Jenkins CI/CD build pipeline monitor. Check build status, push and monitor builds,  follow builds in real-time. Use when the user asks about CI/CD status,  build results, wants to push code and monitor the Jenkins build, or asks if CI is passing. Triggers include "check build", "build status", "is CI passing", "is the build green", "push and watch", "push and monitor", "what failed in CI",  "why did the build fail", "follow the build", "watch the build", "trigger a build",  "run the build".
license: MIT
---

# buildgit

A CLI for git operations and monitoring Jenkins CI/CD build pipelines.

## When to Use This Skill

- monitoring the status of a Jenkins build job for your project
- pushing your git changes and monitoring the Jenkins build
- triggerring a Jenkins build
- showing any Jenkins pipeline build errors 
- determining what failed in a build so it can be fixed

## What this skill does

- replacement for `git push` command.  Instead of `git push` use `buildgit push`
- uses git to push changes then expects a Jenkins build to automatically start, then monitors it
- shows Jenkins build status in many different ways
- uses Jenkins REST api to monitor and track a Jenkins pipeline build job
- any command unknown to `buildgit` is delegated to `git`, e.g. `buildgit log` would run `git log`

All paths in this document are relative to this SKILL.md file's directory, not the project root.

## How to use

```
what is the build status
```

```
push the staged changes and monitor the build.  fix any errors you find.
```



## Commands

| Command | Purpose |
|---------|---------|
| `scripts/buildgit status` | Jenkins build status snapshot |
| `scripts/buildgit status <build#>` | Status of one build (`31`, `0`, `-1`, `-2`) |
| `scripts/buildgit status --line` | One-line status for latest build |
| `scripts/buildgit status -n <N> --line` | One-line status for latest N builds (oldest first) |
| `scripts/buildgit status -n <N>` | Full snapshot output for latest N builds (oldest first) |
| `scripts/buildgit status -n <N> --json` | JSONL snapshot output for latest N builds |
| `scripts/buildgit status -n <N> --no-tests` | One-line status while skipping test-report API calls |
| `scripts/buildgit status --format '<fmt>'` | One-line status with custom format string (implies --line) |
| `scripts/buildgit status --all` | Force full snapshot output |
| `scripts/buildgit status -f --once` | Follow current/next build to completion, then exit (10s timeout) |
| `scripts/buildgit status -f --once=N` | Same, but wait up to N seconds for a build to start |
| `scripts/buildgit status -n N -f --once` | Show N prior builds then follow once with timeout |
| `scripts/buildgit status -f --line --once` | Follow builds with compact one-line output (TTY shows progress bar) |
| `scripts/buildgit status -n N -f --line --once` | Show N prior one-line rows then follow in one-line mode |
| `scripts/buildgit status --json` | Machine-readable Jenkins build status |
| `scripts/buildgit push` | git push + monitor Jenkins build until complete |
| `scripts/buildgit push --no-follow` | git push only, no build monitoring |
| `scripts/buildgit push --line` | git push + compact one-line monitoring (TTY shows progress bar) |
| `scripts/buildgit push --format '<fmt>'` | git push + compact one-line monitoring with custom format |
| `scripts/buildgit build` | Trigger a new build + monitor until complete |
| `scripts/buildgit build --no-follow` | Trigger only, no monitoring |
| `scripts/buildgit build --line` | Trigger + compact one-line monitoring (TTY shows progress bar) |
| `scripts/buildgit build --format '<fmt>'` | Trigger + compact one-line monitoring with custom format |
| `scripts/buildgit --console auto status` | Show default console log on failure |
| `scripts/buildgit --console N status` | Show last N raw console lines on failure |
| `scripts/buildgit --job <name> <cmd>` | Override auto-detected job name |
| `scripts/buildgit --version` | Show version number and exit |

Default one-line format (`status --line`, `push --line`, `build --line`) is:
`%s #%n id=%c Tests=%t Took %d on %I (%r)`

## Interpreting Output

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Success (build passed, or git command succeeded) |
| 1 | Build failed, or an error occurred |
| 2 | Build is currently in progress |

**Build states:**  as reported by Jenkins
- `SUCCESS` — build passed, all tests green
- `FAILURE` — build failed; output includes failed stage and error details
- `BUILDING` — build is still running
- `ABORTED` — build was manually cancelled
- `UNSTABLE` — build completed with test failures or marked warnings (common for flaky tests)
- `NOT_BUILT` — build was skipped or not executed (e.g., due to upstream failure or explicit skip)
- `UNKNOWN` — the state could not be determined (e.g., API error, incomplete data)
- `QUEUED` — build is waiting in the Jenkins queue and hasn't started running yet

For failures, summarize the failed stage name, error logs, and test failure details for the user.

For snapshot mode defaults, `scripts/buildgit status` is TTY-aware:
- TTY stdout: full output
- non-TTY stdout (pipe/redirect): one-line output
- Exception: when `-n` is provided without `--line`, snapshot output is full multi-build mode.

Build reference rules:
- `0` and `-0` mean latest/current build
- Negative values (`-1`, `-2`) are relative offsets from latest build
- Build reference and `-n` are mutually exclusive

**Console log (`--console`):**
On failed builds, buildgit shows a curated error summary by default.
- `--console auto` — force the default error log display even when test failures are present
- `--console N` — show last N raw console lines instead of curated summary (useful for troubleshooting)

For agent-safe follow mode, prefer:
- `scripts/buildgit status -f --once` to follow exactly one build and exit

## Dynamic Context

To inject live build state into context before reasoning about build issues:

```
`scripts/buildgit status --json 2>/dev/null`
```

## References

See [references/buildgit-setup.md](references/buildgit-setup.md) for setup instructions (required tools, fixing permission errors,project setup, needed network access, docker sandbox instructions)
See [references/reference.md](references/reference.md) for real-world output examples
(push failures, parallel pipelines, progress bars, live follow mode).
