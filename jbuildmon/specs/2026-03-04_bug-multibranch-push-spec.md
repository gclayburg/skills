## Fix `buildgit push` crash on multibranch pipeline with no explicit branch

- **Date:** `2026-03-04T10:54:22-0700`
- **References:** `specs/done-reports/bug-multibranch-push.md`
- **Supersedes:** none
- **State:** `DRAFT`

## Background

After implementing multibranch pipeline support (`2026-03-03_multibranch-pipeline-spec.md`), running `buildgit push` from the `main` branch on a multibranch project crashes with:

```
./buildgit: line 2259: args[@]: unbound variable
[10:43:17] ✗ Could not determine git branch for multibranch job 'ralph1'
[10:43:17] ✗ Cannot monitor Jenkins build - could not resolve Jenkins job
```

The git push itself succeeds, but Jenkins build monitoring fails. The workaround is `buildgit --job ralph1/main push`, which bypasses the broken code path. `buildgit status` works fine from the same branch.

## Root Cause Analysis

The crash occurs in `_infer_push_branch_from_args()` (line 2259 of buildgit).

### Code path

1. `buildgit push` is run with no extra arguments (no remote, no refspec).
2. `_parse_push_options` sets `PUSH_GIT_ARGS=()` — an **empty array**.
3. `cmd_push` → `_validate_jenkins_setup` → `_resolve_effective_job_name` detects `ralph1` is a multibranch job and hits the `push` case, calling `_infer_push_branch_from_args`.
4. Inside `_infer_push_branch_from_args`, line 2260 copies `PUSH_GIT_ARGS` into a local array using the `[@]+` guard:
   ```bash
   local args=("${PUSH_GIT_ARGS[@]+"${PUSH_GIT_ARGS[@]}"}")
   ```
   This correctly handles the empty `PUSH_GIT_ARGS`, but the resulting local `args` is itself an empty array `()`.
5. Line 2266 iterates the local array **without** the same guard:
   ```bash
   for arg in "${args[@]}"; do
   ```
   On Bash 3.2 (macOS default) with `set -u`, `${args[@]}` on an empty array triggers `unbound variable`.
6. The `|| true` in the caller suppresses the subshell crash, leaving `inferred_branch` empty, which produces the "Could not determine git branch" error.

### Why `status` works

`_resolve_effective_job_name` uses a different code path for `status` — it calls `_get_current_git_branch` (which runs `git rev-parse --abbrev-ref HEAD`) instead of `_infer_push_branch_from_args`. No array expansion, no crash.

### Why `--job ralph1/main push` works

When the branch is explicitly provided in the `--job` flag, `_resolve_effective_job_name` extracts it directly and never calls `_infer_push_branch_from_args`.

## Specification

### Fix: guard empty array iteration in `_infer_push_branch_from_args`

In `_infer_push_branch_from_args()`, add an early return when the args array is empty so the for-loop is never reached with an empty array:

```bash
_infer_push_branch_from_args() {
    local args=("${PUSH_GIT_ARGS[@]+"${PUSH_GIT_ARGS[@]}"}")
    ...

    # Short-circuit: no push args means no explicit refspec — use current branch
    if [[ "${#args[@]}" -eq 0 ]]; then
        _get_current_git_branch || return 1
        return 0
    fi

    for arg in "${args[@]}"; do
        ...
    done
    ...
}
```

This is the minimal, correct fix because:
- When there are no push arguments, the intent is always to push the current branch — the for-loop would find no positionals and fall through to `_get_current_git_branch` anyway.
- It avoids the Bash 3.2 `set -u` empty-array crash entirely.
- It preserves the existing behavior for all cases where push arguments are provided.

## Test Strategy

### Unit tests

1. **Push with no arguments on multibranch job**: Mock `_get_current_git_branch` to return `main`, set `PUSH_GIT_ARGS=()`, call `_infer_push_branch_from_args`, verify it returns `main`.
2. **Push with explicit remote+branch on multibranch job**: Set `PUSH_GIT_ARGS=(origin feature-x)`, call `_infer_push_branch_from_args`, verify it returns `feature-x`.
3. **Push with only remote (no refspec) on multibranch job**: Set `PUSH_GIT_ARGS=(origin)`, call `_infer_push_branch_from_args`, verify it falls through to `_get_current_git_branch`.

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
