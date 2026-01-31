# Bug: checkbuild.sh Silent Exit for Some Jenkins Jobs
Date: 2026-01-31

## Summary

`checkbuild.sh --job <jobname>` silently exits with code 1 for some Jenkins pipeline jobs without displaying build status, while working correctly for others. The script finds the job and build number but terminates after "Analyzing build details..." with no output.

## Observed Behavior

```bash
$ ./checkbuild.sh --job lifeminder
[12:15:37] ℹ Using specified job: lifeminder
[12:15:37] ℹ Verifying Jenkins connectivity...
[12:15:37] ✓ Connected to Jenkins
[12:15:37] ℹ Verifying job 'lifeminder' exists...
[12:15:37] ✓ Job 'lifeminder' found
[12:15:37] ℹ Fetching last build information...
[12:15:37] ✓ Build #156 found
[12:15:37] ℹ Analyzing build details...

# Script exits silently with exit code 1, no build status displayed
```

Similar behavior observed for `visualsync` job (build #1967).

## Expected Behavior

The script should display build status for all jobs, showing "Unknown" for values that cannot be determined:

```bash
$ ./checkbuild.sh --job lifeminder
[12:15:37] ℹ Using specified job: lifeminder
[12:15:37] ℹ Verifying Jenkins connectivity...
[12:15:37] ✓ Connected to Jenkins
[12:15:37] ℹ Verifying job 'lifeminder' exists...
[12:15:37] ✓ Job 'lifeminder' found
[12:15:37] ℹ Fetching last build information...
[12:15:37] ✓ Build #156 found
[12:15:37] ℹ Analyzing build details...

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        lifeminder
Build:      #156
Status:     SUCCESS
Trigger:    Unknown
Commit:     unknown
            ✗ Unknown commit
Duration:   ...
Completed:  ...
```

## Environment Context

- All affected jobs are Jenkins Pipeline jobs (not freestyle)
- All jobs use Git SCM
- Jobs may use different default branch names (`main` vs `master`)
- The current working directory may be an unrelated git repository
- The `--job` flag explicitly specifies the job name
- Builds show as successful in Jenkins web UI

## Root Cause Analysis

### Primary Cause: `set -euo pipefail` with Non-Zero Function Returns

The script uses `set -euo pipefail` (checkbuild.sh:20), which causes immediate exit when any command returns non-zero. Several functions return `1` to indicate "couldn't determine" conditions, which triggers silent script termination when called within command substitution.

### Affected Code Path #1: `detect_trigger_type`

**Location:** `lib/jenkins-common.sh:1070-1114`

**Called from:** `checkbuild.sh:255`
```bash
trigger_info=$(detect_trigger_type "$console_output")  # Exits if function returns 1
```

**Problem code** (lines 1092-1094):
```bash
# When no trigger pattern matches:
echo "unknown"
echo "unknown"
return 1  # <-- Causes set -e to exit the script
```

The function searches for patterns like "Started by user", "Started by an SCM change", "Started by timer", and "Started by upstream project". If none match, it returns `1`.

### Affected Code Path #2: `correlate_commit` (Invalid SHA)

**Location:** `lib/jenkins-common.sh:1683-1686`

**Called from:** `checkbuild.sh:271`
```bash
correlation_status=$(correlate_commit "$commit_sha")  # Exits if function returns 1
```

**Problem code:**
```bash
# Validate SHA format (7-40 hex characters)
if [[ ! "$sha" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
    echo "unknown"
    return 1  # <-- Causes set -e to exit the script
fi
```

If `extract_triggering_commit` returns "unknown" (because it couldn't find a commit SHA), this validation fails and returns `1`.

### Affected Code Path #3: `correlate_commit` (Git Failure)

**Location:** `lib/jenkins-common.sh:1690-1693`

**Problem code:**
```bash
head_sha=$(git rev-parse HEAD 2>/dev/null) || {
    echo "unknown"
    return 1  # <-- Causes set -e to exit the script
}
```

### Why Some Jobs Work and Others Don't

The console output format varies between Jenkins jobs. Jobs that work (like `msolitaire`) have console output containing recognized trigger patterns. Jobs that fail (like `lifeminder`, `visualsync`) have console output with different or missing trigger patterns.

When `detect_trigger_type` cannot match any pattern, it returns `1`, causing `set -e` to terminate the script before any build status is displayed.

## Investigation Steps

### Step 1: Verify Console Output Format

Check what the Jenkins console output looks like for a failing job:

```bash
curl -s -u "$JENKINS_USER_ID:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/lifeminder/156/consoleText" | head -20
```

Compare with a working job:

```bash
curl -s -u "$JENKINS_USER_ID:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/msolitaire/95/consoleText" | head -20
```

### Step 2: Test Trigger Detection in Isolation

```bash
source lib/jenkins-common.sh

# Fetch console output
console=$(curl -s -u "$JENKINS_USER_ID:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/lifeminder/156/consoleText")

# Test trigger detection (will show return code)
detect_trigger_type "$console"
echo "Return code: $?"
```

### Step 3: Test Commit Extraction

```bash
source lib/jenkins-common.sh

# Test commit extraction
commit_info=$(extract_triggering_commit "lifeminder" "156" "$console")
echo "Commit SHA: $(echo "$commit_info" | head -1)"
echo "Commit Msg: $(echo "$commit_info" | tail -1)"
```

### Step 4: Test Commit Correlation

```bash
source lib/jenkins-common.sh

# Test with "unknown" (simulating failed extraction)
correlate_commit "unknown"
echo "Return code: $?"

# Test with invalid format
correlate_commit "not-a-sha"
echo "Return code: $?"
```

## Affected Files

| File | Function | Line | Issue |
|------|----------|------|-------|
| `lib/jenkins-common.sh` | `detect_trigger_type()` | 1094 | Returns `1` when no trigger pattern matches |
| `lib/jenkins-common.sh` | `correlate_commit()` | 1686 | Returns `1` for invalid SHA format |
| `lib/jenkins-common.sh` | `correlate_commit()` | 1693 | Returns `1` when git rev-parse fails |

## Solution

### Principle

Functions that return "unknown" values should return `0` (success), not `1` (error). A return value of `1` should indicate an actual error that prevents continuing, not "couldn't determine this optional value."

### Change 1: Fix `detect_trigger_type` (line ~1094)

**Before:**
```bash
echo "unknown"
echo "unknown"
return 1
```

**After:**
```bash
echo "unknown"
echo "unknown"
return 0
```

### Change 2: Fix `correlate_commit` Invalid SHA (line ~1686)

**Before:**
```bash
if [[ ! "$sha" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
    echo "unknown"
    return 1
fi
```

**After:**
```bash
if [[ ! "$sha" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
    echo "unknown"
    return 0
fi
```

### Change 3: Fix `correlate_commit` Git Failure (line ~1693)

**Before:**
```bash
head_sha=$(git rev-parse HEAD 2>/dev/null) || {
    echo "unknown"
    return 1
}
```

**After:**
```bash
head_sha=$(git rev-parse HEAD 2>/dev/null) || {
    echo "unknown"
    return 0
}
```

## Testing Requirements

### Unit Tests

Add to `test/checkbuild.bats` or create `test/trigger_detection.bats`:

| Test Case | Description |
|-----------|-------------|
| `detect_trigger_type returns 0 for unknown` | Function returns 0 when no pattern matches |
| `correlate_commit returns 0 for unknown sha` | Function returns 0 when SHA is "unknown" |
| `correlate_commit returns 0 for invalid sha` | Function returns 0 when SHA format is invalid |
| `correlate_commit returns 0 for git failure` | Function returns 0 when not in a git repo |

### Integration Tests

| Test Case | Description |
|-----------|-------------|
| `checkbuild displays status for job with unknown trigger` | Script shows build status with "Unknown" trigger |
| `checkbuild displays status from unrelated directory` | Script shows build status when pwd is unrelated git repo |
| `checkbuild displays unknown commit gracefully` | Script shows "unknown" commit with "✗ Unknown commit" |

### Manual Verification

1. Run `./checkbuild.sh --job lifeminder` - should display build status
2. Run `./checkbuild.sh --job visualsync` - should display build status
3. Run from unrelated git directory with `--job` flag - should display build status

## Definition of Done

- [ ] `detect_trigger_type` returns `0` for unknown trigger type
- [ ] `correlate_commit` returns `0` for invalid/unknown SHA
- [ ] `correlate_commit` returns `0` when git operations fail
- [ ] `checkbuild.sh --job lifeminder` displays build status
- [ ] `checkbuild.sh --job visualsync` displays build status
- [ ] Unit tests added for return value changes
- [ ] Existing tests continue to pass
- [ ] Manual verification with affected jobs
