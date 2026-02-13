# Fix Build Monitoring Header: Missing Fields, Elapsed/Duration, and Commit

- Date: 2026-02-13T10:24:51-07:00
- References: specs/todo/bug-build-push.md
- Supersedes: unify-follow-log-spec.md (partially — removes Elapsed field from header, adds Duration line, changes deferred header behavior)

## Problem Statement

The build monitoring output (`buildgit push`, `buildgit build`, `buildgit status -f`) has several inconsistencies and missing information:

1. **Missing Agent/Pipeline in `buildgit build`**: The `=== Build Info ===` section shows only `Started by` but omits `Agent` and `Pipeline`, because the console output hasn't been written by Jenkins yet when the header is first printed.

2. **Missing Agent/Pipeline in `buildgit status` (snapshot)**: The snapshot code path does not pass `console_output` to the display function at all, so Build Info is always incomplete.

3. **Commit shows "unknown" for `buildgit build`**: The commit extraction relies on `lastBuiltRevision` or console output parsing, neither of which is available immediately after triggering a build.

4. **Elapsed field is misleading**: The `Elapsed` line in the header is meaningless for `push` and `build` (the build just started). The only scenario where elapsed-so-far is useful is `status -f` joining an already-running build.

5. **No final Duration**: When a monitored build completes, there is no indication of how long the build took.

### Actual Output (`buildgit build`)

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #158
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     unknown
            ✗ Unknown commit
Started:    2026-02-13 09:11:25
Elapsed:    unknown

=== Build Info ===
  Started by:  Ralph AI Read Only
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/158/console

[09:11:31] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
...

Finished: SUCCESS
```

### Expected Output (`buildgit build`)

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #158
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Started:    2026-02-13 09:11:25
Commit:     552b265 - "nested job support, status for build by job jumber, better failure detection"
            ✓ Your commit (HEAD)

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/158/console

[09:11:31] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
...

Finished: SUCCESS
[09:14:39] Duration: 3m 14s
```

Note: `Commit`, `Agent`, `Pipeline`, and `Console` may be printed with a delay (appended below the initial header fields as they become available from the Jenkins API). There is no blank line separator between immediately-available and deferred fields.

## Required Changes

### 1. Remove Elapsed Field from Build Header

The `Elapsed` line is removed from the build header in all monitoring modes (`push`, `build`, `status -f`).

### 2. Running-Time Message for `status -f` Only

When `buildgit status -f` joins a build that is already in progress, display a message immediately after the BUILD IN PROGRESS banner (before the header fields):

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝
Job ralph1 #160 has been running for 14s

