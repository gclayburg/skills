## Add `--probe-all` flag to follow builds on any multibranch pipeline branch

- **Date:** `2026-03-14T12:05:14-06:00`
- **References:** `specs/done-reports/status-follow-new-all-branches.md`
- **Supersedes:** none
- **Plan:** `2026-03-14_status-follow-probe-all-branches-plan.md`
- **Chunked:** `true`
- **State:** `IMPLEMENTED`

## Problem Statement

When `implement-spec.sh` creates a new branch and pushes it to Jenkins, the user cannot easily monitor that build from another terminal. Running `buildgit status -f` defaults to the current git branch (typically `main`), not the new branch being built. The user would need to know the exact branch name and use `--job ralph1/<branch>` to follow it.

The user needs a way to say "follow whatever build starts next on any branch" without knowing the branch name in advance.

## Specification

### New flag: `--probe-all`

Add a `--probe-all` flag to `buildgit status` that is only valid when `-f` (follow) is also present. When active, instead of polling a single branch job for new builds, buildgit polls all branch sub-jobs under the multibranch pipeline and latches onto whichever build starts first.

### Flag validation

- `--probe-all` requires `-f` / `--follow`. If used without `-f`, emit an error to stderr and exit non-zero.
- `--probe-all` is incompatible with `--job <job>/<branch>` (explicit branch). If the user specifies both `--probe-all` and a branch-qualified `--job`, emit an error. Using `--job <job>` (top-level only, no branch) with `--probe-all` is allowed.
- `--probe-all` only applies to multibranch pipeline jobs. If the resolved job is a plain Pipeline (not multibranch), emit a warning to stderr and fall back to normal single-job follow behavior.

### Polling behavior

1. **Establish baselines:** Query the top-level multibranch job API to get all current branch sub-jobs and their latest build numbers. Store as a map: `{ "main": 85, "feature-x": 12, ... }`. Branches with no builds yet get baseline `0`.

2. **Poll loop:** On each poll cycle (every `POLL_INTERVAL` seconds), re-query the top-level multibranch API. For each branch:
   - If the branch is new (not in the baseline map), and it has a build, that's a new build — latch onto it.
   - If `lastBuild.number > baseline[branch]`, that's a new build — latch onto it.

3. **Latch:** Once a new build is detected on any branch, switch to monitoring that specific branch job (`ralph1/<branch>`) using the existing follow/monitoring logic. The remaining branches are ignored for this build.

4. **After build completes:**
   - If `--once` is present: exit (existing behavior).
   - If `--once` is NOT present: update the baseline for all branches (re-query the top-level API), then resume polling all branches for the next build.

### Jenkins API for multibranch branch listing

Use the top-level multibranch job API with a tree filter to minimize response size:

```
GET ${JENKINS_URL}/job/${JOB_NAME}/api/json?tree=jobs[name,lastBuild[number,timestamp,building]]
```

This returns all branch sub-jobs with their latest build info in a single API call. New branches appear in the `.jobs[]` array automatically after Jenkins branch indexing completes.

### Output messages

**Waiting state:**
```
[HH:MM:SS] ℹ Waiting for Jenkins build ralph1 (any branch) to start...
```

**Build detected:**
```
[HH:MM:SS] ℹ Build detected on branch 'feature-x' — following ralph1/feature-x #13
```
Then continue with the normal follow output for that build.

**Returning to probe-all after build completes (no `--once`):**
```
[HH:MM:SS] ℹ Waiting for Jenkins build ralph1 (any branch) to start...
```

### Interaction with existing flags

| Flag combination | Behavior |
|---|---|
| `status -f --probe-all` | Follow builds on any branch, loop indefinitely |
| `status -f --probe-all --once` | Follow first build on any branch, then exit |
| `status -f --probe-all --once=20` | Wait up to 20s for any-branch build, follow once, exit |
| `status -f --probe-all --line` | One-line follow mode with any-branch polling |
| `status -f --probe-all --json` | JSON follow mode with any-branch polling |
| `status -f --probe-all -n 5` | Show 5 prior builds (from current branch), then probe-all follow |
| `--threads status -f --probe-all` | Threads display with any-branch polling |
| `status -f --probe-all --prior-jobs 5` | Prior jobs from current branch, then probe-all follow |

### Commands affected

- `status -f`: gains `--probe-all` support
- `push`: NOT affected (always knows its branch)
- `build`: NOT affected (always knows its branch)

### Help text update

Add to the `status` command options:
```
  --probe-all           With -f: follow builds on any multibranch branch
```

Add examples:
```
  buildgit status -f --probe-all          # Follow next build on any branch
  buildgit status -f --probe-all --once   # Follow one build on any branch, then exit
```

## Test Strategy

### Unit tests (`test/buildgit_probe_all.bats`)

1. **`probe_all_requires_follow_flag`**: `status --probe-all` without `-f` exits with error on stderr.
2. **`probe_all_rejects_explicit_branch_job`**: `status -f --probe-all --job ralph1/main` exits with error.
3. **`probe_all_allows_top_level_job`**: `status -f --probe-all --job ralph1` is accepted (no error on option parsing).
4. **`probe_all_detects_new_build_on_existing_branch`**: Mock multibranch API returning two branches. On second poll, increment one branch's build number. Verify buildgit latches onto the correct branch.
5. **`probe_all_detects_new_branch`**: Mock multibranch API returning one branch initially. On second poll, add a second branch with a build. Verify buildgit detects and follows it.
6. **`probe_all_with_once_exits_after_build`**: Verify `--probe-all --once` exits after following one build.
7. **`probe_all_non_multibranch_warns_and_falls_back`**: Mock a plain Pipeline job. Verify warning on stderr and fallback to normal follow.
8. **`probe_all_waiting_message`**: Verify the "any branch" waiting message appears on stdout.
9. **`probe_all_shows_branch_detection_message`**: Verify the "Build detected on branch 'X'" message appears.

### Integration tests

- If integration test infrastructure supports multibranch jobs, add a test that pushes a new branch and verifies `status -f --probe-all --once` picks it up.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
