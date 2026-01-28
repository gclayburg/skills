# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) amd other agents like Cursor when working with code in this repository.

## Project Overview

This repository contains **jbuildmon** (Jenkins Build Monitor), a CLI tool that automates the developer workflow of committing code, pushing to a remote repository, and monitoring the resulting Jenkins CI/CD build until completion.

## Detailed Specifications
- see specs/README.md

## Building

- Jenkins build server will build automatically on a git push to origin
- JOB_NAME=ralph1

## Testing
- jbuildmon uses bats-core located at jbuildmon/test/bats/bin/bats

## Key Commands

### Checking Build Status (`/checkbuild`)

```bash
./jbuildmon/checkbuild.sh [--json]
```

Queries Jenkins for the current status of the last build. Reports:
- Build result (success/failure/in-progress)
- Trigger type (automated push vs manual)
- Commit correlation with local git history
- Detailed failure analysis with error logs

**Exit codes:** 0 (success), 1 (failure), 2 (in progress)

### Running the Build Monitor (`jbuildmon`)

```bash
./jbuildmon/pushmon.sh <job-name> "<commit-message>"
```

Commits staged code, pushes to origin, and monitors the Jenkins build until completion.

**Exit codes:** 0 (success), 1 (failure), 130 (interrupted)

### Required Environment Variables

Both tools require:
- `JENKINS_URL` - Jenkins server URL (e.g., `http://jenkins.example.com:8080`)
- `JENKINS_USER_ID` - Jenkins username
- `JENKINS_API_TOKEN` - Jenkins API token

## Architecture

### Build Status Checker: `jbuildmon/checkbuild.sh`

A CLI tool that queries Jenkins for the current build status:

1. **Job Discovery** - Finds job name from AGENTS.md (`JOB_NAME=...`) or git origin URL
2. **Build Info** - Fetches last build status from Jenkins API
3. **Trigger Detection** - Determines if build was automated (push) or manual
4. **Commit Correlation** - Checks if triggering commit is in local git history
5. **Failure Analysis** - For failed builds, traces downstream failures and extracts error logs

### Build Monitor: `jbuildmon/pushmon.sh`

A single-file bash script (~850 lines) implementing the full workflow:

1. **Validation** - Validates args, env vars, git repo, `jq` dependency, Jenkins connectivity
2. **Git Operations** - Detects staged changes/unpushed commits, commits, rebases if behind remote, pushes
3. **Build Detection** - Polls Jenkins API until a new build starts (120s timeout)
4. **Build Monitoring** - Tracks build progress via workflow API, displays current stage (30 min timeout)
5. **Failure Analysis** - On failure, identifies failed stage, detects downstream builds, extracts relevant logs

### Configuration Constants (can be overridden via env vars)

| Constant | Default | Description |
|----------|---------|-------------|
| `BRANCH` | `main` | Git branch to push to |
| `POLL_INTERVAL` | 5s | Time between API polls |
| `BUILD_START_TIMEOUT` | 120s | Max wait for build to start |
| `MAX_BUILD_TIME` | 1800s | Max wait for build completion |

### Jenkins API Endpoints Used

- `/api/json` - Connectivity check
- `/job/{job}/api/json` - Job existence verification
- `/job/{job}/lastBuild/api/json` - Build number baseline
- `/job/{job}/{build}/api/json` - Build status
- `/job/{job}/{build}/wfapi/describe` - Pipeline stage info
- `/job/{job}/{build}/consoleText` - Console output
- `/queue/api/json` - Queue status

## Specifications

- `jbuildmon/specs/jenkins-build-monitor-spec.md` - Full functional specification for pushmon
- `jbuildmon/specs/pushmon_implementation_plan.md` - Implementation checklist with bug fix history
- `jbuildmon/specs/checkbuild-spec.md` - Full functional specification for checkbuild
- `jbuildmon/specs/checkbuild-plan.md` - Implementation plan and progress tracking
