# Bug: buildgit push Header Missing Commit Position and Agent Field

- **Date:** `2026-02-27T00:00:00-0700`
- **References:** `specs/done-reports/status-display-timing-issue`
- **Supersedes:** none (regression against `bug2026-02-13-build-monitoring-header-spec.md`)
- **State:** `IMPLEMENTED`

## Problem Statement

`buildgit push` produces a build monitoring header that is inconsistent with `buildgit status -f` in two ways:

1. **Commit printed in wrong position** — Commit appears after the Console URL (at the bottom of the header block), instead of in the header field group with Job/Build/Status/Trigger/Started.
2. **Agent missing** — The `=== Build Info ===` section omits the `Agent:` field, even though the same build viewed via `status -f` shows it correctly.

Both issues are regressions against `bug2026-02-13-build-monitoring-header-spec.md`, which defined the canonical header format and the deferred-field mechanism intended to resolve them.

## Observed Output

### `buildgit push` (incorrect)

```
[15:34:54] ℹ Starting

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #213
Status:     BUILDING
Trigger:    Automated (git push)
Started:    2026-02-27 15:34:54         ← Commit missing from header

=== Build Info ===
  Started by:  buildtriggerdude
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================                       ← Agent missing

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/213/console

Commit:     28ed879 - "test123"         ← wrong: should be in header above
            ✓ Your commit (HEAD)
```

### `buildgit status -f` (correct)

```
[15:34:57] ℹ Starting

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job ralph1 #213 has been running for 2s

Job:        ralph1
Build:      #213
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     28ed879 - "test123"         ← correct position
            ✓ Your commit (HEAD)
Started:    2026-02-27 15:34:54

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore           ← present
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/213/console
```

## Root Cause Analysis

### Issue 1: Commit printed after Console URL

`bug2026-02-13` introduced `_print_deferred_header_fields()` to append Commit and Build Info when console output becomes available. For `buildgit push`, the Commit is known from the push context (it is the HEAD commit that was just pushed), so it should be included in the initial header print — `_DEFERRED_COMMIT` should be `false`.

However, the actual output shows Commit appearing after Console URL, which means either:
- `cmd_push()` is not passing the commit SHA to the initial header display, causing `_DEFERRED_COMMIT=true`, and
- When `_print_deferred_header_fields()` later resolves the commit, it prints it after the Console URL has already been output (i.e., Console URL is being printed before deferred fields are resolved), or
- The Commit is being printed by a separate code path that runs after all deferred header fields have already been flushed.

For `buildgit status -f`, the build has been running for ~3 seconds by the time it starts, so console output is already available. The commit is resolved on the first poll cycle and printed in the correct header position.

The core bug: the Console URL is being printed before `_print_deferred_header_fields()` runs for `push`, and the Commit deferred print occurs after Console URL has already been flushed to output.

### Issue 2: Agent missing from Build Info in push

Both Agent and Pipeline come from `_parse_build_metadata()` which parses the Jenkins console output. Pipeline is present in `push` output but Agent is not, despite both coming from the same source.

This indicates that when `_print_deferred_header_fields()` resolves Build Info for `push`, the console output available at that moment contains the `Obtained Jenkinsfile from git...` line (Pipeline) but not the `Running on <agent>...` line (Agent).

In Jenkins, the `Running on <agent>` line appears early in console output (when the agent is assigned), before the SCM checkout. However, `Obtained Jenkinsfile` comes from the Declarative pipeline initialization. The fact that Pipeline appears but Agent does not suggests the console output at time of deferred resolution has Declarative output but the early agent assignment line may be absent, or the regex for Agent extraction is failing.

For `status -f`, which runs 3 seconds after the build starts, more console output is available by the time the header is printed, which is why Agent appears correctly there.

## Canonical Correct Output

Per `bug2026-02-13-build-monitoring-header-spec.md`, the correct `buildgit push` output is:

