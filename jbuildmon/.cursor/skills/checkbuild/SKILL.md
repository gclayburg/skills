---
name: checkbuild
description: Check Jenkins build status for the current repository
disable-model-invocation: true
---

# checkbuild

Queries Jenkins to report the current status of the last build for the job associated with the current git repository. Correlates the triggering commit with local git history to determine if the build was triggered by your changes or by someone else.

## Usage

```bash
path/to/checkbuild.sh [--json]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--json` | No | Output results in JSON format for machine parsing |

## What This Skill Reports

- Whether the last build succeeded, failed, or is in progress
- Who/what triggered the build (automated push vs manual trigger)
- Whether the triggering commit is in your local history
- Detailed failure information including:
  - Failed jobs tree (including downstream builds)
  - Error logs from the failed stage
  - Build metadata (user, agent, pipeline)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Last build was successful |
| 1 | Last build failed, or an error occurred |
| 2 | Build is currently in progress |

## Environment Variables (Required)

- `JENKINS_URL` - Jenkins server URL (e.g., `http://jenkins.example.com:8080`)
- `JENKINS_USER_ID` - Jenkins username
- `JENKINS_API_TOKEN` - Jenkins API token

## Agent Instructions

When a user asks about the Jenkins build status, invokes `/checkbuild`, or wants to know if the CI is passing:

1. Run `checkbuild.sh` from the jbuildmon directory
2. Present the output to the user
3. For failures, the output includes error logs - summarize the key issues
4. For in-progress builds, inform the user they may want to wait and check again

### Job Name Discovery

The skill automatically discovers the Jenkins job name:

1. **AGENTS.md** - Looks for `JOB_NAME=<jobname>` in the repository root
2. **Git origin fallback** - Extracts repository name from git origin URL

### Example Commands

```bash
# Check build status (human-readable output)
./jbuildmon/checkbuild.sh

# Check build status (JSON output for parsing)
./jbuildmon/checkbuild.sh --json
```

## Related Skills

- `jbuildmon` - Commits code, pushes to origin, and monitors the Jenkins build
