# Checkbuild - Jenkins Build Status Checker

## Overview

Checkbuild is a CLI tool and Claude skill that queries the Jenkins build server to report the current status of the last build for the job associated with the current git repository. It correlates the triggering commit with local git history to determine if the build was triggered by a known change or by someone else.

## Purpose

This tool answers the question: "What is the current state of the CI build, and is it building my changes?" It provides quick visibility into:
- Whether the last build succeeded or failed
- Who/what triggered the build (automated push vs manual)
- Whether the triggering commit is in your local history
- Detailed failure information when builds fail

---

## Prerequisites

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `JENKINS_URL` | Base URL of the Jenkins server (e.g., `http://jenkins.example.com:8080`) |
| `JENKINS_USER_ID` | Jenkins username for API authentication |
| `JENKINS_API_TOKEN` | Jenkins API token for authentication |

### External Dependencies

- **jq**: JSON parser for processing API responses
- **curl**: HTTP client for Jenkins API requests
- **git**: Must be run from within a valid git repository

---

## Command Interface

### Usage

```
checkbuild [--json]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--json` | No | Output results in JSON format for machine parsing |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Last build was successful |
| 1 | Last build failed, or an error occurred during execution |
| 2 | Build is currently in progress |

---

## Claude Skill Integration

### Skill Name

`/checkbuild`

### Invocation

The skill takes no arguments. When invoked, it:
1. Determines the job name from the current repository
2. Queries Jenkins for the last build status
3. Reports the status in human-readable format

### Supported Platforms

- Claude Code (CLI)
- Cursor
- Other Claude-compatible IDEs

---

## Functional Requirements

### 1. Startup Validation

Before performing any operations, the tool must validate:

1. **Environment Variables**: `JENKINS_URL` must be set; if not, exit with usage message
2. **Git Repository**: Must be run from within a valid git repository; if not, exit with usage message
3. **Dependencies**: `jq` and `curl` must be available
4. **Job Name**: Must be discoverable via AGENTS.md or git origin (see Section 2)

### 2. Job Name Discovery

The tool discovers the Jenkins job name using the following priority:

#### 2.1 AGENTS.md Lookup (Primary)

1. Find the root directory of the current git repository
2. Look for `AGENTS.md` file in the repository root
3. Search for the pattern `JOB_NAME=<jobname>` using flexible matching:
   - Match: `JOB_NAME=myjob`
   - Match: `JOB_NAME = myjob`
   - Match: `- JOB_NAME=myjob`
   - Match: `the job is JOB_NAME=myjob`
   - The job name is the non-whitespace string immediately following `JOB_NAME` and optional whitespace and `=`
4. Use the first occurrence found

#### 2.2 Git Origin Fallback (Secondary)

If AGENTS.md lookup fails:

1. Get the git origin URL: `git remote get-url origin`
2. Extract the repository name from various URL formats:
   - `git@github.com:org/my-project.git` → `my-project`
   - `https://github.com/org/my-project.git` → `my-project`
   - `ssh://git@server:2233/home/git/ralph1.git` → `ralph1`
   - `git@server:path/to/repo.git` → `repo`
3. Strip the `.git` suffix if present

### 3. Jenkins API Queries

#### 3.1 Get Last Build Information

Query: `GET /job/${JOB_NAME}/lastBuild/api/json`

Extract:
- `number`: Build number
- `result`: Build result (SUCCESS, FAILURE, UNSTABLE, ABORTED, null if building)
- `building`: Boolean indicating if build is in progress
- `timestamp`: Build start time (epoch milliseconds)
- `duration`: Build duration in milliseconds (0 if still building)
- `url`: Direct URL to the build

#### 3.2 Get Build Console Output

Query: `GET /job/${JOB_NAME}/${BUILD_NUMBER}/consoleText`

Used to extract:
- Trigger information (who started the build)
- Commit SHA that triggered the build
- Error logs on failure

### 4. Trigger Detection

#### 4.1 Automated vs Manual Detection

Parse the console output for the trigger line:

- **Automated (git push)**: `Started by user buildtriggerdude`
  - This indicates the build was triggered by the post-receive hook
- **Manual**: `Started by user <any-other-username>`
  - Any username other than `buildtriggerdude` indicates manual trigger

#### 4.2 Triggering Commit Extraction

Extract the commit SHA from the build. Methods (in priority order):

1. **From build API**: Check `actions` array for `lastBuiltRevision.SHA1` in GitSCM data
2. **From console output**: Parse for patterns like:
   - `Checking out Revision <sha>`
   - `Commit message: "<message>"`
   - `> git checkout -f <sha>`

Also extract the commit message associated with the triggering commit.

### 5. Git Commit Correlation

Once the triggering commit SHA is identified:

#### 5.1 Local History Check

```bash
git cat-file -t <sha>
```

If this returns `commit`, the commit exists in local history.

