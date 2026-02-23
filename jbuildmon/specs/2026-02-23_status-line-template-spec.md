## Status Line Format Template

- **Date:** `2026-02-23T10:22:50-0700`
- **References:** `specs/done-reports/status-line-template.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Background

The `buildgit status --line` command currently outputs a fixed one-line format per build:

```
SUCCESS     Job phandlemono-IT #55 Tests=19/0/0 Took 5m 40s on 2026-02-23 (8 hours ago)
```

Users need the ability to customize which fields appear in the line output and in what order. For example, a user may want to see the git commit SHA instead of the job name, or include the branch that was built.

## Specification

### New `--format` option

Add a `--format <string>` option to the `status` subcommand. This option is only meaningful when `--line` mode is active (either explicit `--line` or implicit pipe/redirect). If `--format` is specified without `--line` being active, it implies `--line`.

When `--format` is not specified, the default format string is used (reproducing the current output exactly).

### Format placeholders

All placeholders produce **value only** — no labels or surrounding text. Labels like `Tests=`, `Took `, `on `, etc. are part of the format string itself, not the placeholder output.

| Placeholder | Field | Example value |
|---|---|---|
| `%s` | Build status (fixed-width, colorized on TTY) | `SUCCESS`, `FAILURE`, `IN_PROGRESS` |
| `%j` | Job name | `phandlemono-IT` |
| `%n` | Build number | `55` |
| `%t` | Test counts pass/fail/skip (colorized on TTY) | `19/0/0` or `?/?/?` |
| `%d` | Build duration | `5m 38s` |
| `%D` | Completion date (short) | `2026-02-22` |
| `%I` | Completion date (ISO 8601 with timezone) | `2026-02-22T14:30:00-0700` |
| `%r` | Relative time since completion | `10 hours ago` |
| `%c` | Git commit SHA (short, 7 chars) | `9b9d481` |
| `%b` | Git branch (short name, strip `refs/remotes/origin/` prefix) | `main` |
| `%%` | Literal `%` character | `%` |

### Default format string

The default format must reproduce the current `--line` output exactly:

```
%s Job %j #%n Tests=%t Took %d on %D (%r)
```

### Data sources

- **%s, %j, %n, %d, %D, %r**: Already available from the build JSON (`result`, `timestamp`, `duration`, `number`).
- **%t**: Already fetched from `testReport` API endpoint.
- **%I**: Derived from `timestamp + duration` (completion time), formatted as ISO 8601 with local timezone offset.
- **%c**: Git commit SHA from Jenkins build actions — use `lastBuiltRevision.SHA1` from the git SCM action (same source as `extract_triggering_commit` in `jenkins-common.sh`). Show first 7 characters. If unavailable, output `unknown`.
- **%b**: Git branch from Jenkins build actions — extract from `lastBuiltRevision.branch[].name` or from `buildsByBranchName` keys. Strip `refs/remotes/origin/` prefix. If multiple branches, use the first one. If unavailable, output `unknown`.

### Fetching commit and branch data

Commit SHA and branch name require data from the build JSON `actions` array (the git SCM action). The build JSON is already fetched by `_status_line_for_build_json()` — the git data must be extracted from it without additional API calls.

Create a helper function `_extract_git_info_from_build()` that takes the build JSON and sets two variables:
- `_LINE_COMMIT_SHA` — short (7-char) commit SHA, or `unknown`
- `_LINE_BRANCH_NAME` — short branch name, or `unknown`

This function is only called when the format string contains `%c` or `%b` (optimization: skip git extraction if neither placeholder is present).

### Format string parsing

Implement a function `_apply_line_format()` that:
1. Takes the format string and all field values as arguments.
2. Iterates through the format string character by character.
3. Replaces each `%X` placeholder with the corresponding value.
4. Leaves unknown `%X` sequences unchanged (literal pass-through) so typos are visible.
5. Replaces `%%` with a literal `%`.

### IN_PROGRESS builds

For in-progress builds, the format string is applied the same way, except:
- `%s` outputs `IN_PROGRESS` (with appropriate colorization).
- `%t` outputs `?/?/?`.
- `%d` outputs the elapsed time so far (e.g. `2m 15s`), same as the current behavior.
- `%D`, `%I`, `%r` are based on the build start time, not completion (since it hasn't completed). The labels in the default format change from `on`/`()` to `started`/`()`, but with a custom `--format`, the user controls the surrounding text so no label change is needed — the value is simply the start datetime.
- `%c` and `%b` may be available if the git SCM action has already populated (they are set at build start).

### Interaction with other flags

- `--format` is valid with `--line`, `-n`, `-f`, `--once`, `push --line`, and `build --line`.
- `--format` is not valid with `--json` (error: "cannot combine --format with --json").
- `--format` is not valid with `--all` (error: "cannot combine --format with --all").
- `--no-tests` still suppresses test API fetches; if `%t` is in the format string with `--no-tests`, it outputs `?/?/?`.

### --help update

Add `--format` to the status command help:

```
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests] [--format <fmt>]
```

Add format documentation to the help examples section:

```
Format placeholders for --format (use with --line):
  %s=status  %j=job  %n=build#  %t=tests  %d=duration
  %D=date  %I=iso8601  %r=relative  %c=commit  %b=branch  %%=literal%
  Default: "%s Job %j #%n Tests=%t Took %d on %D (%r)"
```

## Test Strategy

### Unit tests (bats)

1. **Default format produces current output** — Run `_status_line_for_build_json` with no `--format` and verify output matches the existing fixed format.
2. **Custom format string** — Provide `--format '%s #%n %c'` and verify only status, build number, and commit SHA appear in the correct order.
3. **Literal percent** — `--format '100%% #%n'` produces `100% #55`.
4. **Unknown placeholder passthrough** — `--format '%s %Z'` outputs the status followed by literal `%Z`.
5. **Commit SHA extraction** — Mock build JSON with git SCM action containing `lastBuiltRevision.SHA1` and verify `%c` outputs first 7 characters.
6. **Branch extraction** — Mock build JSON with `lastBuiltRevision.branch[].name` = `refs/remotes/origin/main` and verify `%b` outputs `main`.
7. **Missing git data** — Build JSON without git SCM action: `%c` and `%b` produce `unknown`.
8. **ISO 8601 date** — Verify `%I` outputs completion timestamp in ISO 8601 format with timezone offset.
9. **--format implies --line** — Running `status --format '%s #%n'` without explicit `--line` produces one-line output.
10. **--format + --json conflict** — Verify error message when both are specified.
11. **--format + --no-tests** — Verify `%t` shows `?/?/?` when `--no-tests` is active.
12. **Optimization: skip git fetch** — When format string does not contain `%c` or `%b`, the git extraction function is not called.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
