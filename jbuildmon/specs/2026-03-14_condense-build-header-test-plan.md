# Manual Test Plan: Condense build header and fix trigger/commit display

**Spec:** `2026-03-14_condense-build-header-spec.md`
**Purpose:** Verify the implemented spec by running `buildgit` against a real Jenkins server and checking output matches the specification.

## Prerequisites

- Jenkins server is reachable (`$JENKINS_URL` set)
- Jenkins credentials configured (`$JENKINS_USER_ID`, `$JENKINS_API_TOKEN`)
- At least one completed build exists for the `ralph1/main` job
- The build's commit SHA is reachable in local git history

## Test 1: Header layout — no Build Info box

**Command:**
```bash
buildgit status --all 2>&1 | head -20
```

**Verify:**
- [ ] Output does NOT contain `=== Build Info ===`
- [ ] Output does NOT contain `==================`
- [ ] Output does NOT contain `Started by:` as a separate field

## Test 2: Header field order and no blank lines

**Command:**
```bash
buildgit status --all 2>&1 | head -12
```

**Verify the header fields appear in this exact order with no blank lines between them:**
- [ ] `Job:` is first
- [ ] `Build:` immediately follows
- [ ] `Status:` immediately follows
- [ ] `Trigger:` immediately follows
- [ ] `Commit:` immediately follows (may have a second indented line for reachability)
- [ ] `Started:` follows (after optional commit reachability line)
- [ ] `Agent:` immediately follows
- [ ] `Console:` immediately follows
- [ ] No blank lines exist between any of these fields
- [ ] A blank line separates the header from the stages/test output below

## Test 3: Agent field is top-level

**Command:**
```bash
buildgit status --all 2>&1 | grep -E '^Agent:'
```

**Verify:**
- [ ] `Agent:` appears as a top-level field (starts at column 1, not indented under a box)
- [ ] Alignment matches other fields (value starts at same column as Job/Build/Status values — column 13)

## Test 4: Trigger display — manual build with known user

**Command:**
```bash
buildgit status --all 2>&1 | grep '^Trigger:'
```

**Verify:**
- [ ] Format is `Trigger:    Manual by <username>` (not `Manual (started by <username>)`)
- [ ] No empty parentheses or trailing "by " with no name
- [ ] Username is non-empty

## Test 5: Trigger display — SCM/push-triggered build

Find a build triggered by a push (not manual). Use relative build numbers to search:
```bash
for i in 0 -1 -2 -3 -4; do
  echo "--- Build $i ---"
  buildgit status "$i" --all 2>&1 | grep '^Trigger:'
done
```

**Verify (for any SCM-triggered build found):**
- [ ] Format is `Trigger:    SCM change` (not `Automated (git push)`)

## Test 6: Commit message shown

**Command:**
```bash
buildgit status --all 2>&1 | grep '^Commit:'
```

**Verify:**
- [ ] Format is `Commit:     <sha>  <first line of commit message>`
- [ ] SHA is 7 characters
- [ ] Commit message follows the SHA on the same line, separated by two spaces
- [ ] If the message is long, it is truncated with `...`

**Cross-check the commit message is correct:**
```bash
SHA=$(buildgit status --all 2>&1 | grep '^Commit:' | awk '{print $2}')
git log --format=%s -1 "$SHA"
```
- [ ] The message shown by buildgit matches (or is a truncated prefix of) the `git log` output

## Test 7: Commit reachability line preserved

**Command:**
```bash
buildgit status --all 2>&1 | grep -A1 '^Commit:'
```

**Verify:**
- [ ] Second line shows reachability status (e.g., `✓ In your history (reachable from HEAD)` or `✓ Your commit (HEAD)`)
- [ ] The reachability line is indented to align with the commit value (starts at column 13)

## Test 8: JSON output includes new fields

**Command:**
```bash
buildgit status --json 2>&1 | head -1 | jq '{triggerUser, commitMessage}'
```

**Verify:**
- [ ] `triggerUser` field exists (string, may be empty if trigger user is unknown)
- [ ] `commitMessage` field exists (string, first line of commit message, may be empty)
- [ ] `triggerUser` matches the user shown in the `Trigger:` line from `--all` output
- [ ] `commitMessage` matches the message shown on the `Commit:` line from `--all` output

## Test 9: JSON and --all output consistency

**Command:**
```bash
# Capture both outputs for the same build
BUILD_NUM=$(buildgit status --json 2>&1 | head -1 | jq -r '.build.number')
ALL_OUTPUT=$(buildgit status "$BUILD_NUM" --all 2>&1)
JSON_OUTPUT=$(buildgit status "$BUILD_NUM" --json 2>&1 | head -1)

echo "=== Trigger ==="
echo "  --all:  $(echo "$ALL_OUTPUT" | grep '^Trigger:')"
echo "  --json: $(echo "$JSON_OUTPUT" | jq -r '.triggerUser')"

echo "=== Commit ==="
echo "  --all:  $(echo "$ALL_OUTPUT" | grep '^Commit:')"
echo "  --json: $(echo "$JSON_OUTPUT" | jq -r '.commitMessage')"
```

**Verify:**
- [ ] Trigger user in JSON matches the name shown in the `Trigger:` line
- [ ] Commit message in JSON matches the message shown on the `Commit:` line

## Test 10: Monitoring mode header (follow mode)

**Command:**
```bash
# Trigger a build and capture the monitoring header
# (or use an in-progress build if one exists)
buildgit status -f --once=30 2>&1 | head -15
```

**Verify:**
- [ ] Monitoring mode uses the same condensed header format (no Build Info box)
- [ ] `Agent:` appears as top-level field (may be deferred if not yet known)
- [ ] `Trigger:` uses the new unified format
- [ ] `Commit:` shows the message (if available at monitoring time)
- [ ] No blank lines between header fields

## Test 11: Multiple build history with --prior-jobs

**Command:**
```bash
buildgit status --prior-jobs 3 --all 2>&1 | head -30
```

**Verify:**
- [ ] The main build header uses the new condensed format
- [ ] Prior build one-line summaries are unaffected by header changes

## Test 12: Trigger display — Unknown trigger

**Command:**
```bash
# Query the Jenkins API directly to find the trigger causes for the latest build
cat > /tmp/check_trigger.sh << 'SCRIPT'
#!/usr/bin/env bash
BUILD_URL="${JENKINS_URL}/job/ralph1/job/main/lastBuild/api/json"
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$BUILD_URL" | \
  jq '.actions[] | select(._class? | contains("CauseAction")) | .causes'
SCRIPT
bash /tmp/check_trigger.sh
```

**Verify:**
- [ ] The trigger cause class from the API matches what buildgit displays
- [ ] `UserIdCause` → `Manual by <userName>`
- [ ] `SCMTriggerCause` → `SCM change`
- [ ] `BranchIndexingCause` → `SCM change`
- [ ] `TimerTriggerCause` → `Timer`
- [ ] `UpstreamCause` → `Upstream`

## Test Summary

| # | Test | Pass/Fail | Notes |
|---|------|-----------|-------|
| 1 | No Build Info box | | |
| 2 | Field order, no blank lines | | |
| 3 | Agent top-level | | |
| 4 | Trigger — manual with user | | |
| 5 | Trigger — SCM change | | |
| 6 | Commit message shown | | |
| 7 | Commit reachability preserved | | |
| 8 | JSON new fields | | |
| 9 | JSON/--all consistency | | |
| 10 | Monitoring mode header | | |
| 11 | --prior-jobs format | | |
| 12 | Trigger cause API match | | |