Job:        ralph1
Build:      #160
...
```

This message is only shown for `status -f`. It is never shown for `push` or `build` since those commands always start the build fresh.

### 3. Deferred Header Fields

When a monitoring-mode build header is printed, some fields may not be available from the Jenkins API yet (especially for `buildgit build` where the build was just triggered). The behavior is:

- **Print immediately**: Job, Build, Status, Trigger, Started (these come from the build API JSON and are always available)
- **Print when available**: Commit, Build Info block (Agent, Pipeline), Console URL

Deferred fields are appended below the initial header with no blank line separator, as if the header were being incrementally built. They are printed as soon as the data appears during the normal polling cycle.

Once all header fields have been printed, no further header updates occur — subsequent output is stage lines only.

### 4. Fetch Commit from Jenkins API

For `buildgit build` (and any case where the commit is not known from the local push), fetch the commit from the Jenkins build API:

1. Try `lastBuiltRevision.SHA1` from the build API JSON
2. Fall back to parsing console output for checkout patterns (`Checking out Revision`, `git checkout -f`)

Once obtained, print the Commit line in the header area (deferred if not immediately available). Match against local HEAD to show `✓ Your commit (HEAD)` or `✗ Does not match local HEAD` as usual.

### 5. Fix Snapshot Mode (`buildgit status`)

The `buildgit status` snapshot code path must pass `console_output` to the display function so that Agent and Pipeline are shown in the Build Info section. This is a bug fix — the data is already fetched but not passed through.

### 6. Add Duration Line at Build Completion

After the `Finished: <STATUS>` line, print a timestamped log line showing the total build duration:

```
Finished: SUCCESS
[09:14:39] Duration: 3m 14s
```

The duration is calculated from the Jenkins build API (`duration` field for completed builds, or `timestamp` to completion time). The timestamp prefix follows the existing log line format used for stage output.

This applies to all monitoring modes: `push`, `build`, and `status -f`.

## Scope

All changes apply to all build display modes unless otherwise noted:

| Change | `push` | `build` | `status -f` | `status` (snapshot) |
|--------|--------|---------|-------------|-------------------|
| Remove Elapsed from header | ✓ | ✓ | ✓ | ✓ |
| Running-time message | | | ✓ | |
| Deferred header fields | ✓ | ✓ | ✓ | N/A (snapshot has all data) |
| Fetch commit from Jenkins API | ✓ | ✓ | ✓ | ✓ |
| Fix console_output passthrough | | | | ✓ |
| Duration line at completion | ✓ | ✓ | ✓ | |

## Complete Example Outputs

### `buildgit push` (successful build)

```
To ssh://scranton2:2233/home/git/ralph1.git
   732740a..552b265  main -> main

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #157
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     552b265 - "nested job support, status for build by job jumber, better failure detection"
            ✓ Your commit (HEAD)
Started:    2026-02-13 09:04:35

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/157/console

[09:04:39] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[09:04:39] ℹ   Stage: [agent8_sixcore] Declarative: Agent Setup (<1s)
[09:04:55] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[09:04:55] ℹ   Stage: [agent8_sixcore] Build (<1s)
[09:07:52] ℹ   Stage: [agent8_sixcore] Unit Tests (2m 57s)
[09:07:52] ℹ   Stage: [agent8_sixcore] Deploy (<1s)

Finished: SUCCESS
[09:07:52] Duration: 3m 17s
```

### `buildgit build` (deferred fields)

Fields arrive incrementally. The user sees the header build up over 1-2 poll cycles:

**Immediately printed:**
```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #158
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Started:    2026-02-13 09:11:25
```

**After next poll cycle (console output now available), appended below:**
```
Commit:     552b265 - "nested job support, status for build by job jumber, better failure detection"
            ✓ Your commit (HEAD)

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/158/console
```

**Then stages and completion as normal:**
```
[09:11:31] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
...
Finished: SUCCESS
[09:14:39] Duration: 3m 14s
```

### `buildgit status -f` (joining in-progress build)

```
╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝
Job ralph1 #160 has been running for 14s

Job:        ralph1
Build:      #160
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     552b265 - "nested job support"
            ✓ Your commit (HEAD)
Started:    2026-02-13 09:20:00

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/160/console

[09:20:14] ℹ   Stage: [agent8_sixcore] Initialize Submodules (10s)
[09:20:14] ℹ   Stage: [agent8_sixcore] Build (<1s)
[09:23:12] ℹ   Stage: [agent8_sixcore] Unit Tests (2m 58s)
[09:23:12] ℹ   Stage: [agent8_sixcore] Deploy (<1s)

Finished: SUCCESS
[09:23:12] Duration: 3m 12s
```

### `buildgit status` (snapshot, completed build)

```
╔════════════════════════════════════════╗
║            BUILD COMPLETE              ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #157
Status:     SUCCESS
Trigger:    Automated (git push)
Commit:     552b265 - "nested job support, status for build by job jumber, better failure detection"
            ✓ Your commit (HEAD)
Started:    2026-02-13 09:04:35
Duration:   3m 17s

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/157/console

Stages:
  [agent8_sixcore] Declarative: Checkout SCM (<1s)
  [agent8_sixcore] Declarative: Agent Setup (<1s)
  [agent8_sixcore] Initialize Submodules (10s)
  [agent8_sixcore] Build (<1s)
  [agent8_sixcore] Unit Tests (2m 57s)
  [agent8_sixcore] Deploy (<1s)