```
[HH:MM:SS] ℹ Starting

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #213
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     28ed879 - "test123"         ← in header, before Started
            ✓ Your commit (HEAD)
Started:    2026-02-27 15:34:54

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent8_sixcore           ← present
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/213/console
```

The output of `buildgit push`, `buildgit build`, and `buildgit status -f` must all match this format (accounting for the `status -f`-only running-time message, which is intentional and not a bug).

## Specification

### 1. Commit Placement Fix

For `buildgit push`: the commit SHA is available from the local git context at push time. It must be passed to the initial header display so that Commit appears in the header field group, not as a deferred field.

If for any reason the commit is not available at initial header print time (e.g., `buildgit build` which has no push context), the deferred mechanism must print Commit **before** Console URL, not after it. The order of deferred output must be:

```
Commit:     <sha> - "<msg>"             ← deferred commit (if not in initial header)
            <correlation line>

=== Build Info ===
  Started by:  <user>
  Agent:       <agent>                  ← deferred
  Pipeline:    <pipeline>               ← deferred
==================

Console:    <url>                       ← Console URL always last
```

Console URL must be the final item in the header block, printed only after all other deferred fields are resolved or a timeout has been reached.

### 2. Agent Field Fix

The Agent extraction from console output must be made more robust. Investigate why `Running on <agent>` is not being matched when Pipeline (`Obtained Jenkinsfile`) is present. Possible causes:

- The regex pattern for `Running on` does not match the actual console line format.
- The console output slice passed to `_parse_build_metadata()` does not include the early `Running on` line.
- The Agent field is extracted but not stored or passed through to the Build Info display.

Fix the Agent extraction so it reliably appears in Build Info for `push`, matching the behavior already working in `status -f`.

### 3. Consistency Requirement

All build monitoring commands must produce the same header field order and completeness:
- `buildgit push`
- `buildgit build`
- `buildgit status -f`

The only permitted difference is the `status -f`-specific running-time message (`Job ralph1 #213 has been running for Xs`), which is intentional.

### 4. Additional Inconsistency Check

During implementation, verify no other header fields differ between monitoring commands. Known intentional differences:
- Running-time message: `status -f` only.
- Deferred timing: `push` has commit immediately; `build` may defer commit.

Any field present in `status -f` output but absent in `push` or `build` output (beyond the running-time message) should be treated as a bug and fixed.

## Files Expected to Change

| File | Expected change |
|------|-----------------|
| `skill/buildgit/scripts/buildgit` | Fix `cmd_push()` to pass commit SHA to initial header. Fix Console URL to print after deferred fields. Fix or re-examine Agent extraction from console output. |
| `test/buildgit_status.bats` or `test/buildgit_push.bats` | Add regression tests per Test Strategy. |

## Acceptance Criteria

1. `buildgit push` shows Commit in the header field group (before Started), not after Console URL.
2. `buildgit push` shows Agent in the `=== Build Info ===` section.
3. `buildgit build` shows Commit and Agent (possibly deferred, but in correct order).
4. Console URL is always the last item printed in the header block.
5. Header field order for all monitoring commands matches the canonical format above.
6. `buildgit status -f` behavior is unchanged (it is already correct).

## Test Strategy

### Unit Tests (bats)

| Test Case | Description |
|-----------|-------------|
| `push_commit_in_header` | `buildgit push` output contains `Commit:` before `Console:` |
| `push_commit_not_after_console` | `buildgit push` output does not contain `Commit:` after `Console:` |
| `push_agent_in_build_info` | `buildgit push` output contains `Agent:` in Build Info section |
| `build_commit_before_console` | `buildgit build` deferred Commit appears before Console URL |
| `build_agent_in_build_info` | `buildgit build` output contains `Agent:` in Build Info section |
| `console_url_last_header_field` | Console URL is the last field printed in the header block for push and build |
| `push_status_f_header_consistency` | Header fields present in `status -f` also present in `push` output |

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
