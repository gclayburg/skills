# Multibranch Pipeline Support

We need to support building feature branches on Jenkins, not just main. This is needed for the `implement-spec.sh` workflow where codex implements a spec on a feature branch in a worktree — we want to push that branch, have Jenkins build it, and monitor the results with buildgit.

## Current state

- Jenkins job `ralph1` is a single Pipeline job pointed at `main`
- All buildgit API URLs use `/job/${job_name}/...` which only works for simple Pipeline jobs
- `buildgit push` always monitors the single `ralph1` job regardless of which branch was pushed
- Job name is auto-detected from AGENTS.md (`JOB_NAME=ralph1`) or git origin URL

## What we want

- Push a feature branch (e.g. `change-buildgit-status-default`) and have Jenkins build it
- `buildgit push origin change-buildgit-status-default` should monitor that branch's build, not main's
- `buildgit status` should be branch-aware — show the current branch's build by default

## Jenkins change needed

Convert the `ralph1` job from a Pipeline job to a Multibranch Pipeline job. This means:

- Multibranch Pipeline scans the repo and creates a sub-job per branch
- Job URL structure changes: `/job/ralph1/job/main/`, `/job/ralph1/job/change-buildgit-status-default/`
- Branch names with `/` in them get URL-encoded in the path
- The existing `Jenkinsfile` works without changes
- Branch jobs are auto-created when pushed and auto-removed when branches are deleted
- Each branch has its own build history

## buildgit changes needed

### API URL path construction

Currently all API calls go to `/job/${job_name}/...`. For multibranch, the path becomes `/job/${job_name}/job/${branch_name}/...`.

The key function is `jenkins_api()` in `jenkins-common.sh`. Every endpoint that includes the job name needs to support the multibranch path format.

Examples:
- Pipeline job: `/job/ralph1/42/api/json`
- Multibranch job: `/job/ralph1/job/main/42/api/json`

### Job name format

For multibranch, the "full job name" should be `ralph1/main` or `ralph1/change-buildgit-status-default`. The `/` separates the folder (multibranch job) from the branch.

When constructing URLs, this needs to be translated:
- `ralph1/main` → `/job/ralph1/job/main/`
- `ralph1/feature-branch` → `/job/ralph1/job/feature-branch/`

### Branch auto-detection

`buildgit push` should auto-detect which branch is being pushed and monitor that branch's job. The branch can be inferred from:
1. The git push arguments (e.g. `buildgit push origin feature-branch`)
2. The current git branch (`git rev-parse --abbrev-ref HEAD`)

`buildgit status` (without `-j`) should default to the current git branch's job.

### Backward compatibility

The existing single Pipeline job behavior must continue to work. If the job is not a multibranch pipeline, buildgit should behave exactly as before.

Detection: query `/job/${job_name}/api/json` and check `_class` — multibranch jobs have class `org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject`, regular pipeline jobs have `org.jenkinsci.plugins.workflow.job.WorkflowJob`.

### --job flag

The `--job` flag should accept either:
- `ralph1` — simple job name (works for both pipeline types; for multibranch, auto-detects branch)
- `ralph1/feature-branch` — explicit multibranch job + branch

## Questions to resolve

- Should we keep the old `ralph1` Pipeline job around during migration, or replace it?
- Do we need to update the Jenkins webhook/post-receive hook to trigger multibranch scan instead of a specific job build?
- Should `buildgit build` (manual trigger) support triggering a specific branch build on multibranch?
