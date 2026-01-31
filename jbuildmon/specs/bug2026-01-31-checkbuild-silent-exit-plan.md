# Implementation Plan: checkbuild.sh Silent Exit Bug Fix

**Spec Reference:** [bug2026-01-31-checkbuild-silent-exit-spec.md](./bug2026-01-31-checkbuild-silent-exit-spec.md)

## Summary

This plan addresses the silent exit bug in `checkbuild.sh` where certain Jenkins pipeline jobs cause the script to exit with code 1 without displaying build status. The root cause is functions returning `1` (error) for "unknown/indeterminate" conditions, which triggers `set -e` termination.

## Contents

- [x] **Chunk A: Fix `detect_trigger_type` return value for unknown triggers**
- [x] **Chunk B: Fix `correlate_commit` return values for invalid SHA and git failures**

---

## Chunk Detail

### Chunk A: Fix `detect_trigger_type` return value for unknown triggers

#### Description

Modify the `detect_trigger_type` function to return `0` instead of `1` when no trigger pattern matches. The function currently returns `1` to indicate "couldn't determine trigger type," but this causes script termination under `set -e`. An unknown trigger is a valid outcome, not an error.

#### Spec Reference

See spec [Root Cause Analysis - Affected Code Path #1](./bug2026-01-31-checkbuild-silent-exit-spec.md#affected-code-path-1-detect_trigger_type) and [Solution - Change 1](./bug2026-01-31-checkbuild-silent-exit-spec.md#change-1-fix-detect_trigger_type-line-1094).

#### Dependencies

- None

#### Produces

- Modified `lib/jenkins-common.sh` (line ~1094)
- `test/trigger_detection.bats`

#### Implementation Details

1. Locate the `detect_trigger_type` function in `lib/jenkins-common.sh`:
   - Function starts at line 1070
   - The problematic code is at lines 1092-1094

2. Change the return value from `1` to `0`:
   - **Before:**
     ```bash
     echo "unknown"
     echo "unknown"
     return 1
     ```
   - **After:**
     ```bash
     echo "unknown"
     echo "unknown"
     return 0
     ```

3. Verify the function's docstring still accurately describes behavior:
   - Current docstring says "Returns 1 if trigger cannot be determined" (line 1069)
   - Update to: "Returns 0 always; outputs 'unknown' if trigger cannot be determined"

#### Test Plan

**Test File:** `test/trigger_detection.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `detect_trigger_type_returns_0_for_unknown` | Function returns 0 when no trigger pattern matches | Solution - Change 1 |
| `detect_trigger_type_outputs_unknown_for_no_match` | Function outputs "unknown" on both lines when no pattern matches | Solution - Change 1 |
| `detect_trigger_type_returns_0_for_user_trigger` | Function returns 0 for "Started by user" pattern (existing behavior) | Solution - Change 1 |
| `detect_trigger_type_returns_0_for_scm_trigger` | Function returns 0 for "Started by an SCM change" pattern (existing behavior) | Solution - Change 1 |
| `detect_trigger_type_returns_0_for_timer_trigger` | Function returns 0 for "Started by timer" pattern (existing behavior) | Solution - Change 1 |
| `detect_trigger_type_returns_0_for_upstream_trigger` | Function returns 0 for "Started by upstream project" pattern (existing behavior) | Solution - Change 1 |

**Mocking Requirements:**
- None; function takes console output as string parameter

---

### Chunk B: Fix `correlate_commit` return values for invalid SHA and git failures

#### Description

Modify the `correlate_commit` function to return `0` instead of `1` in two scenarios:
1. When the SHA format is invalid (not matching `^[a-fA-F0-9]{7,40}$`)
2. When `git rev-parse HEAD` fails (e.g., not in a git repository)

These conditions represent "cannot determine correlation" outcomes, not errors that should terminate the script.

#### Spec Reference

See spec [Affected Code Path #2](./bug2026-01-31-checkbuild-silent-exit-spec.md#affected-code-path-2-correlate_commit-invalid-sha), [Affected Code Path #3](./bug2026-01-31-checkbuild-silent-exit-spec.md#affected-code-path-3-correlate_commit-git-failure), [Solution - Change 2](./bug2026-01-31-checkbuild-silent-exit-spec.md#change-2-fix-correlate_commit-invalid-sha-line-1686), and [Solution - Change 3](./bug2026-01-31-checkbuild-silent-exit-spec.md#change-3-fix-correlate_commit-git-failure-line-1693).

#### Dependencies

- None

#### Produces

- Modified `lib/jenkins-common.sh` (lines ~1685 and ~1692)
- `test/correlate_commit.bats`

#### Implementation Details

1. Locate the `correlate_commit` function in `lib/jenkins-common.sh`:
   - Function starts at line 1673
   - First problematic code at lines 1683-1686 (invalid SHA check)
   - Second problematic code at lines 1690-1693 (git rev-parse failure)

2. Fix the invalid SHA check (lines 1683-1686):
   - **Before:**
     ```bash
     if [[ ! "$sha" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
         echo "unknown"
         return 1
     fi
     ```
   - **After:**
     ```bash
     if [[ ! "$sha" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
         echo "unknown"
         return 0
     fi
     ```

3. Fix the git rev-parse failure handler (lines 1690-1693):
   - **Before:**
     ```bash
     head_sha=$(git rev-parse HEAD 2>/dev/null) || {
         echo "unknown"
         return 1
     }
     ```
   - **After:**
     ```bash
     head_sha=$(git rev-parse HEAD 2>/dev/null) || {
         echo "unknown"
         return 0
     }
     ```

4. Verify function docstring accurately describes behavior:
   - Update any documentation that implies return 1 for these conditions

#### Test Plan

**Test File:** `test/correlate_commit.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `correlate_commit_returns_0_for_unknown_sha` | Function returns 0 when SHA is "unknown" | Solution - Change 2 |
| `correlate_commit_returns_0_for_empty_sha` | Function returns 0 when SHA is empty string | Solution - Change 2 |
| `correlate_commit_returns_0_for_invalid_sha_format` | Function returns 0 when SHA doesn't match hex pattern | Solution - Change 2 |
| `correlate_commit_outputs_unknown_for_invalid_sha` | Function outputs "unknown" for invalid SHA format | Solution - Change 2 |
| `correlate_commit_returns_0_for_git_failure` | Function returns 0 when not in a git repository | Solution - Change 3 |
| `correlate_commit_outputs_unknown_for_git_failure` | Function outputs "unknown" when git fails | Solution - Change 3 |
| `correlate_commit_returns_0_for_valid_scenarios` | Function returns 0 for valid SHA scenarios (existing behavior) | Solution |

**Mocking Requirements:**
- Test for git failure requires running from a non-git directory (use temp directory)
- Tests for valid commit scenarios require a git repository with commits

---

## Verification

After implementing both chunks, the following manual verification should pass:

```bash
# These jobs should display build status instead of silently exiting
./checkbuild.sh --job lifeminder
./checkbuild.sh --job visualsync

# Running from unrelated git directory should work
cd /tmp && /path/to/checkbuild.sh --job lifeminder
```

## Definition of Done

Per spec requirements:
- [ ] `detect_trigger_type` returns `0` for unknown trigger type
- [ ] `correlate_commit` returns `0` for invalid/unknown SHA
- [ ] `correlate_commit` returns `0` when git operations fail
- [ ] `checkbuild.sh --job lifeminder` displays build status
- [ ] `checkbuild.sh --job visualsync` displays build status
- [ ] Unit tests added for return value changes
- [ ] Existing tests continue to pass
