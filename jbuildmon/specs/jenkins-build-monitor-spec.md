# Jenkins Build Monitor - Functional Specification

## Overview

The Jenkins Build Monitor is a command-line tool that automates the workflow of committing code changes, pushing to a remote repository, and monitoring the resulting Jenkins CI/CD build until completion. It provides real-time feedback on build progress and detailed failure analysis when builds fail.

## Purpose

This tool streamlines the developer workflow by combining multiple steps (commit, push, monitor, analyze) into a single command, eliminating the need to manually check Jenkins for build status.

---

## Prerequisites

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `JENKINS_URL` | Base URL of the Jenkins server (e.g., `http://jenkins.example.com:8080` or `https://jenkins.example.com`) |
| `JENKINS_USER_ID` | Jenkins username for API authentication |
| `JENKINS_API_TOKEN` | Jenkins API token for authentication (not password) |

### External Dependencies

- **JSON Parser**: A tool capable of parsing JSON responses (e.g., `jq` in bash implementations)
- **Git**: Must be run from within a valid git repository with an `origin` remote configured
- **HTTP Client**: Capability to make authenticated HTTP requests to Jenkins REST API

---

## Command Interface

### Usage

```
jenkins-build-monitor <job-name> <commit-message>
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `job-name` | Yes | The exact name of the Jenkins job to monitor |
| `commit-message` | Yes | The git commit message for staged changes |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Build completed successfully |
| 1 | Build failed, or an error occurred during execution |
| 130 | Script was interrupted by user (Ctrl+C) |

---

## Functional Requirements

### 1. Startup Validation

Before performing any operations, the tool must validate:

1. **Arguments**: Both `job-name` and `commit-message` must be provided
2. **Environment Variables**: All three required environment variables must be set and non-empty
3. **JENKINS_URL Format**: Must begin with `http://` or `https://`; trailing slashes should be normalized (removed)
4. **Git Repository**: Must be run from within a valid git repository
5. **Git Remote**: The repository must have an `origin` remote configured
6. **JSON Parser**: The required JSON parsing tool must be available

### 2. Jenkins Connectivity Verification

Before proceeding with git operations:

1. **Test Connection**: Make an authenticated request to `${JENKINS_URL}/api/json`
2. **Handle Authentication Errors**: Detect and report 401 (bad credentials) and 403 (permission denied) errors
3. **Verify Job Exists**: Confirm the specified job exists at `${JENKINS_URL}/job/${job-name}/api/json`

### 3. Git Operations

#### 3.1 Check for Changes

Determine what needs to be pushed:

1. **Staged Changes**: Check if there are staged (but uncommitted) changes
2. **Unpushed Commits**: If no staged changes, check if there are local commits not yet pushed to origin

If neither staged changes nor unpushed commits exist, the operation must fail with an appropriate error message.

#### 3.2 Commit (if applicable)

If staged changes exist:

1. Create a commit with the provided commit message
2. Record the commit hash for logging purposes

#### 3.3 Sync with Remote

1. **Fetch**: Retrieve the latest state from `origin/${BRANCH}` (where BRANCH defaults to `main`)
2. **Detect Divergence**: Check if the local branch is behind the remote
3. **Rebase if Needed**: If behind, rebase local commits on top of remote changes
4. **Handle Conflicts**: If rebase fails due to conflicts, abort and provide clear instructions for manual resolution

#### 3.4 Push

1. Push to `origin/${BRANCH}`
2. If push fails after successful rebase, report the error and suggest using `--force-with-lease`

### 4. Build Detection

After pushing, wait for Jenkins to start a new build:

#### 4.1 Baseline

1. Record the current "last build number" for the job before the push
2. If no builds exist yet, use 0 as the baseline

#### 4.2 Polling for New Build

1. **Poll Interval**: Check every 5 seconds (configurable)
2. **Maximum Wait**: 2 minutes (120 seconds) for a new build to start
3. **Detection**: A new build is detected when the job's last build number exceeds the baseline
4. **Queue Status**: While waiting, check if the job is queued and inform the user

#### 4.3 Timeout Handling

If no new build starts within the timeout period, provide diagnostic information:
- Suggest checking webhook/polling configuration
- Suggest verifying SCM settings match the pushed branch
- Provide the job URL for manual inspection

### 5. Build Monitoring

Once a build starts, monitor its progress until completion:

#### 5.1 Progress Tracking

1. **Poll Interval**: Check every 5 seconds
2. **Maximum Duration**: 30 minutes (1800 seconds)
3. **Stage Information**: If available (Pipeline jobs), display the currently executing stage name
4. **Progress Updates**: Periodically log elapsed time (every 30 seconds)

#### 5.2 Completion Detection

A build is complete when:
- The `building` field in the build API response is `false`
- The `result` field contains the final status (SUCCESS, FAILURE, UNSTABLE, ABORTED, etc.)

