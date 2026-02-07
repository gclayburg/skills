# Unified Build Monitoring Output
Date: 2026-02-06

## Overview

Unify the output format for all build monitoring commands (`buildgit push`, `buildgit build`, `buildgit status -f`) to provide consistent, informative feedback when a build is in progress.

## Problem Statement

Currently, `buildgit push` and `buildgit status -f` display different information when monitoring a build in progress:

- `buildgit push` shows minimal stage information (only the current stage)
- `buildgit status -f` shows comprehensive build metadata and all completed stages

This inconsistency makes it harder for users to understand build progress depending on which command they used.

## Scope

This specification applies to all build monitoring scenarios:
- `buildgit push` (monitors build after push)
- `buildgit build` (triggers and monitors build)
- `buildgit status -f/--follow` (continuous monitoring)

## Unified Output Format

### 1. Verbose-Only Messages

The following connection verification messages should only appear when `--verbose` is set:

```
[HH:MM:SS] ℹ Verifying Jenkins connectivity...
[HH:MM:SS] ✓ Connected to Jenkins
[HH:MM:SS] ℹ Verifying job 'ralph1' exists...
[HH:MM:SS] ✓ Job 'ralph1' found
```

In default (non-verbose) mode, these messages are suppressed. Monitoring begins silently after successful verification.

### 2. Build Header (Displayed Immediately)

When monitoring begins, display the complete build header before any stage output:

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #80
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     b372452 - "test123"
            ✓ Your commit (HEAD)
Started:    2026-02-06 14:19:44
Elapsed:    1m 17s (so far)

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent2paton
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://jenkins.example.com:8080/job/ralph1/80/console
```

#### Field Descriptions

| Field | Description |
|-------|-------------|
| Job | Jenkins job name |
| Build | Build number with # prefix |
| Status | Current build status (BUILDING while in progress) |
| Trigger | How the build was triggered (see Trigger Types below) |
| Commit | Short hash and commit message of the build |
| ✓ Your commit (HEAD) | Indicator when build commit matches local HEAD |
| Started | Timestamp when build started |
| Elapsed | Time since build started |
| Started by | User or trigger that initiated the build |
| Agent | Jenkins agent/node executing the build |
| Pipeline | Jenkinsfile location and SCM source |
| Console | Direct URL to build console output |

#### Trigger Types

| Trigger | Description |
|---------|-------------|
| Automated (git push) | Triggered by SCM webhook/polling |
| Manual | Triggered by "Build Now" in Jenkins UI |
| Upstream | Triggered by another Jenkins job |

#### Elapsed Time Display

- For `buildgit push` and `buildgit build`: Show elapsed time without suffix (build started moments ago)
- For `buildgit status -f`: Show elapsed time with "(so far)" suffix (build may have been running before monitoring started)

### 3. Stage Output

After the build header, display stage information:

#### Initial Display

Show all stages that have already completed when monitoring begins:

```
[14:21:02] ℹ   Stage: Declarative: Checkout SCM (<1s)
[14:21:02] ℹ   Stage: Declarative: Agent Setup (<1s)
[14:21:02] ℹ   Stage: Initialize Submodules (10s)
[14:21:02] ℹ   Stage: Build (<1s)
```

#### Streaming Updates

As monitoring continues, print each stage when it completes (transitions from IN_PROGRESS to SUCCESS/FAILED/UNSTABLE):

```
[14:23:04] ℹ   Stage: Unit Tests (2m 2s)
[14:23:05] ℹ   Stage: Deploy (<1s)
```

#### Stage Format

Follow the format defined in `full-stage-print-spec.md`:
- Completed stages show duration: `Stage: <name> (<duration>)`
- Duration format: `<1s`, `15s`, `2m 4s`, `1h 5m 30s`
- Color coding: SUCCESS (green), FAILED (red), UNSTABLE (yellow)
- In verbose mode only: Show `(running)` for in-progress stage when it first starts

### 4. Build Completion

When the build finishes, display:

1. Any remaining stage completions
2. Test failure details (if applicable, per `test-failure-display-spec.md`)
3. Final status line matching Jenkins console format:

```
Finished: SUCCESS
```

#### Final Status Line Colors

| Status | Color |
|--------|-------|
| SUCCESS | Green |
| UNSTABLE | Yellow |
| FAILURE | Red |
| ABORTED | Gray/dim |

### 5. Command-Specific Behavior

#### `buildgit push`

1. Display git commit output (if committing)
2. Display git push output
3. If push succeeds, begin build monitoring with unified format
4. Git output appears before the "BUILD IN PROGRESS" banner

Example flow:
```
[main b372452] test123
 1 file changed, 1 insertion(+)