```

Note: In snapshot mode for completed builds, `Duration` replaces `Elapsed` in the header (not as a log line, since there is no streaming output).

## Implementation Notes

### Root Cause: Missing console_output in Snapshot Mode

In `buildgit`, the `_jenkins_status_check` function fetches `console_output` but does not pass it to `display_building_output()`. The fix is to add it as the 10th parameter in the function call.

### Root Cause: Console Output Not Yet Available

When `buildgit build` triggers a new build, the Jenkins console output hasn't been written yet by the time the header is first displayed. The `_parse_build_metadata()` function in `jenkins-common.sh` extracts Agent from `Running on <agent>` and Pipeline from `Obtained ... from git ...` patterns — neither present in early console output.

### Deferred Header State Tracking

The monitoring loop needs to track which header fields have been printed. On each poll cycle, check if new data is available (console output now contains Agent/Pipeline, or API now has commit info). If so, print the deferred fields and mark them as printed. This state resets when monitoring a new build (relevant for `status -f` which watches multiple builds).

### Duration Calculation

For the final Duration line in monitoring mode, use the Jenkins `duration` field from the build API JSON (available once the build completes). Format using the existing duration formatting function (`format_duration` or equivalent).

For the snapshot mode Duration header field, use the same source.

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jenkins-common.sh` | Remove Elapsed from `display_building_output()`. Add deferred header field printing logic. Update `_parse_build_metadata()` to support incremental output. Add duration display function. |
| `skill/buildgit/scripts/buildgit` | Fix snapshot mode to pass `console_output`. Add deferred header tracking to monitoring loop. Add running-time message for `status -f`. Add Duration log line after `Finished`. Fetch commit from Jenkins API for `build` command. |

## Spec Rules Compliance

Per specs/README.md: changes to `buildgit status` must ensure `buildgit status`, `buildgit status -f`, and `buildgit status --json` remain consistent. The `--json` output should reflect:
- Removal of `elapsed` field (or set to null) when not meaningful
- Addition of `duration` field (in ms or formatted string) for completed builds
- Commit info populated from Jenkins API when available

## Testing

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| No Elapsed in monitoring header | Verify the `Elapsed:` line does not appear in monitoring output |
| Duration line after Finished | Verify `[HH:MM:SS] Duration: Xm Ys` appears after `Finished:` line |
| Running-time message for status -f | Verify `Job <name> #<num> has been running for Xs` appears for in-progress builds in follow mode |
| No running-time for push/build | Verify running-time message does NOT appear for push or build commands |
| Snapshot shows Agent/Pipeline | Verify `buildgit status` snapshot includes Agent and Pipeline in Build Info |
| Commit from Jenkins API | Verify commit is fetched from Jenkins API when not available from push context |
| Deferred fields printed | Verify that fields not available on first poll are printed on subsequent polls |
| Snapshot Duration field | Verify completed build snapshot shows `Duration:` in header instead of `Elapsed:` |
| JSON output consistency | Verify `--json` includes duration and commit fields |

### Manual Testing Checklist

- [ ] `buildgit push` — no Elapsed line, Duration printed after Finished
- [ ] `buildgit build` — Commit populated (possibly deferred), Agent/Pipeline appear, Duration printed
- [ ] `buildgit status -f` joining running build — running-time message shown, no Elapsed, Duration printed
- [ ] `buildgit status` snapshot — Agent/Pipeline shown in Build Info, Duration in header for completed builds
- [ ] `buildgit status --json` — consistent with above changes

## Related Specifications

- `unify-follow-log-spec.md` — Partially superseded (Elapsed field behavior changed)
- `buildgit-spec.md` — Base command specification
- `nested-jobs-display-spec.md` — Nested stage display (unaffected by this spec)
- `bug-json-stdout-pollution-spec.md` — JSON output changes (this spec adds duration/commit to JSON)
