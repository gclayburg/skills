## Multibranch Pipeline Support for buildgit

- **Date:** `2026-03-03T15:39:16-0700`
- **References:** `specs/todo/feature-multibranch-pipeline.md`
- **Supersedes:** none
- **State:** `DRAFT`

## Background

buildgit currently assumes a single Jenkins Pipeline job per repository. All API URLs use the pattern `/job/${job_name}/...` which only works for simple Pipeline jobs. The Jenkins job `ralph1` is a Pipeline job pointed at the `main` branch.

To support the `implement-spec.sh` workflow — where a feature branch is created in a worktree, implemented by an AI agent, then pushed and built — Jenkins needs to build branches other than `main`, and buildgit needs to monitor the correct branch's build.

## Specification

### Part 1: Jenkins Multibranch Pipeline Job

#### 1.1 Create a new Multibranch Pipeline job

Create a new Jenkins job named `ralph1` of type **Multibranch Pipeline**. The existing Pipeline job `ralph1` should be renamed to `ralph1-legacy` and kept running during migration.

The Multibranch Pipeline job configuration:
- **Branch Sources:** Git, pointing at `ssh://git@scranton2:2233/home/git/ralph1.git`
- **Build Configuration:** Jenkinsfile from SCM (uses `Jenkinsfile` from each branch)
- **Scan Triggers:** Webhook trigger or periodic scan (1 minute interval as fallback)
- **Orphaned Item Strategy:** Discard old branches after 7 days of inactivity

#### 1.2 Update post-receive hook

The current post-receive hook (`jbuildmon/buildme.sh`) triggers a single Pipeline job build via `POST /job/${JOB}/build`. For Multibranch Pipeline, the trigger must instead request a **branch scan** so Jenkins discovers and builds the pushed branch.

**New trigger endpoint:** `POST /job/${JOB}/build?delay=0`

This is the same URL format but triggers a scan for Multibranch Pipeline jobs (vs. triggering a build for Pipeline jobs). The scan detects which branches changed and builds only those.

Alternatively, use the **Multibranch Scan Webhook Trigger** Jenkins plugin, which provides a dedicated webhook endpoint: `POST /multibranch-webhook-trigger/invoke?token=${JOB}`. This is more efficient as it tells Jenkins exactly which branch to check.

The post-receive hook should be updated to support both job types. Since the `buildme.sh` script takes the job name as an argument, no changes are needed to the script itself — the existing `POST /job/${JOB}/build` endpoint works for both Pipeline and Multibranch Pipeline jobs.

### Part 2: buildgit Multibranch Support

#### 2.1 Job name format for multibranch

Multibranch Pipeline jobs create sub-jobs per branch. The full job path in Jenkins URLs is:
- Pipeline: `/job/ralph1/`
- Multibranch: `/job/ralph1/job/main/`, `/job/ralph1/job/feature-branch/`

buildgit will accept job names in the format `<job>/<branch>`:
- `ralph1` — simple job name (auto-detect branch for multibranch, or use as-is for pipeline)
- `ralph1/main` — explicit multibranch job + branch
- `ralph1/feature-branch` — explicit multibranch job + specific branch

The `--job` global flag accepts both formats:
```bash
buildgit --job ralph1/main status
buildgit --job ralph1/feature-branch build
```

#### 2.2 URL path construction

Add a function to translate a job name into the correct Jenkins URL path segment:

| Input | URL path segment |
|-------|-----------------|
| `ralph1` (Pipeline) | `/job/ralph1` |
| `ralph1` (Multibranch, branch=main) | `/job/ralph1/job/main` |
| `ralph1/main` | `/job/ralph1/job/main` |
| `ralph1/feature-branch` | `/job/ralph1/job/feature-branch` |

Branch names containing special characters must be URL-encoded in the path (e.g. `/` in branch names becomes `%2F`).

All existing API endpoint functions (`get_build_info`, `get_console_output`, `get_all_stages`, `get_last_build_number`, `trigger_build`, etc.) must use this path construction instead of the current hardcoded `/job/${job_name}` pattern.

