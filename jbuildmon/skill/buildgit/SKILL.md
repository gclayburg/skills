---
name: buildgit
description: Jenkins CI/CD build monitor. Check build status, push and monitor builds,  follow builds in real-time. Use when the user asks about CI/CD status,  build results, wants to push code and monitor the Jenkins build, or asks if CI is passing. Triggers include "check build", "build status", "is CI passing", "is the build green", "push and watch", "push and monitor", "what failed in CI",  "why did the build fail", "follow the build", "watch the build", "trigger a build",  "run the build".
license: MIT
---

# buildgit

A unified CLI for git operations with Jenkins CI/CD integration.
## Prerequisites

Before running any command, verify:
1. Jenkins env vars are set: `JENKINS_URL`, `JENKINS_USER_ID`, `JENKINS_API_TOKEN`
2. Project has `JOB_NAME=<name>` in its CLAUDE.md or AGENTS.md

If any prerequisite is missing, tell the user what's needed instead of attempting the command.

The `buildgit` script is bundled at `scripts/buildgit` within this skill package.

## Commands

| Command | Purpose |
|---------|---------|
| `scripts/buildgit status` | Jenkins build status snapshot |
| `scripts/buildgit status <build#>` | Status of a specific build number |
| `scripts/buildgit status --line` | One-line status for latest build |
| `scripts/buildgit status -n <N> --line` | One-line status for latest N builds (oldest first) |
| `scripts/buildgit status -n <N> --no-tests` | One-line status while skipping test-report API calls |
| `scripts/buildgit status --all` | Force full snapshot output |
| `scripts/buildgit status -f` | Follow builds in real-time (Ctrl+C to stop) |
| `scripts/buildgit status -f --once` | Follow current/next build to completion, then exit (10s timeout) |
| `scripts/buildgit status -f --once=N` | Same, but wait up to N seconds for a build to start |
| `scripts/buildgit status -n N -f` | Show N prior completed builds then follow indefinitely |
| `scripts/buildgit status -n N -f --once` | Show N prior builds then follow once with timeout |
| `scripts/buildgit status -f --line` | Follow builds with compact one-line output (TTY shows progress bar) |
| `scripts/buildgit status -n N -f --line` | Show N prior one-line rows then follow in one-line mode |
| `scripts/buildgit status --json` | Machine-readable Jenkins build status |
| `scripts/buildgit push` | Push + monitor Jenkins build until complete |
| `scripts/buildgit push --no-follow` | Push only, no build monitoring |
| `scripts/buildgit build` | Trigger a new build + monitor until complete |
| `scripts/buildgit build --no-follow` | Trigger only, no monitoring |
| `scripts/buildgit --job <name> <cmd>` | Override auto-detected job name |

## Interpreting Output

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Success (build passed, or git command succeeded) |
| 1 | Build failed, or an error occurred |
| 2 | Build is currently in progress |

**Build states:**
- `SUCCESS` — build passed, all tests green
- `FAILURE` — build failed; output includes failed stage and error details
- `BUILDING` — build is still running
- `ABORTED` — build was manually cancelled

For failures, summarize the failed stage name, error logs, and test failure details for the user.

For snapshot mode defaults, `scripts/buildgit status` is TTY-aware:
- TTY stdout: full output
- non-TTY stdout (pipe/redirect): one-line output

For agent-safe follow mode, prefer:
- `scripts/buildgit status -f --once` to follow exactly one build and exit
- `scripts/buildgit status -f` only when you intentionally want indefinite monitoring

## Dynamic Context

To inject live build state into context before reasoning about build issues:

```
!`scripts/buildgit status --json 2>/dev/null`
```

## Reference

See [references/reference.md](references/reference.md) for full command documentation, example output, and troubleshooting.