### 6. Result Handling

#### 6.1 On Success

Display:
- Clear success indicator
- Build number
- Direct URL to the build

#### 6.2 On Failure

Perform failure analysis:

1. **Identify Failed Stage**: Query the Pipeline workflow API to find which stage failed
2. **Check for Downstream Builds**: Determine if the failure originated from a triggered downstream job
3. **Extract Relevant Logs**: Display the most relevant log output for diagnosis

### 7. Failure Analysis

#### 7.1 Stage Identification

For Pipeline jobs, use the workflow API (`/job/${job-name}/${build-number}/wfapi/describe`) to:
- List all stages and their statuses
- Find the first stage with status `FAILED` or `UNSTABLE`

#### 7.2 Downstream Build Detection

Check if the failed stage triggered a downstream build:
- Search the console output for patterns like `Starting building: <job-name> #<build-number>`
- If found, the failure analysis should focus on the downstream build

#### 7.3 Log Extraction Priority

When displaying failure information:

1. **Downstream Build Logs**: If a downstream build failed, fetch and display its console output
   - Search for error patterns (ERROR, Exception, FAILURE, failed)
   - If no patterns found, show the last 100 lines
   
2. **Stage-Specific Logs**: If no downstream build, extract logs for the failed stage
   - Parse console output using Pipeline markers: `[Pipeline] { (StageName)` ... `[Pipeline] }`
   
3. **Full Console Output**: If stage cannot be identified (e.g., Jenkinsfile syntax error):
   - Display the complete console output
   
4. **Fallback**: If log extraction fails, show the last 100 lines of output

---

## Jenkins API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `/api/json` | Verify Jenkins connectivity |
| `/job/${job}/api/json` | Verify job exists, get job information |
| `/job/${job}/lastBuild/api/json` | Get the most recent build number |
| `/job/${job}/${build}/api/json` | Get build status and metadata |
| `/job/${job}/${build}/wfapi/describe` | Get Pipeline stage information |
| `/job/${job}/${build}/consoleText` | Get build console output |
| `/queue/api/json` | Check if job is queued |

All API calls must include HTTP Basic Authentication using `JENKINS_USER_ID` and `JENKINS_API_TOKEN`.

---

## User Feedback Requirements

### Logging Levels

The tool must provide timestamped, visually distinct log messages:

| Level | Purpose | Visual Indicator |
|-------|---------|------------------|
| INFO | General status updates | Blue indicator |
| SUCCESS | Successful operations | Green checkmark |
| WARNING | Non-fatal issues | Yellow warning |
| ERROR | Fatal errors | Red X, output to stderr |

### Required User Feedback Points

1. **Startup**: Display configuration summary (Jenkins URL, job name, branch, repository)
2. **Git Operations**: Report each step (checking changes, committing, rebasing, pushing)
3. **Build Detection**: Report when build starts with build number
4. **Build Progress**: Show current stage name and periodic elapsed time updates
5. **Completion**: Clear banner indicating SUCCESS or FAILURE
6. **Failure Details**: Stage name, relevant logs, and URL for full console output

---

## Error Handling

### Recoverable Errors

These should be retried or handled gracefully:

- Transient API failures during polling (retry up to 5 consecutive failures)
- Missing stage information in workflow API (fall back to console parsing)
- Failed log extraction (show alternative/fallback output)

### Fatal Errors

These should terminate execution immediately with clear error messages:

- Missing required environment variables
- Invalid JENKINS_URL format
- Not in a git repository
- No origin remote configured
- Jenkins authentication failure (401/403)
- Jenkins job not found (404)
- Git commit failure
- Git push failure (after rebase conflict handling)
- Build detection timeout (2 minutes)
- Build execution timeout (30 minutes)

---

## Configuration Constants

| Constant | Default Value | Description |
|----------|---------------|-------------|
| BRANCH | `main` | Git branch to push to |
| POLL_INTERVAL | 5 seconds | Time between API polling requests |
| MAX_BUILD_TIME | 1800 seconds (30 min) | Maximum time to wait for build completion |
| BUILD_START_TIMEOUT | 120 seconds (2 min) | Maximum time to wait for build to start |
| MAX_CONSECUTIVE_FAILURES | 5 | API failures before aborting |

---

## Interrupt Handling

When the user interrupts execution (e.g., Ctrl+C):

1. Display a warning that the script was interrupted
2. Inform the user that the Jenkins build may still be running
3. Provide the job URL for manual monitoring
4. Exit with code 130

---

## Non-Functional Requirements

### Performance

- Minimize API calls during polling (avoid redundant requests)
- Parse only necessary fields from JSON responses

### Reliability

- Handle network interruptions gracefully during polling
- Provide useful diagnostics when operations fail

### Usability

- All error messages must be actionable (tell the user what to do)
- Provide URLs for manual inspection when automated analysis fails
- Support terminal color codes for improved readability