#### 2.3 Multibranch job detection

When a job name without a branch is provided (e.g. `ralph1`), buildgit must determine whether the job is a Pipeline or Multibranch Pipeline.

Query `${JENKINS_URL}/job/${job_name}/api/json` and check the `_class` field:
- `org.jenkinsci.plugins.workflow.job.WorkflowJob` → Pipeline (single job, use as-is)
- `org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject` → Multibranch (append branch)

Cache the result for the duration of the command to avoid repeated API calls.

#### 2.4 Branch auto-detection

When the job is detected as Multibranch and no explicit branch is provided via `--job job/branch`, auto-detect the branch:

1. **`buildgit push`**: Infer branch from git push arguments. If no branch argument given, use the current git branch (`git rev-parse --abbrev-ref HEAD`).
2. **`buildgit build`**: Use the current git branch.
3. **`buildgit status`**: Use the current git branch.
4. **`buildgit status -f`**: Use the current git branch.

The auto-detected branch is combined with the job name to form the full multibranch job path (e.g. `ralph1` + `feature-branch` → URL path `/job/ralph1/job/feature-branch`).

#### 2.5 Job discovery update

The `discover_job_name()` function currently returns a simple job name (e.g. `ralph1`). It does not need to change — the branch component is determined separately by the new multibranch detection logic.

The `JOB_NAME=ralph1` in AGENTS.md/CLAUDE.md continues to specify just the top-level job name. The branch is always auto-detected or explicitly provided via `--job`.

#### 2.6 `--job` flag behavior

| Flag value | Pipeline job | Multibranch job |
|------------|-------------|-----------------|
| `--job ralph1` | Use `ralph1` directly | Use `ralph1` + auto-detect branch |
| `--job ralph1/main` | Error: job `ralph1/main` not found | Use `ralph1`, branch `main` |
| (no flag) | Auto-discover `ralph1` | Auto-discover `ralph1` + auto-detect branch |

#### 2.7 Error handling

- If a multibranch job has no sub-job for the detected branch (branch not yet scanned), print a clear error: `Branch '<branch>' not found in multibranch job '<job>'. Push the branch and wait for Jenkins to scan.`
- If `--job ralph1/nonexistent` is given and the branch doesn't exist, same error.

#### 2.8 Backward compatibility

- Existing Pipeline jobs work exactly as before — no behavior change.
- The multibranch logic only activates when the job type is detected as Multibranch Pipeline.
- `JOB_NAME=ralph1` in project configuration files works for both job types.

### Part 3: Documentation updates

- Update `CLAUDE.md` (project root) to note that `ralph1` is now a Multibranch Pipeline job.
- Update `jbuildmon/skill/buildgit/references/buildgit-setup.md` to document multibranch support.
- Update `buildgit --help` text if any new options or behaviors are user-visible.
- Update `CHANGELOG.md` with the new multibranch feature.

## Test Strategy

### Unit tests
1. **URL construction**: Test that job name + branch combinations produce correct URL path segments.
2. **Job type detection**: Mock the Jenkins API response to return Pipeline vs Multibranch `_class` values; verify correct code path.
3. **Branch auto-detection**: Mock `git rev-parse --abbrev-ref HEAD` and verify branch is correctly appended.
4. **`--job` parsing**: Test `ralph1`, `ralph1/main`, `ralph1/feature/name` (nested branch) formats.
5. **Error cases**: Nonexistent branch on multibranch job, Pipeline job with `job/branch` format.
6. **Backward compatibility**: All existing tests must pass without modification (they use Pipeline job assumptions).

### Integration/manual tests
1. Push to `main` on multibranch job → builds and monitors correctly.
2. Push a feature branch → builds that branch, `buildgit push` monitors the correct build.
3. `buildgit status` on feature branch → shows that branch's latest build.
4. `buildgit --job ralph1/main status` from a feature branch → shows main's build.
5. `buildgit build` on feature branch → triggers that branch's build.
6. `buildgit status -f` on feature branch → follows that branch's builds.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
