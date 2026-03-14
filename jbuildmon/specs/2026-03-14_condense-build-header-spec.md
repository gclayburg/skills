## Condense build header and fix trigger/commit display

- **Date:** `2026-03-14T15:42:48-06:00`
- **References:** `specs/todo/commit-msg-print.md`
- **Supersedes:** none
- **Plan:** `none`
- **Chunked:** `false`
- **State:** `DRAFT`

## Problem Statement

The build header section displayed by `buildgit status --all`, `buildgit status -f`, and other full-output modes has several cosmetic and functional issues:

### Bug 1: Trigger shows "Unknown"

When the Jenkins console output is empty, incomplete, or doesn't match expected patterns, `detect_trigger_type()` returns `"unknown"` and the header shows `Trigger: Unknown`.

### Bug 2: Trigger shows "Manual (started by )" with empty name

The trigger user extraction in `detect_trigger_type()` (`failure_analysis.sh` line ~659) uses `sed 's/^Started by user //'` on the console output. When the parsed username is empty (malformed line or different format), the display becomes `Manual (started by )` with a trailing empty space.

### Bug 3: Redundant trigger and "Started by:" fields

The trigger user is parsed and displayed in two separate places:
- `Trigger:` line in the header (from `_format_trigger_display()` in `output_render.sh`)
- `Started by:` line in the `=== Build Info ===` section (from `display_build_metadata()` in `failure_analysis.sh`)

These convey the same information but are classified and displayed differently, leading to inconsistency (e.g., `Trigger: Unknown` but `Started by: Ralph AI Read Only`).

### Bug 4: Commit message not shown

The commit SHA is displayed but the commit message is not, even when it could be resolved from the local git history.

### Bug 5: Header has unnecessary blank lines and boxed Build Info section

The `=== Build Info ===` / `==================` box adds visual noise and blank lines between sections make the header unnecessarily tall.

## Root Cause Analysis

### Trigger "Unknown" and empty name

`detect_trigger_type()` in `failure_analysis.sh` (lines ~630-674) parses the Jenkins console output for patterns like `"Started by user <username>"`, `"Started by an SCM change"`, etc. The function has two problems:

1. **No fallback to Jenkins API:** It relies exclusively on console text parsing. The Jenkins build API provides trigger cause data in the `actions[]` array (class `hudson.model.CauseAction` → `causes[]`), which is available immediately even when console output isn't. The function never queries this.

2. **No empty-name guard:** When the `sed` extraction produces an empty username, it's passed through to the display without validation.

### Redundant Started by

`_parse_build_metadata()` (line ~487) independently parses the same console pattern and stores it in `_META_STARTED_BY`. `display_build_metadata()` (line ~507) then displays it in the Build Info box. This is a separate code path from `detect_trigger_type()`, so they can disagree.

### Commit message

`extract_triggering_commit()` extracts the SHA but doesn't attempt to get the commit message from `git log` locally. The Jenkins API sometimes includes the message in `changeSet` data, but this isn't checked either.

## Specification

### 1. Condensed header layout

Remove the `=== Build Info ===` / `==================` boxed section and blank lines. Merge all fields into a flat, compact header with consistent alignment:

**Before:**
```
Job:        ralph1/main
Build:      #83
Status:     SUCCESS
Trigger:    Manual (started by )
Commit:     2ecd125
            ✓ In your history (reachable from HEAD)
Started:    2026-03-14 15:18:35

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent6 guthrie
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/job/main/83/console
```

**After:**
```
Job:        ralph1/main
Build:      #83
Status:     SUCCESS
Trigger:    Manual by Ralph AI Read Only
Commit:     2ecd125  implement: Standardize stdout/stderr output streams for buildgit
            ✓ In your history (reachable from HEAD)
Started:    2026-03-14 15:18:35
Agent:      agent6 guthrie
Console:    http://palmer.garyclayburg.com:18080/job/ralph1/job/main/83/console
```

Changes:
- Remove `=== Build Info ===` / `==================` box and its contents
- Move `Agent:` to a top-level field (same alignment as other fields)
- Remove `Started by:` line (merged into `Trigger:`)
- Remove all blank lines between header fields
- Remove blank line between header and Console URL
- The blank line before the stages section is preserved (visual separator before timestamped stage output)

### 2. Unified Trigger line

Merge trigger type and user into a single `Trigger:` line:

