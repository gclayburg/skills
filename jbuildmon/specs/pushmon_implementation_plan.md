# Jenkins Build Monitor - Implementation Plan

This document outlines the implementation tasks for the Jenkins Build Monitor tool as specified in [jenkins-build-monitor-spec.md](jenkins-build-monitor-spec.md).

**Implementation Status: COMPLETE** - All phases implemented in `pushmon.sh`

---

## Bug Fixes

### 2026-01-26: Fixed check_for_changes output capture bug

**Issue**: The `check_for_changes` function used `log_info` calls (which output to stdout) and then echoed the result. When main captured this with `has_staged=$(check_for_changes)`, the variable contained all log output plus the "true"/"false" string, causing the comparison `[[ "$has_staged" == "true" ]]` to always fail. This meant the script never committed staged changes.

**Fix**: Changed `check_for_changes` to use a global variable `HAS_STAGED_CHANGES` instead of echoing the result. Main now calls `check_for_changes` without capturing output and checks the global variable directly.

### 2026-01-26: Improved downstream build detection for parallel stages

**Issue**: The `detect_downstream_build` function used `tail -1` to only find the LAST downstream build triggered. When parallel stages trigger multiple downstream builds and one fails (but not the last one triggered), the failure analysis would focus on the wrong build, missing the actual failure.

**Fix**: Replaced `detect_downstream_build` with three new functions:
- `detect_all_downstream_builds`: Finds ALL downstream builds from console output
- `check_build_failed`: Checks if a specific build failed via Jenkins API
- `find_failed_downstream_build`: Iterates through all downstream builds and returns the one that actually failed

This ensures that when parallel stages are used, the failure analysis correctly identifies and displays logs from the downstream build that actually failed, rather than just the last one triggered.

---

## Phase 1: Project Setup

- [x] Create project directory structure
- [x] Initialize the script file with shebang and basic structure
- [x] Define configuration constants (see spec: Configuration Constants section)
  - `BRANCH=main`
  - `POLL_INTERVAL=5`
  - `MAX_BUILD_TIME=1800`
  - `BUILD_START_TIMEOUT=120`
  - `MAX_CONSECUTIVE_FAILURES=5`

---

## Phase 2: Logging and Output Functions

- [x] Implement timestamped logging function with color support (see spec: User Feedback Requirements - Logging Levels)
  - INFO level (blue indicator)
  - SUCCESS level (green checkmark)
  - WARNING level (yellow warning)
  - ERROR level (red X, output to stderr)
- [x] Implement cleanup/interrupt handler for Ctrl+C (see spec: Interrupt Handling)
  - Display warning that script was interrupted
  - Inform user that Jenkins build may still be running
  - Provide job URL for manual monitoring
  - Exit with code 130

---

## Phase 3: Startup Validation

- [x] Implement argument validation (see spec: Section 1 - Startup Validation)
  - Verify both `job-name` and `commit-message` are provided
  - Display usage message if arguments missing
- [x] Implement environment variable validation (see spec: Prerequisites - Required Environment Variables)
  - Check `JENKINS_URL` is set and non-empty
  - Check `JENKINS_USER_ID` is set and non-empty
  - Check `JENKINS_API_TOKEN` is set and non-empty
- [x] Implement `JENKINS_URL` format validation (see spec: Section 1.3)
  - Must begin with `http://` or `https://`
  - Normalize trailing slashes (remove them)
- [x] Implement git repository validation (see spec: Section 1.4-1.5)
  - Verify current directory is a git repository
  - Verify `origin` remote is configured
- [x] Implement JSON parser availability check (see spec: Section 1.6)
  - Verify `jq` is available in PATH

---

## Phase 4: Jenkins Connectivity Verification

- [x] Implement Jenkins connection test (see spec: Section 2.1)
  - Make authenticated request to `${JENKINS_URL}/api/json`
  - Use HTTP Basic Authentication with `JENKINS_USER_ID` and `JENKINS_API_TOKEN`
- [x] Implement authentication error handling (see spec: Section 2.2)
  - Detect and report 401 (bad credentials)
  - Detect and report 403 (permission denied)
- [x] Implement job existence verification (see spec: Section 2.3)
  - Request `${JENKINS_URL}/job/${job-name}/api/json`
  - Handle 404 (job not found)

---

## Phase 5: Git Operations

- [x] Implement change detection (see spec: Section 3.1)
  - Check for staged (uncommitted) changes
  - Check for unpushed commits to origin
  - Fail with error if neither exists
- [x] Implement commit operation (see spec: Section 3.2)
  - Create commit with provided message
  - Record and log commit hash
- [x] Implement remote sync (see spec: Section 3.3)
  - Fetch latest state from `origin/${BRANCH}`
  - Detect if local branch is behind remote
  - Rebase local commits if behind
  - Handle rebase conflicts: abort and provide manual resolution instructions