To ssh://scranton2:2233/home/git/ralph1.git
   1905bd5..b372452  main -> main

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝
...
```

#### `buildgit build`

1. Trigger build
2. Begin build monitoring with unified format immediately

#### `buildgit status -f`

1. Display git status output
2. Begin build monitoring with unified format
3. Show "(so far)" suffix on Elapsed time
4. After build completes, wait for next build and repeat

## Implementation Requirements

### Functions to Modify

1. **Suppress verbose messages**: Update connection verification to check verbose flag
2. **Build header display**: Create/update function to display unified header format
3. **Console URL placement**: Move console URL to appear after Build Info section
4. **Stage streaming**: Ensure all commands use consistent stage tracking (per `full-stage-print-spec.md`)
5. **Final status line**: Add "Finished: <STATUS>" output with appropriate coloring

### Affected Code Paths

- `buildgit` push monitoring (`_push_monitor_build`)
- `buildgit` build monitoring (`_build_monitor`)
- `buildgit` status follow mode (`_follow_monitor_build`)
- Display functions in `lib/jenkins-common.sh`

### Backward Compatibility

- Command-line interface remains unchanged
- `--verbose` flag gains additional output (connection messages)
- Visual output format changes are enhancements, not breaking changes

## Complete Example Output

### buildgit push (successful build)

```
[main 59cf17c] test123
 1 file changed, 1 insertion(+)
To ssh://scranton2:2233/home/git/ralph1.git
   b372452..59cf17c  main -> main

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #81
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     59cf17c - "test123"
            ✓ Your commit (HEAD)
Started:    2026-02-06 14:25:00
Elapsed:    5s

=== Build Info ===
  Started by:  git-webhook
  Agent:       agent2paton
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/81/console

[14:25:05] ℹ   Stage: Declarative: Checkout SCM (<1s)
[14:25:06] ℹ   Stage: Declarative: Agent Setup (<1s)
[14:25:16] ℹ   Stage: Initialize Submodules (10s)
[14:25:31] ℹ   Stage: Build (15s)
[14:27:33] ℹ   Stage: Unit Tests (2m 2s)
[14:27:34] ℹ   Stage: Deploy (<1s)

Finished: SUCCESS
```

### buildgit push (failed build)

```
[main abc1234] add new feature
 3 files changed, 45 insertions(+), 12 deletions(-)
To ssh://scranton2:2233/home/git/ralph1.git
   59cf17c..abc1234  main -> main

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #82
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     abc1234 - "add new feature"
            ✓ Your commit (HEAD)
Started:    2026-02-06 14:30:00
Elapsed:    3s

=== Build Info ===
  Started by:  git-webhook
  Agent:       agent2paton
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/82/console

[14:30:03] ℹ   Stage: Declarative: Checkout SCM (<1s)
[14:30:04] ℹ   Stage: Declarative: Agent Setup (<1s)
[14:30:14] ℹ   Stage: Initialize Submodules (10s)
[14:30:29] ℹ   Stage: Build (15s)
[14:32:31] ℹ   Stage: Unit Tests (2m 2s)    ← FAILED

=== Test Results ===
  Total: 33 | Passed: 32 | Failed: 1 | Skipped: 0

  FAILED TESTS:
  ✗ test_helper.bats::TEST_TEMP_DIR is unique per test run
    Error: [[: command not found
    (in test file test/test_helper.bats, line 74)
====================

Finished: UNSTABLE
```

## Testing Requirements

### Unit Tests

- Verify verbose messages are suppressed in default mode
- Verify verbose messages appear with `--verbose` flag
- Verify build header format matches specification
- Verify Console URL appears after Build Info section
- Verify "Finished:" line has correct color for each status

### Integration Tests

- `buildgit push` shows git output, then unified monitoring format
- `buildgit build` shows unified monitoring format
- `buildgit status -f` shows "(so far)" on elapsed time
- All commands show identical header and stage format

### Manual Testing Checklist

- [ ] `buildgit push` suppresses connection messages by default
- [ ] `buildgit --verbose push` shows connection messages
- [ ] Build header appears before any stage output
- [ ] Console URL appears after Build Info section
- [ ] Already-completed stages shown immediately
- [ ] New stages stream as they complete
- [ ] "Finished: SUCCESS" appears in green
- [ ] "Finished: FAILURE" appears in red
- [ ] "Finished: UNSTABLE" appears in yellow

## Related Specifications

- `buildgit-spec.md` - Base command specification
- `full-stage-print-spec.md` - Stage display format
- `test-failure-display-spec.md` - Test failure output
- `bug2026-02-04-running-stage-spam-spec.md` - Running stage display fix