#### 5.2 Reachability Check

```bash
git merge-base --is-ancestor <sha> HEAD
```

If exit code is 0, the commit is an ancestor of the current HEAD (i.e., it's "our" commit or we have it).

#### 5.3 Correlation Status

Report one of:
- **"Your commit"**: SHA matches current HEAD
- **"In your history"**: SHA is reachable from HEAD but not HEAD itself
- **"Not in your history"**: SHA exists locally but not reachable from HEAD
- **"Unknown commit"**: SHA not found in local repository

### 6. Failure Analysis

When the last build has failed (`result` is FAILURE, UNSTABLE, or ABORTED):

#### 6.1 Failed Job Tree Detection

1. Parse console output for downstream build triggers: `Starting building: <job-name> #<build-number>`
2. For each downstream build, check its status
3. Recursively check for nested downstream builds
4. Collect the names of all failed jobs in the dependency tree

#### 6.2 Error Log Extraction

Follow the same logic as `pushmon.sh`:

1. If downstream build failed, extract error lines from the deepest failed downstream build
2. If no downstream builds, identify the failed stage and extract stage-specific logs
3. Fall back to extracting error patterns (ERROR, Exception, FAILURE, failed, FATAL)
4. Final fallback: show last 100 lines of console output

#### 6.3 Build Metadata Display

On failure, display:
- User who started the build
- Jenkins agent that ran the build
- Pipeline source (Jenkinsfile location)

### 7. Output Formats

#### 7.1 Human-Readable Output (Default)

```
╔════════════════════════════════════════╗
║         BUILD STATUS: SUCCESS          ║
╚════════════════════════════════════════╝

Job:        my-project
Build:      #142
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     abc1234 - "Fix login bug"
            ✓ In your history (reachable from HEAD)
Duration:   2m 34s
Completed:  2024-01-15 14:32:05

Console:    https://jenkins.example.com/job/my-project/142/console
```

For failures, additionally show:

```
╔════════════════════════════════════════╗
║          BUILD STATUS: FAILURE         ║
╚════════════════════════════════════════╝

Job:        my-project
Build:      #143
Status:     FAILURE
Trigger:    Manual (started by jsmith)
Commit:     def5678 - "Add new feature"
            ✗ Not in your history
Duration:   1m 12s
Completed:  2024-01-15 15:10:22

=== Build Info ===
  Started by:  jsmith
  Agent:       build-agent-01
  Pipeline:    Jenkinsfile from git ssh://git@server/repo.git
==================

=== Failed Jobs ===
  → my-project (stage: Build)
    → my-project-tests
      → my-project-integration-tests  ← FAILED
====================

=== Error Logs ===
[ERROR] Test failed: testUserLogin
java.lang.AssertionError: expected:<200> but was:<401>
    at org.junit.Assert.fail(Assert.java:88)
...
==================

Console:    https://jenkins.example.com/job/my-project/143/console
```

For in-progress builds:

```
╔════════════════════════════════════════╗
║       BUILD STATUS: IN PROGRESS        ║
╚════════════════════════════════════════╝

Job:        my-project
Build:      #144
Status:     BUILDING
Stage:      Running Tests
Trigger:    Automated (git push)
Commit:     789abcd - "Update dependencies"
            ✓ Your commit (HEAD)
Started:    2024-01-15 15:45:00
Elapsed:    3m 21s

Console:    https://jenkins.example.com/job/my-project/144/console
```

#### 7.2 JSON Output (`--json` flag)

```json
{
  "job": "my-project",
  "build": {
    "number": 142,
    "status": "SUCCESS",
    "building": false,
    "duration_seconds": 154,
    "timestamp": "2024-01-15T14:32:05Z",
    "url": "https://jenkins.example.com/job/my-project/142/"
  },
  "trigger": {
    "type": "automated",
    "user": "buildtriggerdude"
  },
  "commit": {
    "sha": "abc1234def5678",
    "message": "Fix login bug",
    "in_local_history": true,
    "reachable_from_head": true,
    "is_head": false
  },
  "console_url": "https://jenkins.example.com/job/my-project/142/console"
}
```

For failures, add:

```json
{
  ...
  "failure": {
    "failed_jobs": [
      "my-project",
      "my-project-tests",
      "my-project-integration-tests"
    ],
    "root_cause_job": "my-project-integration-tests",
    "failed_stage": "Integration Tests",
    "error_summary": "Test failed: testUserLogin - expected:<200> but was:<401>"
  },
  "build_info": {
    "started_by": "jsmith",
    "agent": "build-agent-01",
    "pipeline": "Jenkinsfile from git ssh://git@server/repo.git"
  }
}
```

---

## Shared Library: jenkins-common.sh

### Location

`jbuildmon/lib/jenkins-common.sh`

### Purpose

Provide common functionality shared between `pushmon.sh` and `checkbuild.sh` to avoid code duplication.

### Exported Functions

#### Color Support

| Function/Variable | Description |
|-------------------|-------------|
| `COLOR_RESET`, `COLOR_BLUE`, etc. | Color escape codes (empty if not a TTY) |
| Color detection logic | Auto-detect terminal color support |

#### Logging Functions

| Function | Description |
|----------|-------------|
| `_timestamp` | Returns current time in HH:MM:SS format |
| `log_info` | Blue info messages |
| `log_success` | Green success messages with checkmark |
| `log_warning` | Yellow warning messages |
| `log_error` | Red error messages to stderr |
| `log_banner` | Large status banners (success/failure) |

#### Validation Functions

| Function | Description |
|----------|-------------|
| `validate_environment` | Check required env vars (JENKINS_URL, JENKINS_USER_ID, JENKINS_API_TOKEN) |
| `validate_dependencies` | Check for jq and curl |
| `validate_git_repository` | Verify we're in a git repo with origin remote |

#### Jenkins API Functions

| Function | Description |
|----------|-------------|
| `jenkins_api` | Make authenticated GET request, return body |
| `jenkins_api_with_status` | Make authenticated GET request, return body + HTTP status |
| `verify_jenkins_connection` | Test connectivity to Jenkins |
| `verify_job_exists` | Verify job exists, set JOB_URL global |

#### Build Information Functions

| Function | Description |
|----------|-------------|
| `get_build_info` | Get build JSON from API |
| `get_console_output` | Get console text for a build |
| `get_current_stage` | Get currently executing stage name |
| `get_failed_stage` | Get first failed stage name |
| `get_last_build_number` | Get the last build number for a job |

#### Failure Analysis Functions

| Function | Description |
|----------|-------------|
| `extract_error_lines` | Extract error patterns from console output |
| `extract_stage_logs` | Extract logs for a specific pipeline stage |
| `display_build_metadata` | Show user, agent, pipeline info |
| `detect_all_downstream_builds` | Find all triggered downstream builds |
| `find_failed_downstream_build` | Find the failed downstream build |
| `check_build_failed` | Check if a build result indicates failure |
| `analyze_failure` | Full failure analysis orchestration |

### Usage Pattern

Scripts source the library from a relative path:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/jenkins-common.sh"
```

### Global Variables Set by Library

| Variable | Description |
|----------|-------------|
| `JOB_URL` | Full URL to the job (set by `verify_job_exists`) |
| `BUILD_NUMBER` | Current build number being processed |

---

## Error Handling

### Fatal Errors (Exit 1)

- `JENKINS_URL` not set
- Not in a git repository
- Job name cannot be determined
- Jenkins authentication failure (401/403)
- Jenkins job not found (404)
- Required dependencies missing (jq, curl)

### Graceful Handling

- Transient API failures: Retry up to 3 times
- Missing workflow API data: Fall back to console parsing
- Cannot extract commit SHA: Report as "unknown"
- Cannot determine trigger type: Report as "unknown"

---

## Configuration

### Environment Variable Overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `CHECKBUILD_TRIGGER_USER` | `buildtriggerdude` | Username that indicates automated trigger |

---

## File Structure

After implementation:

```
jbuildmon/
├── pushmon.sh              # Existing push + monitor script
├── checkbuild.sh           # New status checker script
├── lib/
│   └── jenkins-common.sh   # Shared library
└── specs/
    ├── jenkins-build-monitor-spec.md
    ├── pushmon_implementation_plan.md
    └── checkbuild-spec.md  # This document
```

---

## Implementation Notes

### Phase 1: Create Shared Library

1. Create `jbuildmon/lib/jenkins-common.sh`
2. Extract shared functions from `pushmon.sh`
3. Verify `pushmon.sh` still works after sourcing library (migration deferred)

### Phase 2: Implement checkbuild.sh

1. Implement job name discovery (AGENTS.md parsing, git origin fallback)
2. Implement trigger detection and commit extraction
3. Implement git commit correlation
4. Implement human-readable output
5. Implement JSON output mode
6. Implement failure analysis (reuse shared library functions)

### Phase 3: Claude Skill Integration

1. Create skill definition file for `/checkbuild`
2. Test in Claude Code and Cursor
3. Document usage in AGENTS.md

---

## Testing Checklist

- [ ] Job discovery from AGENTS.md with various formats
- [ ] Job discovery fallback to git origin
- [ ] Successful build status display
- [ ] Failed build with downstream job tree
- [ ] In-progress build display
- [ ] Manual vs automated trigger detection
- [ ] Commit correlation: HEAD match
- [ ] Commit correlation: ancestor commit
- [ ] Commit correlation: unknown commit
- [ ] JSON output format validation
- [ ] Missing JENKINS_URL error message
- [ ] Not in git repo error message
- [ ] Job not found error handling