- [x] Implement push operation (see spec: Section 3.4)
  - Push to `origin/${BRANCH}`
  - If push fails after rebase, suggest `--force-with-lease`

---

## Phase 6: Build Detection

- [x] Implement baseline recording (see spec: Section 4.1)
  - Query `${JENKINS_URL}/job/${job}/lastBuild/api/json` for current build number
  - Use 0 as baseline if no builds exist
- [x] Implement build polling loop (see spec: Section 4.2)
  - Poll every 5 seconds (configurable via `POLL_INTERVAL`)
  - Maximum wait of 120 seconds (`BUILD_START_TIMEOUT`)
  - Detect new build when last build number exceeds baseline
- [x] Implement queue status check (see spec: Section 4.2.4)
  - Query `/queue/api/json` while waiting
  - Inform user if job is queued
- [x] Implement build detection timeout handling (see spec: Section 4.3)
  - Suggest checking webhook/polling configuration
  - Suggest verifying SCM settings match pushed branch
  - Provide job URL for manual inspection

---

## Phase 7: Build Monitoring

- [x] Implement build progress polling loop (see spec: Section 5.1)
  - Poll every 5 seconds (`POLL_INTERVAL`)
  - Maximum duration of 1800 seconds (`MAX_BUILD_TIME`)
  - Log elapsed time every 30 seconds
- [x] Implement stage information display (see spec: Section 5.1.3)
  - Query `/job/${job}/${build}/wfapi/describe` for Pipeline jobs
  - Display currently executing stage name
- [x] Implement completion detection (see spec: Section 5.2)
  - Check `building` field is `false`
  - Read `result` field for final status (SUCCESS, FAILURE, UNSTABLE, ABORTED)
- [x] Implement transient API failure handling (see spec: Error Handling - Recoverable Errors)
  - Retry up to `MAX_CONSECUTIVE_FAILURES` (5) consecutive failures
  - Continue polling after transient failures

---

## Phase 8: Result Handling

- [x] Implement success handling (see spec: Section 6.1)
  - Display clear success indicator/banner
  - Show build number
  - Provide direct URL to the build
- [x] Implement failure handling trigger (see spec: Section 6.2)
  - Detect FAILURE, UNSTABLE, ABORTED results
  - Trigger failure analysis workflow

---

## Phase 9: Failure Analysis

- [x] Implement stage identification (see spec: Section 7.1)
  - Query `/job/${job}/${build}/wfapi/describe`
  - List all stages and their statuses
  - Find first stage with status `FAILED` or `UNSTABLE`
- [x] Implement downstream build detection (see spec: Section 7.2)
  - Fetch console output from `/job/${job}/${build}/consoleText`
  - Search for pattern: `Starting building: <job-name> #<build-number>`
  - If found, redirect analysis to downstream build
- [x] Implement log extraction - downstream builds (see spec: Section 7.3.1)
  - Fetch downstream build's console output
  - Search for error patterns (ERROR, Exception, FAILURE, failed)
  - If no patterns found, show last 100 lines
- [x] Implement log extraction - stage-specific (see spec: Section 7.3.2)
  - Parse console output using Pipeline markers
  - Extract content between `[Pipeline] { (StageName)` and `[Pipeline] }`
- [x] Implement log extraction - full console (see spec: Section 7.3.3)
  - Display complete console output for Jenkinsfile syntax errors
- [x] Implement log extraction - fallback (see spec: Section 7.3.4)
  - Show last 100 lines if other extraction methods fail
- [x] Display failure summary
  - Show failed stage name
  - Show relevant log excerpt
  - Provide URL for full console output

---

## Phase 10: Integration and Polish

- [x] Implement main execution flow connecting all phases
- [x] Add startup configuration summary display (see spec: User Feedback Requirements)
  - Jenkins URL
  - Job name
  - Branch
  - Repository
- [x] Verify all exit codes are correct (see spec: Command Interface - Exit Codes)
  - 0 for success
  - 1 for failure/error
  - 130 for user interrupt
- [x] Test error messages are actionable (see spec: Non-Functional Requirements - Usability)
- [x] Verify all required user feedback points are implemented (see spec: User Feedback Requirements - Required User Feedback Points)

---

## API Endpoints Reference

For implementation reference, these Jenkins API endpoints are used (see spec: Jenkins API Endpoints Used):

| Endpoint | Purpose |
|----------|---------|
| `/api/json` | Verify Jenkins connectivity |
| `/job/${job}/api/json` | Verify job exists, get job information |
| `/job/${job}/lastBuild/api/json` | Get the most recent build number |
| `/job/${job}/${build}/api/json` | Get build status and metadata |
| `/job/${job}/${build}/wfapi/describe` | Get Pipeline stage information |
| `/job/${job}/${build}/consoleText` | Get build console output |
| `/queue/api/json` | Check if job is queued |
