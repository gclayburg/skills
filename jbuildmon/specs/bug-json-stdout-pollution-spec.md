# Remove `git status` from `buildgit status`
Date: 2026-02-10T17:10:00-07:00
References: none
Supersedes: buildgit-spec.md (partially — removes `git status` from the `buildgit status` command)

## Problem Statement

`buildgit status --json` emits `git status` text and a blank-line separator to stdout before the JSON object, making the output unparseable by `jq` or any other JSON consumer:

```bash
$ ./buildgit status --json | jq .
jq: parse error: Invalid numeric literal at line 1, column 3
```

More broadly, the `git status` output in `buildgit status` adds no value:

1. **No code uses it.** The `git status` call is purely cosmetic — its output goes directly to the terminal and is never captured, parsed, or included in JSON output.
2. **Users already know `git status`.** Anyone using `buildgit` can run `git status` themselves. The value of `buildgit status` is the Jenkins build information, not duplicating a command the user already has.
3. **It pollutes stdout.** Even in non-JSON mode, mixing git status text with Jenkins output makes the combined output harder to parse or redirect.

## Required Behavior

### `buildgit status` no longer calls `git status`

The `buildgit status` command displays **only Jenkins build status**. The `git status` call and its blank-line separator are removed entirely, regardless of `--json`, `--follow`, or any other flags.

Users who want git status can run it separately:
```bash
git status && buildgit status
```

Or use the passthrough:
```bash
buildgit status    # Jenkins build status only
buildgit log -1    # Passthrough to git log
```

### Specific changes by mode

| Mode | Before | After |
|---|---|---|
| `buildgit status` | git status + blank line + Jenkins status | Jenkins status only |
| `buildgit status --json` | git status + blank line + JSON | JSON only |
| `buildgit status -f` | git status once + follow loop | follow loop only |

### Passthrough options removed

The `buildgit status` command previously accepted passthrough options like `-s` (short format) that were forwarded to `git status`. Since `git status` is no longer called, these passthrough options have been removed. Unrecognized options now raise an error, as `_parse_status_options` only accepts `--json` and `-f`/`--follow`.

### Error handling change

The current behavior when Jenkins is unavailable:
> Show git status, then display error for Jenkins portion

New behavior when Jenkins is unavailable:
> Display error for Jenkins portion (no git status)

## Implementation

### Change 1: Remove `git status` from `cmd_status()` snapshot mode

Remove the `git status` call and blank-line separator from `cmd_status()`:

```bash
# REMOVE these lines:
local git_exit_code=0
git status "${STATUS_GIT_ARGS[@]+"${STATUS_GIT_ARGS[@]}"}" || git_exit_code=$?
echo ""
```

And simplify the return code logic — it no longer needs to consider `git_exit_code`.

### Change 2: Remove `git status` from `cmd_status()` follow mode

Remove the `git status` call from the follow mode path:

```bash
# REMOVE this line:
git status "${STATUS_GIT_ARGS[@]+"${STATUS_GIT_ARGS[@]}"}" || true
```

### Change 3: Update help text and usage examples

In `show_usage()`, update the status command description and examples to remove references to "Git status":
- Change `"Display combined git and Jenkins build status"` to `"Display Jenkins build status"`
- Remove or update examples that reference git status output

### Change 4: Update tests

The following tests assert `git status` output (e.g., `assert_output --partial "On branch"`) and must be updated:

- `test/buildgit_status.bats`:
  - `status_shows_git_status` — remove or rewrite (git status no longer shown)
  - `status_shows_both_git_and_jenkins` — update to assert only Jenkins output
  - `status_passes_short_option` — remove (passthrough to git status no longer applies)
  - `status_json_mode` — remove assertion for "On branch"
  - `status_shows_git_when_jenkins_unavailable` — update to assert only error output

- `test/buildgit_errors.bats`:
  - Tests asserting `"On branch"` — remove those assertions

- `test/buildgit_routing.bats`:
  - Test using `"On branch"` to verify routing — find alternative assertion

- `test/buildgit_status_follow.bats`:
  - `follow_shows_git_status_at_start` — remove or rewrite

- `test/buildgit_verbosity.bats`:
  - Tests with `"git status output here"` — update if they test the git status display path