| Scenario | Display |
|---|---|
| Manual build with known user | `Trigger:    Manual by Ralph AI Read Only` |
| Manual build with unknown user | `Trigger:    Manual` |
| SCM change (push-triggered) | `Trigger:    SCM change` |
| Timer-triggered | `Trigger:    Timer` |
| Upstream project triggered | `Trigger:    Upstream` |
| Unknown trigger type | `Trigger:    Unknown` |

**Implementation approach:**

1. **Primary source: Jenkins API `causes[]`** — Query the build API JSON for `actions[].causes[]` (already available in `build_json`). Extract:
   - `_class` containing `UserIdCause` → Manual, get `userName` field
   - `_class` containing `SCMTriggerCause` → SCM change
   - `_class` containing `TimerTriggerCause` → Timer
   - `_class` containing `UpstreamCause` → Upstream
   - `_class` containing `BranchIndexingCause` → SCM change (multibranch scan)

2. **Fallback: console output parsing** — Keep existing `detect_trigger_type()` as fallback when API data isn't available.

3. **Guard against empty user** — If trigger type is manual but user is empty/unknown, display just `Manual` (no trailing "by" or empty parens).

### 3. Commit message on the Commit line

Display the first line of the commit message after the SHA on the same line:

```
Commit:     2ecd125  implement: Standardize stdout/stderr output streams
            ✓ In your history (reachable from HEAD)
```

**Resolution order for commit message:**

1. **Jenkins API `changeSet`/`changeSets`** — Check `build_json` for `.changeSets[].items[].msg` or `.changeSet.items[].msg`. Use the first line of the message matching the commit SHA.

2. **Local `git log`** — Run `git log --format=%s -1 <sha> 2>/dev/null` to get the subject line from the local repo. This works when the commit is reachable locally (which it is for your own builds).

3. **Omit if unavailable** — If neither source provides a message, display just the SHA (current behavior).

**Truncation:** If the commit message plus SHA exceeds the terminal width (or a reasonable max like 100 chars for the value portion), truncate the message with `...`.

### 4. Affected functions

All three display functions in `output_render.sh` must be updated:
- `display_success_output()`
- `display_failure_output()`
- `display_building_output()`

Additionally:
- `_format_trigger_display()` in `output_render.sh` — rewrite to use API causes first, console fallback second
- `_format_commit_display()` in `output_render.sh` — add commit message after SHA
- `display_build_metadata()` in `failure_analysis.sh` — remove (no longer needed)
- `_parse_build_metadata()` in `failure_analysis.sh` — keep for Agent extraction only, remove Started by parsing

### 5. JSON output

Update `json_output.sh` to include:
- `triggerUser` field (string, empty if unknown) — already may exist, verify
- `commitMessage` field (string, first line of commit message, empty if unavailable)

### 6. Monitoring mode header

The monitoring mode `_display_build_in_progress_banner` shows the same header. It must use the same condensed layout. The deferred header field mechanism (from `bug2026-02-13-build-monitoring-header-spec.md`) should still work — fields that aren't available yet are printed when they become available, but in the new flat format.

## Test Strategy

### Existing tests

Update tests that assert on the old header format:
- Tests checking for `=== Build Info ===` — remove or update assertions
- Tests checking for `Started by:` inside Build Info — update to check `Trigger:` line
- Tests checking for blank lines between header fields — update

### New tests in existing test files

1. **`test/buildgit_status.bats`:**
   - `status_trigger_manual_with_user`: Mock build with `UserIdCause` in API actions. Verify `Trigger:    Manual by <username>`.
   - `status_trigger_manual_no_user`: Mock build with empty userName. Verify `Trigger:    Manual` (no trailing "by" or empty parens).
   - `status_trigger_scm_change`: Mock build with `SCMTriggerCause`. Verify `Trigger:    SCM change`.
   - `status_trigger_unknown`: Mock build with no cause data and no console. Verify `Trigger:    Unknown`.
   - `status_commit_message_shown`: Mock build with known SHA reachable locally (or mock git log). Verify commit message appears after SHA.
   - `status_header_no_build_info_box`: Verify output does NOT contain `=== Build Info ===`.
   - `status_header_agent_inline`: Verify `Agent:` appears as a top-level field aligned with other fields.
   - `status_header_no_blank_lines`: Verify no blank lines between Job/Build/Status/Trigger/Commit/Started/Agent/Console.

2. **`test/buildgit_status_follow.bats`:**
   - `follow_monitoring_header_condensed`: Verify monitoring mode uses the condensed header format.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
