# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) amd other agents like Cursor when working with code in this repository.

## Project Overview

This repository contains **jbuildmon** (Jenkins Build Monitor), a CLI tool that automates the developer workflow of committing code, pushing to a remote repository, and monitoring the resulting Jenkins CI/CD build until completion.


## Building

- Jenkins build server will build automatically on a git push to origin
- JOB_NAME=ralph1


## Key Commands

### Running the Build Monitor

```bash
./jbuildmon/pushmon.sh <job-name> "<commit-message>"
```

**Required environment variables:**
- `JENKINS_URL` - Jenkins server URL (e.g., `http://jenkins.example.com:8080`)
- `JENKINS_USER_ID` - Jenkins username
- `JENKINS_API_TOKEN` - Jenkins API token

**Exit codes:** 0 (success), 1 (failure), 130 (interrupted)

## Architecture

### Main Script: `jbuildmon/pushmon.sh`

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

- `jbuildmon/specs/jenkins-build-monitor-spec.md` - Full functional specification
- `jbuildmon/specs/pushmon_implementation_plan.md` - Implementation checklist with bug fix history
